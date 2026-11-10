# frozen_string_literal: true

require 'spec_helper'

describe 'tasks/code_manager.sh' do
  let(:harness) { ShellTaskHarness.new }
  let(:body) { '{"error":"FAKE"}' }

  before(:each) do
    # certname lookup goes through the PEADM_PUPPET_BIN seam
    harness.stub('puppet', 'echo primary.example.com')
    # The curl stub writes CURL_BODY to the -o file (or stdout without -o), prints
    # the HTTP code when asked with -w, and exits with CURL_EXIT. CURL_COMMIT_CODE
    # overrides the code for the file-sync commit endpoint only.
    harness.stub('curl', <<~'BASH')
      outfile=''
      writeout=''
      prev=''
      for arg in "$@"; do
        [ "$prev" = '-o' ] && outfile="$arg"
        [ "$prev" = '-w' ] && writeout="$arg"
        prev="$arg"
      done
      code="${CURL_HTTP_CODE:-200}"
      case "$*" in *file-sync/v1/commit*) code="${CURL_COMMIT_CODE:-$code}" ;; esac
      if [ -n "$outfile" ]; then printf '%s' "$CURL_BODY" > "$outfile"; else printf '%s' "$CURL_BODY"; fi
      [ -n "$writeout" ] && printf '%s' "$code"
      exit "${CURL_EXIT:-0}"
    BASH
    harness.stub('su', 'exit "${SU_EXIT:-0}"')
    harness.stub('systemctl', <<~BASH)
      case "$1" in
        list-units) echo "pe-puppetserver.service loaded failed failed PE Puppet Server" ;;
        status) echo "pe-puppetserver.service - status block for $2" ;;
      esac
    BASH
  end

  after(:each) { harness.cleanup }

  def run_task(action, env = {}, params = {})
    harness.run('code_manager.sh', { action: action }.merge(params),
                { 'PEADM_PUPPET_BIN' => File.join(harness.stubs, 'puppet'), 'CURL_BODY' => body }.merge(env))
  end

  context 'when the file-sync commit answers HTTP 500' do
    let(:result) { run_task('file-sync commit', 'CURL_HTTP_CODE' => '500') }

    # Catches a mutation that swallows an HTTP error status (the pre-fix behaviour:
    # the task exited 0 although nothing was committed).
    it 'exits non-zero' do
      expect(result[:status]).not_to eq(0)
    end

    # Catches a mutation that reports the failure without the method, URL path and HTTP code.
    it 'names the method, the URL path and the HTTP code' do
      expect(result[:stdout]).to include('POST /file-sync/v1/commit').and include('HTTP 500')
    end

    # Catches a mutation that drops the response body from the report.
    it 'prints the response body' do
      expect(result[:stdout]).to include('{"error":"FAKE"}')
    end

    # Catches a mutation that drops the failed-unit section.
    it 'lists the failed pe-* units' do
      expect(result[:stdout]).to include('--- systemctl status pe-puppetserver.service')
    end
  end

  context 'when the response body carries a secret' do
    let(:body) { '{"token":"FAKE-SECRET-tok","password":"FAKE-SECRET-pw","error":"nope"}' }

    # Catches a mutation that prints the body without the shared redaction filter.
    it 'never prints the planted secrets' do
      result = run_task('file-sync commit', 'CURL_HTTP_CODE' => '500')
      expect(result[:stdout] + result[:stderr]).not_to include('FAKE-SECRET')
    end
  end

  context 'when curl itself fails' do
    # Catches a mutation that ignores the curl exit code when no HTTP code came back.
    it 'exits non-zero and names the curl exit code' do
      result = run_task('file-sync commit', 'CURL_EXIT' => '7', 'CURL_HTTP_CODE' => '000')
      expect(result[:status]).not_to eq(0)
      expect(result[:stdout]).to include('curl exit 7')
    end
  end

  context 'when the API answers 2xx' do
    # Catches a mutation that treats HTTP 200 as a failure.
    it 'exits 0 for file-sync commit' do
      result = run_task('file-sync commit', 'CURL_HTTP_CODE' => '200', 'CURL_BODY' => '{"id":"abc"}')
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).not_to include('failed')
    end

    # Catches a mutation that treats HTTP 200 as a failure for force-sync.
    it 'exits 0 for file-sync force-sync' do
      result = run_task('file-sync force-sync', 'CURL_HTTP_CODE' => '200', 'CURL_BODY' => '{"status":"ok"}')
      expect(result[:status]).to eq(0)
    end

    # Catches a mutation that only accepts HTTP 200: the cache flush answers 204 with no body.
    it 'exits 0 for flush-environment-cache answering 204' do
      result = run_task('flush-environment-cache', 'CURL_HTTP_CODE' => '204', 'CURL_BODY' => '')
      expect(result[:status]).to eq(0)
    end
  end

  context 'when the environment cache flush fails' do
    # Catches a mutation that propagates failure from commit but not from the cache flush.
    it 'exits non-zero and names the DELETE endpoint' do
      result = run_task('flush-environment-cache', 'CURL_HTTP_CODE' => '503')
      expect(result[:status]).not_to eq(0)
      expect(result[:stdout]).to include('DELETE /puppet-admin-api/v1/environment-cache').and include('HTTP 503')
    end
  end

  context 'with the commit action' do
    # Catches a mutation where a failed commit is masked by the force-sync that follows it.
    it 'exits non-zero when the commit fails even though force-sync would succeed' do
      result = run_task('commit', 'CURL_COMMIT_CODE' => '500', 'CURL_HTTP_CODE' => '200')
      expect(result[:status]).not_to eq(0)
    end

    # Catches a mutation that stops after the commit and skips the force-sync.
    it 'runs commit and force-sync when both succeed' do
      result = run_task('commit')
      expect(result[:status]).to eq(0)
      expect(harness.calls('curl').map { |c| c[%r{/file-sync/v1/\S+}] }).to eq(['/file-sync/v1/commit', '/file-sync/v1/force-sync'])
    end
  end

  context 'with the deploy action' do
    # Catches a mutation that commits after r10k failed.
    it 'exits non-zero and does not call the API when r10k fails' do
      result = run_task('deploy production', 'SU_EXIT' => '1')
      expect(result[:status]).not_to eq(0)
      expect(harness.calls('curl')).to be_empty
    end

    # Catches a mutation that loses the commit failure behind a successful r10k run.
    it 'exits non-zero when r10k works but the commit fails' do
      result = run_task('deploy production', 'CURL_COMMIT_CODE' => '500')
      expect(result[:status]).not_to eq(0)
    end

    # Catches a mutation that breaks the happy deploy path.
    it 'exits 0 when r10k, commit and force-sync succeed' do
      expect(run_task('deploy production')[:status]).to eq(0)
    end
  end

  context 'with the verbose flag' do
    # Catches a mutation that drops the existing -v command echo.
    it 'echoes the curl command' do
      result = run_task('-v file-sync force-sync')
      expect(result[:stdout]).to include('command: curl')
    end
  end

  context 'with an unknown action' do
    # Catches a mutation that changes the usage exit code.
    it 'prints usage and exits 1' do
      result = run_task('nonsense')
      expect(result[:status]).to eq(1)
      expect(result[:stdout]).to include('Available subcommands')
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'

describe 'tasks/wait_until_service_ready.sh' do
  let(:harness) { ShellTaskHarness.new }
  let(:log_root) { File.join(harness.root, 'logs') }
  let(:puppetserver_log) { File.join(log_root, 'puppetserver', 'puppetserver.log') }
  let(:orchestrator_log) { File.join(log_root, 'orchestration-services', 'orchestration-services.log') }

  before(:each) do
    FileUtils.mkdir_p(File.dirname(puppetserver_log))
    FileUtils.mkdir_p(File.dirname(orchestrator_log))
    File.write(puppetserver_log, "boot line\nCA not ready yet\npassword=FAKE-SECRET-pw\nlast puppetserver line\n")
    File.write(orchestrator_log, "orchestrator last line\n")
    # The curl stub writes CURL_BODY to the -o file and prints the HTTP code for -w.
    # CURL_OK_ON makes the Nth call answer 200 (counted from the recorded calls).
    harness.stub('curl', <<~BASH)
      outfile=''
      prev=''
      for arg in "$@"; do
        [ "$prev" = '-o' ] && outfile="$arg"
        prev="$arg"
      done
      calls=$(wc -l < "#{File.join(harness.root, 'curl.calls')}")
      code="${CURL_HTTP_CODE:-503}"
      [ -n "$CURL_OK_ON" ] && [ "$calls" -ge "$CURL_OK_ON" ] && code=200
      [ -n "$outfile" ] && printf '%s' "$CURL_BODY" > "$outfile"
      printf '%s' "$code"
      exit "${CURL_EXIT:-0}"
    BASH
    harness.stub('sleep', 'exit 0')
    harness.stub('systemctl', <<~BASH)
      case "$1" in
        list-units) echo "pe-puppetserver.service loaded failed failed PE Puppet Server" ;;
        status) echo "pe-puppetserver.service - status block for $2" ;;
      esac
    BASH
  end

  after(:each) { harness.cleanup }

  def run_task(params, env = {})
    harness.run('wait_until_service_ready.sh', params, { 'PEADM_LOG_ROOT' => log_root }.merge(env))
  end

  context 'when the service never becomes ready' do
    let(:result) { run_task({ service: 'pe-master', port: '8140', timeout: 9, interval: 3 }, 'CURL_HTTP_CODE' => '503', 'CURL_BODY' => 'service unavailable') }
    let(:output) { result[:stdout] + result[:stderr] }

    # Catches a mutation that keeps the fixed 20 x 3 s loop and ignores the timeout parameter.
    it 'makes ceiling(timeout / interval) attempts' do
      result
      expect(harness.calls('curl').length).to eq(3)
    end

    # Catches a mutation that goes back to exiting silently (the pre-fix behaviour).
    it 'exits 1 and names the service, deadline and URL awaited' do
      expect(result[:status]).to eq(1)
      expect(output).to include('Timed out after 9s waiting for pe-master')
      expect(output).to include('https://localhost:8140/status/v1/simple/pe-master')
    end

    it 'reports the last HTTP result and response body' do
      expect(output).to include('HTTP 503')
      expect(output).to include('service unavailable')
    end

    it 'reports failed pe-* units and the service log tail' do
      expect(output).to include('pe-puppetserver.service')
      expect(output).to include('last puppetserver line')
    end

    # Catches a mutation that prints the service log without redaction.
    it 'does not print secrets from the service log' do
      expect(output).not_to include('FAKE-SECRET-pw')
    end
  end

  context 'when curl cannot connect' do
    # Catches a mutation that loses the curl exit code when no HTTP code came back.
    it 'reports the curl exit code and HTTP 000' do
      result = run_task({ service: 'pe-master', port: '8140', timeout: 3, interval: 3 }, 'CURL_EXIT' => '7', 'CURL_HTTP_CODE' => '000')
      expect(result[:status]).to eq(1)
      expect(result[:stdout]).to include('curl exit 7, HTTP 000')
    end
  end

  context 'when the service answers on the second attempt' do
    # Catches a mutation that polls the whole deadline instead of returning on the first 200.
    it 'exits 0 after 2 curl calls and prints no timeout report' do
      result = run_task({ service: 'pe-master', port: '8140', timeout: 30, interval: 3 }, 'CURL_OK_ON' => '2')
      expect(result[:status]).to eq(0)
      expect(harness.calls('curl').length).to eq(2)
      expect(result[:stdout] + result[:stderr]).not_to include('Timed out')
    end
  end

  context 'with the default parameters' do
    # Catches a mutation that changes today's 60 s behaviour (20 attempts, 3 s apart).
    it 'makes 20 attempts, sleeping 3 s between them' do
      result = run_task({ service: 'pe-master', port: '8140' })
      expect(result[:status]).to eq(1)
      expect(harness.calls('curl').length).to eq(20)
      expect(harness.calls('sleep').uniq.map { |line| line.split.last }).to eq(['3'])
      expect(result[:stdout]).to include('Timed out after 60s')
    end
  end

  context 'with a non-numeric timeout or interval' do
    # Catches a mutation that lets an unchecked value reach shell arithmetic (T-01-10).
    it 'rejects a non-numeric timeout before any curl call' do
      result = run_task({ service: 'pe-master', port: '8140', timeout: '5; touch pwned' })
      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include('timeout must be a positive whole number')
      expect(harness.calls('curl')).to be_empty
      expect(File.exist?(File.join(harness.root, 'pwned'))).to be(false)
    end

    it 'rejects a zero interval' do
      result = run_task({ service: 'pe-master', port: '8140', interval: 0 })
      expect(result[:status]).to eq(1)
      expect(result[:stderr]).to include('interval must be a positive whole number')
    end
  end

  context 'with the other services' do
    # Catches a mutation that queries the wrong status path for service=all.
    it 'queries /status/v1/simple for service all' do
      run_task({ service: 'all', port: '8140', timeout: 3, interval: 3 })
      expect(harness.calls('curl').first).to match(%r{https://localhost:8140/status/v1/simple$})
    end

    # Catches a mutation that drops the ca path or reports the wrong port for the CA wait.
    it 'queries /status/v1/simple/ca on port 8140 and honours the deadline for service ca' do
      result = run_task({ service: 'ca', port: '8140', timeout: 6, interval: 3 })
      expect(harness.calls('curl').length).to eq(2)
      expect(harness.calls('curl').first).to match(%r{https://localhost:8140/status/v1/simple/ca$})
      expect(result[:stdout]).to include('Timed out after 6s waiting for ca')
    end

    # Catches a mutation that reads the puppetserver log for the orchestrator service.
    it 'reports the orchestration-services log for orchestrator-service' do
      result = run_task({ service: 'orchestrator-service', port: '8143', timeout: 3, interval: 3 })
      expect(harness.calls('curl').first).to match(%r{https://localhost:8143/status/v1/simple/orchestrator-service$})
      expect(result[:stdout]).to include('orchestrator last line')
      expect(result[:stdout]).not_to include('last puppetserver line')
    end
  end
end

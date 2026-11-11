# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'

describe 'tasks/reinstall_pe.sh' do
  let(:harness) { ShellTaskHarness.new }
  let(:log_dir) { File.join(harness.root, 'installer-logs') }
  let(:installer_name) { 'puppet-enterprise-2025.12.1-el-8-x86_64' }
  let(:tarball) { File.join(harness.root, 'prebuilt', "#{installer_name}.tar.gz") }
  let(:log_lines) do
    (1..58).map { |n| "log line #{n}" } + ['password=FAKE-SECRET-pw-1 and https://user:FAKE-SECRET-userpass@host/x', 'last log line']
  end

  before(:each) do
    # Prebuild a real tarball whose top directory holds a fake installer, so the
    # task's real tar and cd steps run; only curl and the installer are fake.
    build_dir = File.join(harness.root, 'build', installer_name)
    FileUtils.mkdir_p(build_dir)
    installer = File.join(build_dir, 'puppet-enterprise-installer')
    File.write(installer, <<~BASH)
      #!/bin/bash
      mkdir -p "$PE_INSTALLER_LOG_DIR"
      cat > "$PE_INSTALLER_LOG_DIR/20260101.install.log" <<'LOG'
      #{log_lines.join("\n")}
      LOG
      exit "${FAKE_INSTALLER_EXIT:-0}"
    BASH
    FileUtils.chmod(0o755, installer)
    FileUtils.mkdir_p(File.dirname(tarball))
    _out, err, status = Open3.capture3('tar', 'czf', tarball, '-C', File.join(harness.root, 'build'), installer_name)
    raise "could not build the fake installer tarball: #{err}" unless status.success?

    # curl -O saves the download under its remote file name in the cwd.
    harness.stub('curl', <<~'BASH')
      [ "${CURL_EXIT:-0}" != 0 ] && exit "$CURL_EXIT"
      url=''
      for arg in "$@"; do url="$arg"; done
      cp "$CURL_TARBALL" "./$(basename "$url")"
    BASH
    harness.stub('uninstaller', 'exit 0')
    harness.stub('systemctl', <<~BASH)
      case "$1" in
        list-units) echo "pe-puppetdb.service loaded failed failed PE PuppetDB" ;;
        status) echo "pe-puppetdb.service - status block for $2" ;;
      esac
    BASH
  end

  after(:each) { harness.cleanup }

  def run_task(params = {}, env = {})
    harness.run('reinstall_pe.sh', { version: '2025.12.1', arch: 'el-8-x86_64' }.merge(params),
                { 'PE_INSTALLER_LOG_DIR' => log_dir, 'FAKE_INSTALLER_EXIT' => '6', 'CURL_TARBALL' => tarball,
                  'PEADM_PE_UNINSTALLER' => File.join(harness.stubs, 'uninstaller') }.merge(env))
  end

  context 'when the installer fails' do
    let(:result) { run_task }

    # Catches a mutation that swallows the installer exit code.
    it 'exits with the installer exit code' do
      expect(result[:status]).to eq(6)
    end

    # Catches a mutation that drops the report header or the exit code from it.
    it 'prints the failure header with the exit code' do
      expect(result[:stdout]).to include('=== Puppet Enterprise installer failed with exit code 6 ===')
    end

    # Catches a mutation that reports the head of the log instead of its tail.
    it 'includes the last line of the installer log' do
      expect(result[:stdout]).to include('last log line')
    end

    # Catches a mutation that drops the failed-unit section.
    it 'includes the status of a failed pe-* unit' do
      expect(result[:stdout]).to include('--- systemctl status pe-puppetdb.service')
    end

    # Catches a mutation that prints the log without redacting it.
    it 'never prints planted secrets' do
      expect(result[:stdout] + result[:stderr]).not_to include('FAKE-SECRET')
    end
  end

  context 'when the installer succeeds' do
    # Catches a mutation that prints the report on a clean run.
    it 'exits 0 and prints no report' do
      result = run_task({}, 'FAKE_INSTALLER_EXIT' => '0')
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).not_to include('failed with exit code')
    end
  end

  context 'when the download fails' do
    let(:result) { run_task({}, 'CURL_EXIT' => '22') }

    # Catches a mutation that carries on after a failed download (the task runs under set -e).
    it 'exits non-zero' do
      expect(result[:status]).not_to eq(0)
    end

    # Catches a mutation that runs an installer after a failed download.
    it 'never runs an installer' do
      expect(File.exist?(File.join(log_dir, '20260101.install.log'))).to be(false)
    end
  end

  context 'with the uninstall parameter' do
    # Catches a mutation that uninstalls PE when the operator did not ask for it.
    it 'never calls the uninstaller with uninstall=false' do
      run_task({ uninstall: false })
      expect(harness.calls('uninstaller')).to be_empty
    end

    # Catches a mutation that ignores uninstall=true.
    it 'calls the uninstaller with uninstall=true' do
      run_task({ uninstall: true })
      expect(harness.calls('uninstaller').first).to match(%r{uninstaller -p -d -y$})
    end

    # Catches a mutation that makes a failing uninstaller abort the reinstall (it is allowed to fail).
    it 'still reinstalls when the uninstaller fails' do
      harness.stub('uninstaller', 'exit 1')
      result = run_task({ uninstall: true }, 'FAKE_INSTALLER_EXIT' => '0')
      expect(result[:status]).to eq(0)
    end
  end

  context 'when report_log_lines is set' do
    # Catches a mutation that stops mapping report_log_lines onto the helper.
    it 'limits the log tail to that many lines' do
      result = run_task(report_log_lines: 5)
      expect(result[:stdout]).to include('--- Last 5 lines of')
      expect(result[:stdout]).not_to include('log line 50')
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

describe 'tasks/pe_install.sh' do
  let(:harness) { ShellTaskHarness.new }
  let(:log_dir) { File.join(harness.root, 'installer-logs') }
  let(:tarball) { File.join(harness.root, 'puppet-enterprise-2025.12.1-el-9-x86_64.tar.gz') }
  let(:planted_log_lines) do
    lines = (1..58).map { |n| "log line #{n}" }
    lines << 'console_admin_password: hunter2-FAKE-SECRET'
    lines << 'password=FAKE-SECRET-pw-1 fetching https://user:FAKE-SECRET-userpass@host/x'
    lines << 'last log line'
    lines
  end

  # Builds a real gzip tarball whose first entry is the installer as a file path
  # (no directory entry), so the task derives the installer directory from it.
  # The installer is a fake script that writes the planted log and exits with
  # FAKE_INSTALLER_EXIT.
  def build_tarball
    src = File.join(harness.root, 'src', 'puppet-enterprise-2025.12.1-el-9-x86_64')
    FileUtils.mkdir_p(src)
    installer = File.join(src, 'puppet-enterprise-installer')
    File.write(installer, <<~BASH)
      #!/bin/bash
      mkdir -p "$PE_INSTALLER_LOG_DIR"
      cat > "$PE_INSTALLER_LOG_DIR/20260101.install.log" <<'LOG'
      #{planted_log_lines.join("\n")}
      LOG
      exit "${FAKE_INSTALLER_EXIT:-0}"
    BASH
    FileUtils.chmod(0o755, installer)
    system('tar', '-C', File.join(harness.root, 'src'), '-czf', tarball,
           'puppet-enterprise-2025.12.1-el-9-x86_64/puppet-enterprise-installer', exception: true)
  end

  def stub_failed_unit
    harness.stub('systemctl', <<~BASH)
      case "$1" in
        list-units) echo "pe-puppetdb.service loaded failed failed PE PuppetDB" ;;
        status) echo "pe-puppetdb.service - status block for $2" ;;
      esac
    BASH
  end

  def run_task(params = {}, env = {})
    harness.run('pe_install.sh', { tarball: tarball }.merge(params),
                { 'PE_INSTALLER_LOG_DIR' => log_dir }.merge(env))
  end

  before(:each) { build_tarball }

  after(:each) { harness.cleanup }

  context 'when the installer fails' do
    let(:result) do
      stub_failed_unit
      run_task({}, { 'FAKE_INSTALLER_EXIT' => '6' })
    end

    # Catches a mutation that swallows the installer exit code, which would let
    # Bolt report a failed install as a success.
    it 'exits with the installer exit code' do
      expect(result[:status]).to eq(6)
    end

    # Catches a mutation that drops the report header or the exit code from it.
    it 'reports the exit code in the task output' do
      expect(result[:json]['_output']).to include('=== Puppet Enterprise installer failed with exit code 6 ===')
    end

    # Catches a mutation that reports the head of the log instead of the tail,
    # where the failure reason is.
    it 'includes the last line of the installer log' do
      expect(result[:json]['_output']).to include('last log line')
    end

    # Catches a mutation that drops the failed-unit section of the report.
    it 'includes the status of a failed pe-* unit' do
      expect(result[:json]['_output']).to include('--- systemctl status pe-puppetdb.service')
    end

    # Catches a mutation that prints the log without redacting it, which put
    # installer passwords into Bolt output and CI logs (P0-6 leaked them).
    it 'never prints planted secrets' do
      expect(result[:stdout] + result[:stderr]).not_to include('FAKE-SECRET')
    end

    # Catches a mutation that blanks the whole line instead of only the value,
    # which would hide which setting was involved.
    it 'keeps the non-secret part of a redacted line' do
      expect(result[:json]['_output']).to include('console_admin_password: [REDACTED]')
    end
  end

  context 'when the installer succeeds' do
    # Catches a mutation that prints the failure report on a clean install.
    it 'exits 0 and prints no report' do
      stub_failed_unit
      result = run_task({}, { 'FAKE_INSTALLER_EXIT' => '0' })
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).not_to include('failed with exit code')
    end
  end
end

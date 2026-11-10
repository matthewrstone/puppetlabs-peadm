# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

describe 'tasks/pe_reinstall.sh' do
  let(:harness) { ShellTaskHarness.new }
  let(:log_dir) { File.join(harness.root, 'installer-logs') }
  let(:installer_dir) { File.join(harness.root, 'puppet-enterprise-2025.12.1-el-9-x86_64') }
  let(:log_lines) do
    (1..58).map { |n| "log line #{n}" } + ['password=FAKE-SECRET-pw-1 and https://user:FAKE-SECRET-userpass@host/x', 'last log line']
  end

  before(:each) do
    FileUtils.mkdir_p(installer_dir)
    installer = File.join(installer_dir, 'puppet-enterprise-installer')
    File.write(installer, <<~BASH)
      #!/bin/bash
      mkdir -p "$PE_INSTALLER_LOG_DIR"
      cat > "$PE_INSTALLER_LOG_DIR/20260101.install.log" <<'LOG'
      #{log_lines.join("\n")}
      LOG
      exit "${FAKE_INSTALLER_EXIT:-0}"
    BASH
    FileUtils.chmod(0o755, installer)
    harness.stub('systemctl', <<~BASH)
      case "$1" in
        list-units) echo "pe-puppetdb.service loaded failed failed PE PuppetDB" ;;
        status) echo "pe-puppetdb.service - status block for $2" ;;
      esac
    BASH
  end

  after(:each) { harness.cleanup }

  def run_task(params = {}, exit_code = 6)
    harness.run('pe_reinstall.sh', { installer_dir: installer_dir, peconf: '/dummy/pe.conf' }.merge(params),
                { 'PE_INSTALLER_LOG_DIR' => log_dir, 'FAKE_INSTALLER_EXIT' => exit_code.to_s })
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

    # Catches a mutation that wraps the output in JSON, changing the plain-text
    # contract this task has (it does not source task_helper.sh).
    it 'keeps plain-text output' do
      expect(result[:json]).to be_nil
    end
  end

  context 'when the installer succeeds' do
    # Catches a mutation that prints the report on a clean run.
    it 'exits 0 and prints no report' do
      result = run_task({}, 0)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).not_to include('failed with exit code')
    end
  end

  context 'when the installer is missing' do
    # Catches a mutation that changes the existing not-found message or exit code.
    it 'exits 1 with the installer-not-found message' do
      missing = File.join(harness.root, 'nowhere')
      result = run_task({ installer_dir: missing })
      expect(result[:status]).to eq(1)
      expect(result[:stdout]).to include("Puppet Enterprise installer not found at #{missing}/puppet-enterprise-installer")
    end
  end

  context 'with puppet_service_ensure=stopped' do
    # Catches a mutation that drops the puppet stop, or moves it after the
    # report so a failed run leaves Puppet running.
    it 'stops puppet.service, also when the installer fails' do
      run_task({ puppet_service_ensure: 'stopped' })
      expect(harness.calls('systemctl')).to include(%r{stop puppet\.service$})
    end
  end

  context 'when report_log_lines is set' do
    # Catches a mutation that stops mapping report_log_lines onto the helper.
    it 'limits the log tail to that many lines' do
      result = run_task({ report_log_lines: 5 })
      expect(result[:stdout]).to include('--- Last 5 lines of')
      expect(result[:stdout]).not_to include('log line 50')
    end
  end
end

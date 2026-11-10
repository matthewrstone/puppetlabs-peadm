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
      [ -f "$PE_SYSTEMD_DROPIN_DIR/10-shortcircuit.conf" ] && touch "$PE_INSTALLER_LOG_DIR/dropin-present"
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

  context 'when the report size is overridden' do
    let(:result) do
      stub_failed_unit
      run_task({ report_log_lines: 7, report_unit_lines: 3 }, { 'FAKE_INSTALLER_EXIT' => '6' })
    end

    # Catches a mutation that stops mapping report_log_lines onto the helper.
    it 'limits the log tail to report_log_lines' do
      expect(result[:json]['_output']).to include('--- Last 7 lines of')
    end

    # Catches a mutation that stops mapping report_unit_lines onto the helper.
    it 'asks systemctl for report_unit_lines lines per failed unit' do
      result
      expect(harness.calls('systemctl')).to include(%r{status pe-puppetdb\.service --no-pager -l -n 3$})
    end

    # Catches a mutation that changes the documented defaults of 40 and 15.
    it 'uses 40 log lines and 15 unit lines by default' do
      stub_failed_unit
      default_result = run_task({}, { 'FAKE_INSTALLER_EXIT' => '6' })
      expect(default_result[:json]['_output']).to include('--- Last 40 lines of')
      expect(harness.calls('systemctl')).to include(%r{-n 15$})
    end
  end

  context 'with install_extra_large' do
    let(:dropin_dir) { File.join(harness.root, 'dropin') }
    let(:marker) { File.join(log_dir, 'dropin-present') }

    def stub_services(inactive: nil)
      harness.stub('systemctl', <<~BASH)
        case "$1" in
          is-active) [ "$3" = "#{inactive}.service" ] && exit 3; exit 0 ;;
          list-units) echo "pe-puppetdb.service loaded failed failed PE PuppetDB" ;;
          status) echo "status block for $2" ;;
        esac
      BASH
    end

    def run_extra_large(env = {})
      run_task({ install_extra_large: true }, { 'PE_SYSTEMD_DROPIN_DIR' => dropin_dir }.merge(env))
    end

    # Catches a mutation that treats the known XL installer exit 1 as a failure
    # even when the core services are up.
    it 'exits 0 when the installer exits 1 but all three services are active' do
      stub_services
      result = run_extra_large('FAKE_INSTALLER_EXIT' => '1')
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).not_to include('failed with exit code')
    end

    # Catches a mutation that skips the PuppetDB short-circuit or leaves it
    # behind, which would break PuppetDB start after the install.
    it 'writes the drop-in for the installer run and removes it afterwards' do
      stub_services
      run_extra_large('FAKE_INSTALLER_EXIT' => '1')
      expect(File.exist?(marker)).to be(true)
      expect(File.exist?(File.join(dropin_dir, '10-shortcircuit.conf'))).to be(false)
    end

    # Catches a mutation that skips the daemon-reload around the drop-in.
    it 'reloads systemd after writing and after removing the drop-in' do
      stub_services
      run_extra_large('FAKE_INSTALLER_EXIT' => '1')
      expect(harness.calls('systemctl').grep(%r{daemon-reload}).length).to eq(2)
    end

    # Catches a mutation that accepts a missing core service as success.
    it 'prints the report and exits with the installer code when a service is inactive' do
      stub_services(inactive: 'pe-orchestration-services')
      result = run_extra_large('FAKE_INSTALLER_EXIT' => '1')
      expect(result[:status]).to eq(1)
      expect(result[:json]['_output']).to include('=== Puppet Enterprise installer failed with exit code 1 ===')
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

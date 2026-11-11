# frozen_string_literal: true

require 'spec_helper'
require 'open3'

describe 'files/failure_report.sh' do
  let(:harness) { ShellTaskHarness.new }
  let(:helper) { File.join(ShellTaskHarness::REPO, 'files', 'failure_report.sh') }

  after(:each) { harness.cleanup }

  # Sources the helper in a fresh bash and runs the given command line.
  def bash(command, stdin = '', env = {})
    environment = { 'PATH' => "#{harness.stubs}:#{ENV.fetch('PATH', nil)}", 'LANG' => 'C' }.merge(env)
    stdout, stderr, status = Open3.capture3(environment, '/bin/bash', '-c', "source #{helper}; #{command}", stdin_data: stdin)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end

  def redact(text)
    bash('peadm_redact', text)[:stdout]
  end

  def key_block(label)
    ["-----BEGIN #{label}-----", 'FAKE-SECRET-keybody-line-1', 'FAKE-SECRET-keybody-line-2', "-----END #{label}-----"].join("\n")
  end

  def stub_failed_units(units)
    harness.stub('systemctl', <<~BASH)
      case "$1" in
        list-units) #{units.map { |u| "echo '#{u} loaded failed failed Description'" }.join('; ')} ;;
        status) echo "status of $2"; for n in $(seq 1 30); do echo "unit line $n"; done; echo "Authorization: Bearer FAKE-SECRET-unit" ;;
      esac
    BASH
  end

  describe 'peadm_redact' do
    ['RSA PRIVATE KEY', 'EC PRIVATE KEY', 'PRIVATE KEY', 'ENCRYPTED PRIVATE KEY'].each do |label|
      # Catches a mutation that narrows the BEGIN/END pattern so this key type
      # passes through with its body.
      it "collapses a #{label} block" do
        out = redact("before\n#{key_block(label)}\nafter\n")
        expect(out).not_to include('FAKE-SECRET')
        expect(out).to include("[REDACTED PRIVATE KEY]\nafter")
        expect(out).to start_with("before\n")
      end
    end

    # Catches a mutation that broadens the key rule to any BEGIN block, which
    # would hide certificates an operator needs to read.
    it 'passes a certificate block through unchanged' do
      cert = "-----BEGIN CERTIFICATE-----\nMIIBFAKEcertbody\n-----END CERTIFICATE-----\n"
      expect(redact(cert)).to eq(cert)
    end

    # Catches a mutation that hides the user name too, or the password not at all.
    it 'keeps the user and hides the password in a URL' do
      out = redact("fetching https://u:FAKE-SECRET-p@h/path\n")
      expect(out).to eq("fetching https://u:[REDACTED]@h/path\n")
    end

    ['X-Amz-Signature', 'X-Amz-Credential', 'X-Amz-Security-Token', 'sig', 'token', 'access_token', 'api_key'].each do |param|
      # Catches a mutation that drops this signed-URL query parameter from the rule.
      # Names such as token or credential also match the generic key rule, which
      # may redact the rest of the query string; that over-redaction is the
      # accepted safe direction, so only the host and path are asserted kept.
      it "hides the #{param} query value and keeps the URL host and path" do
        out = redact("GET https://host/f.tgz?a=1&#{param}=FAKE-SECRET-q&b=2\n")
        expect(out).not_to include('FAKE-SECRET')
        expect(out).to include('GET https://host/f.tgz?a=1&')
      end
    end

    ['Authorization: Bearer FAKE-SECRET-x', 'X-Authentication: FAKE-SECRET-x', 'Authorization: Basic FAKE-SECRET-x'].each do |header|
      # Catches a mutation that stops redacting this header form.
      it "hides the value of #{header.split(':').first} (#{header.split(' ')[1]})" do
        out = redact("#{header}\n")
        expect(out).not_to include('FAKE-SECRET')
        expect(out).to include(header.split(':').first)
      end
    end

    [
      'password=FAKE-SECRET-x',
      'passwd: FAKE-SECRET-x',
      '"console_admin_password": "FAKE-SECRET-x"',
      'secret=FAKE-SECRET-x',
      'private_key: FAKE-SECRET-x',
    ].each do |line|
      # Catches a mutation that stops redacting this key=value or key: value form.
      it "hides the value in #{line.split(%r{[=:]}).first.strip}" do
        out = redact("#{line}\n")
        expect(out).not_to include('FAKE-SECRET')
        expect(out).to include('[REDACTED]')
      end
    end

    # Catches a mutation that over-matches and mangles ordinary lines.
    it 'leaves an ordinary log line unchanged' do
      line = "2026-01-01 12:00:00 INFO Starting service pe-puppetserver on port 8140\n"
      expect(redact(line)).to eq(line)
    end
  end

  describe 'peadm_report_log_tail' do
    # Catches a mutation that tails before redacting: a key whose BEGIN line is
    # outside the window would then leak its body.
    it 'does not leak the body of a private key whose BEGIN line is outside the tail window' do
      lines = (1..100).map { |n| "log line #{n}" }
      lines[49] = '-----BEGIN RSA PRIVATE KEY-----'
      (50..68).each { |i| lines[i] = "FAKE-SECRET-body-#{i}" }
      lines[69] = '-----END RSA PRIVATE KEY-----'
      log = File.join(harness.root, 'big.log')
      File.write(log, lines.join("\n") + "\n")
      out = bash("peadm_report_log_tail #{log} 40")[:stdout]
      expect(out).not_to include('FAKE-SECRET')
      expect(out).to include('log line 100')
    end

    # Catches a mutation that ignores the size override.
    it 'prints exactly PEADM_REPORT_LOG_LINES log lines' do
      log = File.join(harness.root, 'ten.log')
      File.write(log, (1..10).map { |n| "line #{n}" }.join("\n") + "\n")
      out = bash("peadm_report_log_tail #{log}", '', 'PEADM_REPORT_LOG_LINES' => '5')[:stdout]
      expect(out.lines.map(&:chomp)).to eq(['--- Last 5 lines of ' + log, 'line 6', 'line 7', 'line 8', 'line 9', 'line 10'])
    end

    # Catches a mutation that changes the default size away from 40.
    it 'defaults to 40 lines' do
      log = File.join(harness.root, 'fifty.log')
      File.write(log, (1..50).map { |n| "line #{n}" }.join("\n") + "\n")
      out = bash("peadm_report_log_tail #{log}")[:stdout]
      expect(out.lines.length).to eq(41)
    end

    # Catches a mutation that prints an empty tail when there is no log.
    it 'says so when the log is missing' do
      out = bash("peadm_report_log_tail #{File.join(harness.root, 'nope.log')}")[:stdout]
      expect(out).to include('--- No log found at')
    end
  end

  describe 'peadm_report_failed_units' do
    # Catches a mutation that skips units after the first, or leaks the unit
    # status text without redaction (ExecStart lines can hold secrets).
    it 'prints a redacted status block for every failed unit' do
      stub_failed_units(['pe-puppetdb.service', 'pe-puppetserver.service'])
      out = bash('peadm_report_failed_units')[:stdout]
      expect(out).to include('--- systemctl status pe-puppetdb.service', '--- systemctl status pe-puppetserver.service')
      expect(out).not_to include('FAKE-SECRET')
    end

    # Catches a mutation that passes the wrong line count to systemctl.
    it 'asks systemctl for PEADM_REPORT_UNIT_LINES lines per unit' do
      stub_failed_units(['pe-puppetdb.service'])
      bash('peadm_report_failed_units', '', 'PEADM_REPORT_UNIT_LINES' => '3')
      expect(harness.calls('systemctl').last).to match(%r{status pe-puppetdb\.service --no-pager -l -n 3$})
    end

    # Catches a mutation that prints a section header when no unit failed.
    it 'prints nothing when no unit failed' do
      harness.stub('systemctl', 'true')
      expect(bash('peadm_report_failed_units')[:stdout]).to eq('')
    end
  end

  describe 'peadm_failure_report' do
    # Catches a mutation that drops the header, the title or the exit code.
    it 'prints the header, the log tail and the failed units' do
      stub_failed_units(['pe-puppetdb.service'])
      log = File.join(harness.root, 'one.install.log')
      File.write(log, "first\npassword=FAKE-SECRET-x\nlast\n")
      out = bash("peadm_failure_report 6 'Puppet Enterprise installer' #{log}")[:stdout]
      expect(out).to include('=== Puppet Enterprise installer failed with exit code 6 ===', 'last', '--- systemctl status pe-puppetdb.service')
      expect(out).not_to include('FAKE-SECRET')
    end
  end
end

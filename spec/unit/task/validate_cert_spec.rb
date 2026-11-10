# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require_relative '../../../tasks/validate_cert'

describe ValidateCert do
  # A plain `let`, matching the other task specs.
  let(:task) { described_class.new(params) }

  let(:dir) { Dir.mktmpdir('validate_cert_spec') }
  let(:ec_key) { OpenSSL::PKey::EC.generate('prime256v1') }
  let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:key_path) { File.join(dir, 'key.pem') }
  let(:cert_path) { File.join(dir, 'cert.pem') }
  let(:not_before) { Time.now - 3600 }
  let(:not_after) { Time.now + (365 * 86_400) }
  let(:params) { { 'cert_path' => cert_path, 'key_path' => key_path } }

  after(:each) { FileUtils.remove_entry(dir) }

  # Self-signed certificate over the given key, written to cert_path.
  def write_cert(key, not_before:, not_after:)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=test.example.com')
    cert.public_key = key
    cert.not_before = not_before
    cert.not_after = not_after
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    File.write(cert_path, cert.to_pem)
  end

  def run_task
    out = StringIO.new
    $stdout = out
    task.execute!
    JSON.parse(out.string)
  ensure
    $stdout = STDOUT
  end

  describe '#execute!' do
    before(:each) { File.write(key_path, ec_key.private_to_pem) }

    # Catches a mutation that breaks EC key loading again: the RSA-only
    # constructor raised `incorrect pkey type` for exactly this material.
    it 'reports no findings for an EC key and its self-signed EC certificate' do
      write_cert(ec_key, not_before: not_before, not_after: not_after)

      expect(run_task).to eq('ok' => true, 'findings' => [])
    end

    # Catches a mutation that skips check_private_key or inverts its result.
    it 'reports one key_mismatch error when the key belongs to a different certificate' do
      write_cert(rsa_key, not_before: not_before, not_after: not_after)

      result = run_task

      expect(result['ok']).to be(false)
      expect(result['findings'].map { |f| f['code'] }).to eq(['key_mismatch'])
      expect(result['findings'].first['severity']).to eq('error')
    end

    # Catches a mutation that drops the expiry comparison or loses the date
    # from the message the operator reads.
    it 'reports cert_expired with the expiry date for a certificate that expired yesterday' do
      expired = Time.now - 86_400
      write_cert(ec_key, not_before: expired - (365 * 86_400), not_after: expired)

      result = run_task

      expect(result['ok']).to be(false)
      expect(result['findings'].map { |f| f['code'] }).to eq(['cert_expired'])
      expect(result['findings'].first['message']).to include(expired.utc.strftime('%Y-%m-%d'))
    end

    # Catches a mutation that prints key bytes or the passphrase in a finding.
    it 'never prints key material or the passphrase' do
      write_cert(ec_key, not_before: not_before, not_after: not_after)
      File.write(key_path, ec_key.private_to_pem('aes-256-cbc', 'hunter2-FAKE-SECRET'))
      params['key_passphrase'] = 'wrong-FAKE-SECRET'

      out = run_task.to_json

      expect(out).not_to include('FAKE-SECRET')
      expect(out).not_to include('PRIVATE KEY')
    end
  end

  describe 'usage errors' do
    # Catches a mutation that treats a missing cert_path as "nothing to check"
    # and exits 0 with an empty findings list, which would look like a pass.
    it 'prints an _error with the usage kind and exits 1 when cert_path is missing' do
      task = described_class.new({})

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        .and output(a_string_including('"kind":"peadm/validate_cert-usage"')).to_stdout
    end

    # Catches a mutation that lets a negative warn_days through, which would
    # turn the expiry warning into a permanent no-op.
    it 'rejects a negative warn_days' do
      task = described_class.new('cert_path' => '/x', 'warn_days' => -1)

      expect { task.execute! }.to raise_error(SystemExit).and output(a_string_including('warn_days')).to_stdout
    end

    # Catches a mutation that lets unreadable parameters through as an empty hash.
    it 'prints an _error and exits 1 when the parameters are not JSON' do
      expect { described_class.run('not json') }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        .and output(a_string_including('peadm/validate_cert-usage')).to_stdout
    end
  end

  describe '.run' do
    # Catches a mutation that parses the JSON but never hands it to the task.
    it 'runs the checks on parsed parameters' do
      File.write(key_path, ec_key.private_to_pem)
      write_cert(ec_key, not_before: not_before, not_after: not_after)

      expect { described_class.run({ 'cert_path' => cert_path, 'key_path' => key_path }.to_json) }
        .to output(a_string_including('"ok":true')).to_stdout
    end
  end
end

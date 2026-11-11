# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../files/cert_check'

# All material is generated here with stdlib OpenSSL and written to a tmpdir;
# nothing is stubbed, so each example exercises the real OpenSSL behaviour.
# Named after the file it tests (files/cert_check.rb), the house rule for specs
# under spec/unit; RuboCop would derive peadm_cert_check from the module name.
# rubocop:disable RSpec/SpecFilePathFormat
describe PeadmCertCheck do
  let(:dir) { Dir.mktmpdir('cert_check_spec') }
  let(:now) { Time.now }
  let(:week) { 7 * 86_400 }
  let(:year) { 365 * 86_400 }

  let(:root_key) { OpenSSL::PKey::EC.generate('prime256v1') }
  let(:intermediate_key) { OpenSSL::PKey::EC.generate('prime256v1') }
  let(:leaf_key) { OpenSSL::PKey::EC.generate('prime256v1') }
  # The CAs are valid from well before the leaf, so a leaf that expired last
  # week was still issued inside its issuer's validity window.
  let(:root) { build_cert(subject: '/CN=Root CA', key: root_key, ca: true, serial: 10, not_before: now - (3 * year), not_after: now + (3 * year)) }
  let(:intermediate) do
    build_cert(subject: '/CN=Intermediate CA', key: intermediate_key, issuer: root, issuer_key: root_key, ca: true, serial: 11,
               not_before: now - (3 * year), not_after: now + (3 * year))
  end
  let(:leaf) { build_cert(subject: '/CN=leaf.example.com', key: leaf_key, issuer: intermediate, issuer_key: intermediate_key, serial: 12) }

  after(:each) { FileUtils.remove_entry(dir) }

  def path(name)
    File.join(dir, name)
  end

  def write(name, content)
    File.binwrite(path(name), content)
    path(name)
  end

  # Builds a certificate for `key`, signed by `issuer_key` (itself when no
  # issuer is given). A nil subject produces an empty subject name.
  def build_cert(key:, subject: nil, issuer: nil, issuer_key: nil, serial: 1, ca: false, not_before: now - 3600, not_after: now + year)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = serial
    cert.subject = subject ? OpenSSL::X509::Name.parse(subject) : OpenSSL::X509::Name.new
    cert.issuer = issuer ? issuer.subject : cert.subject
    cert.public_key = key
    cert.not_before = not_before
    cert.not_after = not_after
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = cert
    factory.issuer_certificate = issuer || cert
    cert.add_extension(factory.create_extension('basicConstraints', ca ? 'CA:TRUE' : 'CA:FALSE', true))
    cert.add_extension(factory.create_extension('keyUsage', 'keyCertSign, cRLSign', true)) if ca
    signing_key = issuer_key || key
    cert.sign(signing_key, OpenSSL::Digest.new('SHA256'))
    cert
  end

  def build_crl(issuer:, issuer_key:, revoked: [], last_update: now - 3600, next_update: now + week)
    crl = OpenSSL::X509::CRL.new
    crl.version = 1
    crl.issuer = issuer.subject
    crl.last_update = last_update
    crl.next_update = next_update
    revoked.each do |serial|
      entry = OpenSSL::X509::Revoked.new
      entry.serial = serial
      entry.time = now - 60
      crl.add_revoked(entry)
    end
    crl.sign(issuer_key, OpenSSL::Digest.new('SHA256'))
    crl
  end

  def codes(findings)
    findings.map { |f| f['code'] }
  end

  describe '.finding' do
    # Catches a mutation that renames a key of the finding hash, which every
    # consumer (the task, Phase 2 preflight, the CD4PE and SCM plans) reads.
    it 'builds the documented hash shape' do
      expect(described_class.finding('warn', 'some_code', 'text', '/p')).to eq(
        'severity' => 'warn', 'code' => 'some_code', 'message' => 'text', 'path' => '/p',
      )
    end
  end

  describe '.load_key' do
    # Catches a mutation back to OpenSSL::PKey::RSA.new, the RSA-only call that
    # raised `incorrect pkey type` for every other key type (CASE-032).
    it 'loads RSA, EC and Ed25519 keys in PEM and DER' do
      keys = [OpenSSL::PKey::RSA.new(2048), OpenSSL::PKey::EC.generate('prime256v1'), OpenSSL::PKey.generate_key('ED25519')]

      loaded = keys.flat_map { |k| [k.private_to_pem, k.private_to_der].map { |data| described_class.load_key(data) } }

      expect(loaded.map { |k| k.public_to_der }).to eq(keys.flat_map { |k| [k.public_to_der, k.public_to_der] })
    end

    # Catches a mutation that drops the passphrase argument.
    it 'decrypts an encrypted key with the passphrase' do
      pem = leaf_key.private_to_pem('aes-256-cbc', 's3cret')

      expect(described_class.load_key(pem, 's3cret').public_to_der).to eq(leaf_key.public_to_der)
    end

    # Catches a mutation that swallows the error, or lets Ruby prompt on the TTY
    # for a passphrase when none was given.
    it 'raises PKeyError for an encrypted key without a passphrase and for garbage' do
      expect { described_class.load_key(leaf_key.private_to_pem('aes-256-cbc', 's3cret')) }.to raise_error(OpenSSL::PKey::PKeyError)
      expect { described_class.load_key('garbage') }.to raise_error(OpenSSL::PKey::PKeyError)
    end
  end

  describe '.check certificate and key' do
    let(:cert_file) { write('leaf.pem', leaf.to_pem) }
    let(:key_file) { write('leaf.key', leaf_key.private_to_pem) }

    # Catches a mutation that reports a finding for a healthy certificate and key.
    it 'returns no findings for a valid certificate and its key' do
      expect(described_class.check(cert_path: cert_file, key_path: key_file)).to eq([])
    end

    # Catches a mutation that treats DER as a different, worse case than PEM.
    it 'gives the same findings for DER as for PEM' do
      der_cert = write('leaf.der', leaf.to_der)
      der_key = write('leaf.key.der', leaf_key.private_to_der)

      expect(described_class.check(cert_path: der_cert, key_path: der_key)).to eq(described_class.check(cert_path: cert_file, key_path: key_file))
      mismatched = described_class.check(cert_path: der_cert, key_path: write('other.der', OpenSSL::PKey::EC.generate('prime256v1').private_to_der))
      expect(codes(mismatched)).to eq(['key_mismatch'])
    end

    # Catches a mutation that assumes every key answers `private?`: an Ed25519
    # key is a generic OpenSSL::PKey::PKey without it. The certificate is signed
    # by the EC root because the openssl gem on older Rubies cannot sign a
    # certificate with an Ed25519 key; the subject key is what is under test.
    it 'accepts an Ed25519 key and its certificate' do
      ed_key = OpenSSL::PKey.generate_key('ED25519')
      ed_cert = build_cert(subject: '/CN=ed.example.com', key: ed_key, issuer: root, issuer_key: root_key)

      findings = described_class.check(cert_path: write('ed.pem', ed_cert.to_pem), key_path: write('ed.key', ed_key.private_to_pem))

      expect(findings).to eq([])
    end

    # Catches a mutation that compares only the key type, not the key pair.
    it 'reports key_mismatch for an RSA key against an EC certificate' do
      findings = described_class.check(cert_path: cert_file, key_path: write('rsa.key', OpenSSL::PKey::RSA.new(2048).private_to_pem))

      expect(codes(findings)).to eq(['key_mismatch'])
    end

    # Catches a mutation that lets a public-only PEM through as if it were the key.
    it 'reports a public key where a private key is required' do
      findings = described_class.check(cert_path: cert_file, key_path: write('pub.pem', leaf_key.public_to_pem))

      expect(codes(findings)).to eq(['key_parse_error'])
      expect(findings.first['message']).to include('public key')
    end

    context 'with an encrypted key' do
      let(:key_file) { write('enc.key', leaf_key.private_to_pem('aes-256-cbc', 'hunter2-FAKE')) }

      # Catches a mutation that reports an encrypted key as an opaque parse error.
      it 'reports key_encrypted without a passphrase' do
        findings = described_class.check(cert_path: cert_file, key_path: key_file)

        expect(codes(findings)).to eq(['key_encrypted'])
        expect(findings.first['message']).to include('needs a passphrase')
      end

      # Catches a mutation that ignores key_passphrase.
      it 'loads clean with the right passphrase' do
        expect(described_class.check(cert_path: cert_file, key_path: key_file, key_passphrase: 'hunter2-FAKE')).to eq([])
      end

      # Catches a mutation that echoes the passphrase into a finding.
      it 'reports key_encrypted for a wrong passphrase without printing it' do
        findings = described_class.check(cert_path: cert_file, key_path: key_file, key_passphrase: 'wrong-FAKE')

        expect(codes(findings)).to eq(['key_encrypted'])
        expect(findings.to_s).not_to include('FAKE')
      end
    end
  end

  describe '.check validity window' do
    # Catches a mutation that ignores the `now:` argument.
    it 'evaluates expiry at the supplied time' do
      cert_file = write('leaf.pem', leaf.to_pem)

      findings = described_class.check(cert_path: cert_file, now: now + (2 * year))

      expect(codes(findings)).to eq(['cert_expired'])
    end

    # Catches a mutation that warns outside the window, or errors instead of warning.
    it 'warns for a certificate expiring inside warn_days and stays quiet outside it' do
      soon = write('soon.pem', build_cert(subject: '/CN=soon', key: leaf_key, not_after: now + (10 * 86_400)).to_pem)

      warned = described_class.check(cert_path: soon, warn_days: 30)
      quiet = described_class.check(cert_path: soon, warn_days: 5)

      expect(warned.map { |f| [f['code'], f['severity']] }).to eq([['cert_expires_soon', 'warn']])
      expect(quiet).to eq([])
    end

    # Catches a mutation that drops the not_before comparison.
    it 'reports cert_not_yet_valid for a certificate valid from tomorrow' do
      future = write('future.pem', build_cert(subject: '/CN=future', key: leaf_key, not_before: now + 86_400).to_pem)

      expect(codes(described_class.check(cert_path: future))).to eq(['cert_not_yet_valid'])
    end

    # Catches a mutation that accepts an empty subject (an RFC 5280 corner that
    # PE does not support).
    it 'reports cert_empty_subject as an error' do
      empty = write('empty.pem', build_cert(key: leaf_key).to_pem)

      findings = described_class.check(cert_path: empty)

      expect(findings.map { |f| [f['code'], f['severity']] }).to eq([['cert_empty_subject', 'error']])
    end
  end

  describe '.check chain' do
    let(:cert_file) { write('leaf.pem', leaf.to_pem) }

    # Catches a mutation that treats every certificate in the bundle as a trust
    # anchor, or none of them, or splits the bundle on the wrong boundary.
    it 'verifies a leaf through an intermediate to a root' do
      chain = write('chain.pem', intermediate.to_pem + root.to_pem)

      expect(described_class.check(cert_path: cert_file, chain_path: chain)).to eq([])
    end

    # Catches a mutation that reports chain_unverified without OpenSSL's reason.
    it 'reports chain_unverified with the OpenSSL error string when the intermediate is missing' do
      chain = write('chain.pem', root.to_pem)

      findings = described_class.check(cert_path: cert_file, chain_path: chain)

      expect(codes(findings)).to eq(['chain_unverified'])
      expect(findings.first['message']).to match(%r{unable to get (local )?issuer certificate})
    end

    # Catches a mutation that trusts an intermediate without any root.
    it 'reports chain_unverified when the chain holds no root' do
      chain = write('chain.pem', intermediate.to_pem)

      expect(codes(described_class.check(cert_path: cert_file, chain_path: chain))).to eq(['chain_unverified'])
    end

    # Catches a mutation that verifies at Time.now with no clamp, which would
    # report the leaf's own expiry a second time as a chain failure.
    it 'reports an expired leaf once, as cert_expired' do
      expired = build_cert(subject: '/CN=old', key: leaf_key, issuer: intermediate, issuer_key: intermediate_key, not_before: now - (2 * year), not_after: now - 86_400)
      chain = write('chain.pem', intermediate.to_pem + root.to_pem)

      findings = described_class.check(cert_path: write('old.pem', expired.to_pem), chain_path: chain)

      expect(codes(findings)).to eq(['cert_expired'])
    end

    # Catches a mutation that stops verifying the chain's own validity.
    it 'reports chain_unverified when the intermediate has expired' do
      old_intermediate = build_cert(subject: '/CN=Intermediate CA', key: intermediate_key, issuer: root, issuer_key: root_key, ca: true, not_before: now - (2 * year), not_after: now - 86_400)
      chain = write('chain.pem', old_intermediate.to_pem + root.to_pem)

      findings = described_class.check(cert_path: cert_file, chain_path: chain)

      expect(codes(findings)).to eq(['chain_unverified'])
      expect(findings.first['message']).to include('expired')
    end

    # Catches a mutation that lets a chain file be a single DER certificate that fails to parse.
    it 'accepts a DER root as the chain' do
      self_signed = build_cert(subject: '/CN=self', key: leaf_key)

      findings = described_class.check(cert_path: write('self.pem', self_signed.to_pem), chain_path: write('root.der', self_signed.to_der))

      expect(findings).to eq([])
    end
  end

  describe '.check CRL' do
    let(:cert_file) { write('leaf.pem', leaf.to_pem) }

    # Catches a mutation that flags a healthy CRL.
    it 'returns no findings for a current CRL from the certificate issuer' do
      crl = build_crl(issuer: intermediate, issuer_key: intermediate_key)

      expect(described_class.check(cert_path: cert_file, crl_path: write('crl.pem', crl.to_pem))).to eq([])
    end

    # Catches a mutation that lets the opaque `no start line` OpenSSL error through
    # instead of naming the wrong header.
    it 'names the wrong BEGIN CRL header and the expected BEGIN X509 CRL' do
      crl = build_crl(issuer: intermediate, issuer_key: intermediate_key)
      wrong = crl.to_pem.sub('BEGIN X509 CRL', 'BEGIN CRL').sub('END X509 CRL', 'END CRL')

      findings = described_class.check(cert_path: cert_file, crl_path: write('crl.pem', wrong))

      expect(findings.map { |f| [f['code'], f['severity']] }).to eq([['crl_bad_header', 'error']])
      expect(findings.first['message']).to include('BEGIN X509 CRL')
    end

    # Catches a mutation that ignores next_update, or only reads PEM.
    it 'warns crl_stale for a CRL past its next_update, in PEM and DER' do
      stale = build_crl(issuer: intermediate, issuer_key: intermediate_key, last_update: now - (2 * week), next_update: now - week)

      [stale.to_pem, stale.to_der].each_with_index do |data, i|
        findings = described_class.check(cert_path: cert_file, crl_path: write("stale#{i}.crl", data))

        expect(findings.map { |f| [f['code'], f['severity']] }).to eq([['crl_stale', 'warn']])
      end
    end

    # Catches a mutation that never looks at the revoked list.
    it 'reports cert_revoked as an error when the CRL lists the certificate serial' do
      crl = build_crl(issuer: intermediate, issuer_key: intermediate_key, revoked: [leaf.serial])

      findings = described_class.check(cert_path: cert_file, crl_path: write('crl.pem', crl.to_pem))

      expect(findings.map { |f| [f['code'], f['severity']] }).to eq([['cert_revoked', 'error']])
    end

    # Catches a mutation that revokes on any non-empty revoked list.
    it 'ignores revoked serials that are not the certificate' do
      crl = build_crl(issuer: intermediate, issuer_key: intermediate_key, revoked: [9999])

      expect(described_class.check(cert_path: cert_file, crl_path: write('crl.pem', crl.to_pem))).to eq([])
    end

    # Catches a mutation that honours a serial match from a CRL issued by a
    # different CA, where the serial means nothing.
    it 'warns crl_issuer_mismatch, and does not revoke, for a CRL from another CA' do
      other_key = OpenSSL::PKey::EC.generate('prime256v1')
      other = build_cert(subject: '/CN=Other CA', key: other_key, ca: true)
      crl = build_crl(issuer: other, issuer_key: other_key, revoked: [leaf.serial])

      findings = described_class.check(cert_path: cert_file, crl_path: write('crl.pem', crl.to_pem))

      expect(findings.map { |f| [f['code'], f['severity']] }).to eq([['crl_issuer_mismatch', 'warn']])
    end
  end

  describe '.check with bad input' do
    let(:cert_file) { write('leaf.pem', leaf.to_pem) }
    let(:garbage) { write('garbage', "this is not a certificate\n") }
    let(:missing) { path('does-not-exist') }

    # Catches a mutation that lets an OpenSSL or file error escape as an exception.
    it 'turns garbage in each input into a finding instead of raising' do
      expect(codes(described_class.check(cert_path: garbage))).to eq(['cert_parse_error'])
      expect(codes(described_class.check(cert_path: cert_file, key_path: garbage))).to eq(['key_parse_error'])
      expect(codes(described_class.check(cert_path: cert_file, chain_path: garbage))).to eq(['chain_parse_error'])
      expect(codes(described_class.check(cert_path: cert_file, crl_path: garbage))).to eq(['crl_parse_error'])
    end

    # Catches a mutation that lets Errno::ENOENT or Errno::EISDIR escape.
    it 'turns an unreadable file in each input into a finding instead of raising' do
      expect(codes(described_class.check(cert_path: missing))).to eq(['cert_unreadable'])
      expect(codes(described_class.check(cert_path: cert_file, key_path: missing))).to eq(['key_unreadable'])
      expect(codes(described_class.check(cert_path: cert_file, chain_path: missing))).to eq(['chain_unreadable'])
      expect(codes(described_class.check(cert_path: cert_file, crl_path: dir))).to eq(['crl_unreadable'])
    end

    # Catches a mutation that stops checking the other inputs after the
    # certificate fails, hiding problems the operator could fix in one pass.
    it 'still reports key, chain and CRL problems when the certificate is unreadable' do
      findings = described_class.check(cert_path: missing, key_path: garbage, chain_path: garbage, crl_path: garbage)

      expect(codes(findings)).to eq(['cert_unreadable', 'key_parse_error', 'chain_parse_error', 'crl_parse_error'])
    end

    # Catches a mutation that includes the path in the message but drops the path field.
    it 'carries the offending path on each finding' do
      findings = described_class.check(cert_path: missing, key_path: garbage)

      expect(findings.map { |f| f['path'] }).to eq([missing, garbage])
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat

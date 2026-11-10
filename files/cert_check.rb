# frozen_string_literal: true

require 'openssl'
require 'time'

# Shared certificate, key and CRL checker (P1-10).
#
# One place that knows how to read PEM and DER material, RSA, EC and Ed25519
# keys, and how to turn what is wrong with them into structured findings. The
# caller decides what to do with the findings: a plan fails on an error, prints
# a warning on a warn (D-06). Tasks load it with
# `require_relative '../files/cert_check'`, and list
# `peadm/files/cert_check.rb` in their JSON `files` so Bolt ships it.
#
# Stdlib OpenSSL only. Findings carry codes, messages and paths, never key
# bytes or passphrases.
module PeadmCertCheck
  # Returns an OpenSSL::PKey::PKey for PEM or DER RSA, EC or Ed25519 data.
  # Raises OpenSSL::PKey::PKeyError when the data cannot be parsed.
  #
  # A String passphrase is always passed, empty when none was given, so that an
  # encrypted key fails with PKeyError instead of Ruby prompting on the TTY.
  def self.load_key(data, passphrase = nil)
    OpenSSL::PKey.read(data, passphrase || '')
  end

  # @return [Hash] { 'severity' => 'error'|'warn', 'code' => String, 'message' => String, 'path' => String|nil }
  def self.finding(severity, code, message, path = nil)
    { 'severity' => severity, 'code' => code, 'message' => message, 'path' => path }
  end

  # Reads the files, runs every applicable check and returns an Array of
  # finding hashes. An empty Array means nothing was found. Never raises for
  # bad input: every unreadable or unparseable file becomes a finding.
  def self.check(cert_path:, key_path: nil, chain_path: nil, crl_path: nil, warn_days: 30, key_passphrase: nil, now: Time.now)
    findings = []

    cert = read_certificate(cert_path, findings)
    check_certificate(cert, cert_path, warn_days, now, findings) if cert
    check_key(cert, cert_path, key_path, key_passphrase, findings) if key_path
    check_chain(cert, chain_path, now, findings) if chain_path
    check_crl(cert, crl_path, now, findings) if crl_path

    findings
  end

  # @return [String, nil] the file content, or nil after adding a finding
  def self.read_file(path, unreadable_code, what, findings)
    File.binread(path)
  rescue SystemCallError => e
    findings << finding('error', unreadable_code, "#{what} #{path} cannot be read: #{e.message}", path)
    nil
  end

  # @return [OpenSSL::X509::Certificate, nil]
  def self.read_certificate(path, findings)
    data = read_file(path, 'cert_unreadable', 'Certificate', findings)
    return nil unless data

    OpenSSL::X509::Certificate.new(data)
  rescue OpenSSL::X509::CertificateError => e
    findings << finding('error', 'cert_parse_error', "Certificate #{path} is not a valid PEM or DER certificate: #{e.message}", path)
    nil
  end

  def self.check_certificate(cert, path, warn_days, now, findings)
    findings << finding('error', 'cert_empty_subject', "Certificate #{path} has an empty subject", path) if cert.subject.to_a.empty?

    if now > cert.not_after
      findings << finding('error', 'cert_expired', "Certificate #{path} expired on #{cert.not_after.utc.iso8601}", path)
    elsif now < cert.not_before
      findings << finding('error', 'cert_not_yet_valid', "Certificate #{path} is not valid until #{cert.not_before.utc.iso8601}", path)
    elsif cert.not_after - now < warn_days * 86_400
      findings << finding('warn', 'cert_expires_soon', "Certificate #{path} expires on #{cert.not_after.utc.iso8601}, within #{warn_days} days", path)
    end
  end

  # Loads the key and checks that it belongs to the certificate.
  def self.check_key(cert, cert_path, key_path, passphrase, findings)
    data = read_file(key_path, 'key_unreadable', 'Key', findings)
    return unless data

    key = parse_key(data, key_path, passphrase, findings)
    return unless key && private_key?(key, key_path, findings)
    return unless cert

    return if cert.check_private_key(key)

    findings << finding('error', 'key_mismatch', "Key #{key_path} does not match certificate #{cert_path}", key_path)
  rescue OpenSSL::OpenSSLError => e
    findings << finding('error', 'key_mismatch', "Key #{key_path} cannot be compared with certificate #{cert_path}: #{e.message}", key_path)
  end

  # @return [OpenSSL::PKey::PKey, nil]
  def self.parse_key(data, key_path, passphrase, findings)
    load_key(data, passphrase)
  rescue OpenSSL::PKey::PKeyError => e
    if encrypted_pem?(data)
      what = passphrase.to_s.empty? ? 'needs a passphrase' : 'was not decrypted by the supplied passphrase'
      findings << finding('error', 'key_encrypted', "Key #{key_path} is encrypted and #{what}", key_path)
    else
      findings << finding('error', 'key_parse_error', "Key #{key_path} is not a valid PEM or DER private key: #{e.message}", key_path)
    end
    nil
  end

  def self.encrypted_pem?(data)
    data.match?(%r{BEGIN ENCRYPTED PRIVATE KEY|Proc-Type:\s*4,ENCRYPTED})
  end

  # Whether the loaded key holds a private part. RSA and EC answer `private?`;
  # an Ed25519 key is a generic OpenSSL::PKey::PKey with no such method, so it
  # is asked to serialise its private part instead.
  def self.private_key?(key, key_path, findings)
    has_private = if key.respond_to?(:private?)
                    key.private?
                  else
                    begin
                      key.private_to_der
                      true
                    rescue OpenSSL::PKey::PKeyError
                      false
                    end
                  end
    findings << finding('error', 'key_parse_error', "Key #{key_path} holds only a public key; a private key is required", key_path) unless has_private
    has_private
  end

  # Verifies the certificate against the chain file: self-signed certificates
  # in it are the trust anchors, the others are intermediates. OpenSSL decides
  # (X509::Store#verify); its error string goes into the finding.
  def self.check_chain(cert, chain_path, now, findings)
    data = read_file(chain_path, 'chain_unreadable', 'Chain', findings)
    return unless data

    certs = parse_bundle(data)
    if certs.empty?
      findings << finding('error', 'chain_parse_error', "Chain #{chain_path} holds no PEM or DER certificate", chain_path)
      return
    end
    return unless cert

    roots, intermediates = certs.partition { |c| c.subject == c.issuer }
    store = OpenSSL::X509::Store.new
    roots.each { |root| store.add_cert(root) }
    # Verify at a time the certificate itself is valid, so its own expiry is
    # reported once, by cert_expired, and this finding is about the chain. A
    # certificate is already expired at the second of its not_after, hence - 1.
    store.time = [[now, cert.not_before].max, cert.not_after - 1].min
    return if store.verify(cert, intermediates)

    findings << finding('error', 'chain_unverified', "Certificate is not verified by chain #{chain_path}: #{store.error_string}", chain_path)
  end

  # @return [Array<OpenSSL::X509::Certificate>] every certificate in a PEM
  #   bundle, or the single certificate when the data is DER; empty when neither
  def self.parse_bundle(data)
    pems = data.scan(%r{-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----}m)
    return pems.map { |pem| OpenSSL::X509::Certificate.new(pem) } unless pems.empty?

    [OpenSSL::X509::Certificate.new(data)]
  rescue OpenSSL::X509::CertificateError
    []
  end

  # Reports a CRL with the wrong PEM header by name, a stale CRL, a CRL from
  # another issuer, and a certificate the CRL revokes.
  def self.check_crl(cert, crl_path, now, findings)
    data = read_file(crl_path, 'crl_unreadable', 'CRL', findings)
    return unless data

    if data.include?('-----BEGIN CRL-----')
      findings << finding('error', 'crl_bad_header',
                          "CRL #{crl_path} has the header '-----BEGIN CRL-----'; the expected header is '-----BEGIN X509 CRL-----'", crl_path)
      return
    end

    crl = OpenSSL::X509::CRL.new(data)
    if crl.next_update && now > crl.next_update
      findings << finding('warn', 'crl_stale', "CRL #{crl_path} was due for renewal on #{crl.next_update.utc.iso8601}", crl_path)
    end
    check_revocation(cert, crl, crl_path, findings) if cert
  rescue OpenSSL::X509::CRLError => e
    findings << finding('error', 'crl_parse_error', "CRL #{crl_path} is not a valid PEM or DER CRL: #{e.message}", crl_path)
  end

  # A serial number only means something to the CA that issued it, so the
  # revoked list is consulted only when the CRL issuer is the certificate's.
  def self.check_revocation(cert, crl, crl_path, findings)
    if crl.issuer != cert.issuer
      findings << finding('warn', 'crl_issuer_mismatch', "CRL #{crl_path} was issued by #{crl.issuer}, not by the certificate's issuer #{cert.issuer}", crl_path)
    elsif crl.revoked.any? { |entry| entry.serial == cert.serial }
      findings << finding('error', 'cert_revoked', "Certificate with serial #{cert.serial} is revoked in CRL #{crl_path}", crl_path)
    end
  end

  private_class_method :read_file, :read_certificate, :check_certificate, :check_key, :parse_key, :encrypted_pem?, :private_key?,
                       :check_chain, :parse_bundle, :check_crl, :check_revocation
end

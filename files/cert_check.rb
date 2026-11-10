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
  # rubocop:disable Lint/UnusedMethodArgument -- chain_path and crl_path are wired up by the next commit of P1-10
  def self.check(cert_path:, key_path: nil, chain_path: nil, crl_path: nil, warn_days: 30, key_passphrase: nil, now: Time.now)
    findings = []

    cert = read_certificate(cert_path, findings)
    check_certificate(cert, cert_path, warn_days, now, findings) if cert
    check_key(cert, cert_path, key_path, key_passphrase, findings) if key_path

    findings
  end
  # rubocop:enable Lint/UnusedMethodArgument

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
    return unless key && cert

    return if cert.check_private_key(key)

    findings << finding('error', 'key_mismatch', "Key #{key_path} does not match certificate #{cert_path}", key_path)
  rescue OpenSSL::OpenSSLError => e
    findings << finding('error', 'key_mismatch', "Key #{key_path} cannot be compared with certificate #{cert_path}: #{e.message}", key_path)
  end

  # @return [OpenSSL::PKey::PKey, nil]
  def self.parse_key(data, key_path, passphrase, findings)
    load_key(data, passphrase)
  rescue OpenSSL::PKey::PKeyError => e
    findings << finding('error', 'key_parse_error', "Key #{key_path} is not a valid PEM or DER private key: #{e.message}", key_path)
    nil
  end

  private_class_method :read_file, :read_certificate, :check_certificate, :check_key, :parse_key
end

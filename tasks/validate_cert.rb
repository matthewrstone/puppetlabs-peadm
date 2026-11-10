#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

# Puppet Task Name: validate_cert
require 'json'
require_relative '../files/cert_check'

# ValidateCert task class: runs the shared PeadmCertCheck over the supplied
# paths and prints { "ok": <no error findings>, "findings": [...] }.
#
# The task exits 0 whenever the checks ran, so the calling plan decides whether
# a finding fails the run or only warns (D-06). Only a usage error exits 1.
class ValidateCert
  STRING_PARAMS = ['cert_path', 'key_path', 'chain_path', 'crl_path', 'key_passphrase'].freeze

  # Parses the task's JSON parameters and runs the task.
  def self.run(input)
    params = parse(input)
    usage_error('Task parameters must be a JSON object') unless params.is_a?(Hash)
    new(params).execute!
  end

  def self.parse(input)
    JSON.parse(input)
  rescue JSON::ParserError => e
    usage_error("Task parameters are not valid JSON: #{e.message}")
  end

  # Usage errors are reported as an _error object, the shape Bolt reads.
  def self.usage_error(message)
    puts({ '_error' => { 'msg' => message, 'kind' => 'peadm/validate_cert-usage' } }.to_json)
    exit 1
  end

  def initialize(params)
    @params = params
  end

  def execute!
    validate_params!
    findings = PeadmCertCheck.check(
      cert_path: @params['cert_path'],
      key_path: @params['key_path'],
      chain_path: @params['chain_path'],
      crl_path: @params['crl_path'],
      warn_days: warn_days,
      key_passphrase: @params['key_passphrase'],
    )
    puts({ 'ok' => findings.none? { |f| f['severity'] == 'error' }, 'findings' => findings }.to_json)
  end

  private

  def warn_days
    @params.fetch('warn_days', nil) || 30
  end

  def validate_params!
    self.class.usage_error('cert_path is required') if @params['cert_path'].to_s.empty?
    STRING_PARAMS.each do |name|
      value = @params[name]
      next if value.nil? || (value.is_a?(String) && !value.empty?)

      self.class.usage_error("#{name} must be a non-empty string")
    end
    return if warn_days.is_a?(Integer) && warn_days >= 0

    self.class.usage_error('warn_days must be a non-negative integer')
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
ValidateCert.run(STDIN.read) unless ENV['RSPEC_UNIT_TEST_MODE']

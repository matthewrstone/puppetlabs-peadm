# frozen_string_literal: true

require 'spec_helper'

# TST-02, TST-03, TRC-01: peadm_spec::foundation_node_checks answers the Phase 1
# on-node questions. It is run by hand on operator VMs; these examples prove its
# output shape, that one failing check never hides the others, that it never
# returns file contents, and the FND-06 replica read gate.
describe 'peadm_spec::foundation_node_checks' do
  include BoltSpec::Plans

  let(:inventory_data) { { 'targets' => targets } }
  let(:targets) { [{ 'name' => 'primary', 'vars' => { 'role' => 'primary' } }] }

  let(:secret_paths) do
    [
      '/etc/puppetlabs/orchestration-services/conf.d/secrets/keys.json',
      '/etc/puppetlabs/orchestration-services/conf.d/secrets/orchestrator-encryption-keys.json',
      '/etc/puppetlabs/console-services/conf.d/secrets/keys.json',
    ]
  end
  let(:primary_keys) { ['ca_backend', 'ca_backend_grep', 'ca_status', 'validate_cert', 'pe_conf_absent', 'secret_file_modes', 'token_mode', 'pe_version', 'puppet_version', 'bolt_version'] }

  # Per-command overrides: a Hash of command regexp => [stdout, exit_code].
  let(:overrides) { {} }
  let(:commands) { [] }

  def command_result(target, stdout = '', exit_code = 0)
    Bolt::Result.for_command(target, { 'stdout' => stdout, 'stderr' => '', 'exit_code' => exit_code }, 'command', 'cmd', [])
  end

  def default_stdout(command, target_name)
    case command
    when 'hostname -f' then "#{target_name}.example.com\n"
    when %r{\Acat /opt/puppetlabs/server/pe_version} then "2026.0.1\n"
    when %r{puppet --version} then "8.10.0\n"
    when %r{puppet config print hostcert}
      "hostcert = /etc/puppetlabs/puppet/ssl/certs/primary.pem\nhostprivkey = /etc/puppetlabs/puppet/ssl/private_keys/primary.pem\n" \
        "localcacert = /etc/puppetlabs/puppet/ssl/certs/ca.pem\nhostcrl = /etc/puppetlabs/puppet/ssl/crl.pem\n"
    when %r{\Agrep -rnHF}
      "/etc/puppetlabs/puppetserver/services.d/ca.cfg:3\n"
    when %r{\Astat -c .* /root/.puppetlabs/token} then "600 root root /root/.puppetlabs/token\n"
    when %r{\Astat -c} then secret_paths.map { |p| "600 pe-orchestration-services pe-orchestration-services #{p}" }.join("\n") + "\n"
    when %r{\Asystemctl is-active} then "active\nactive\n"
    else ''
    end
  end

  before(:each) do
    allow_out_message
    allow_any_command.return do |targets:, command:, **|
      commands << [targets.map(&:name), command]
      override = overrides.find { |re, _| command.match?(re) }
      Bolt::ResultSet.new(targets.map do |t|
        override ? command_result(t, override.last.first, override.last.last) : command_result(t, default_stdout(command, t.name))
      end)
    end
    allow_task('peadm::ca_storage_backend').always_return('backend' => 'database', 'source' => '/etc/puppetlabs/puppetserver/services.d/ca.cfg', 'checked' => [])
    allow_task('peadm::wait_until_service_ready').always_return({})
    allow_task('peadm::validate_cert').always_return('ok' => true, 'findings' => [{ 'severity' => 'warn', 'code' => 'cert_expires_soon', 'message' => 'x', 'path' => '/p' }])
  end

  def run
    run_plan('peadm_spec::foundation_node_checks', {})
  end

  it 'returns every primary key and no replica keys when the inventory has no replica' do
    result = run

    expect(result).to be_ok
    expect(result.value.keys).to match_array(primary_keys)
    expect(result.value).to include(
      'ca_backend'      => include('backend' => 'database'),
      'ca_backend_grep' => ['/etc/puppetlabs/puppetserver/services.d/ca.cfg:3'],
      'ca_status'       => include('ok' => true),
      'validate_cert'   => { 'task_ok' => true, 'cert_ok' => true, 'findings' => ['warn:cert_expires_soon'] },
      'pe_conf_absent'  => true,
      'token_mode'      => '600 root root /root/.puppetlabs/token',
      'pe_version'      => '2026.0.1',
      'puppet_version'  => '8.10.0',
    )
    expect(result.value['bolt_version']).to eq(Bolt::VERSION)
    expect(result.value['secret_file_modes'].length).to eq(3)
  end

  it 'hands validate_cert the paths puppet reports for the node certificate files' do
    expected = nil
    allow_task('peadm::validate_cert').return do |targets:, params:, **|
      expected = params
      Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, value: { 'ok' => true, 'findings' => [] }) })
    end

    run

    expect(expected).to include(
      'cert_path'  => '/etc/puppetlabs/puppet/ssl/certs/primary.pem',
      'key_path'   => '/etc/puppetlabs/puppet/ssl/private_keys/primary.pem',
      'chain_path' => '/etc/puppetlabs/puppet/ssl/certs/ca.pem',
      'crl_path'   => '/etc/puppetlabs/puppet/ssl/crl.pem',
    )
  end

  # Catches a mutation that lets one failed check abort the plan.
  it 'reports the check that failed and still returns the others' do
    allow_task('peadm::ca_storage_backend').error_with('msg' => 'boom', 'kind' => 'puppetlabs.tasks/task-error')
    allow_task('peadm::wait_until_service_ready').error_with('msg' => 'never ready, log tail: SECRET-LOG-LINE', 'kind' => 'peadm/service-not-ready')
    allow_task('peadm::validate_cert').error_with('msg' => 'cannot load', 'kind' => 'puppetlabs.tasks/task-error')
    overrides[%r{\Atest ! -e /tmp/pe\.conf}] = ['', 1]

    result = run

    expect(result).to be_ok
    expect(result.value.keys).to match_array(primary_keys)
    expect(result.value['ca_backend']).to eq('error_kind' => 'puppetlabs.tasks/task-error')
    expect(result.value['ca_status']).to eq('ok' => false, 'error_kind' => 'peadm/service-not-ready')
    expect(result.value['validate_cert']).to eq('task_ok' => false, 'error_kind' => 'puppetlabs.tasks/task-error')
    expect(result.value['pe_conf_absent']).to be(false)
    expect(result.value.to_s).not_to include('SECRET-LOG-LINE')
  end

  it 'does not run validate_cert when the node reports no certificate paths' do
    overrides[%r{puppet config print hostcert}] = ['', 1]

    result = run

    expect(result.value['validate_cert']).to eq('task_ok' => false, 'error_kind' => 'peadm_spec/ssl-paths-unavailable')
  end

  # Catches a mutation that returns key store contents instead of modes.
  it 'never reads the key stores or the token: only stat is run on them' do
    run

    secret_commands = commands.map(&:last).select { |c| c.include?('secrets/') || c.include?('.puppetlabs/token') }
    expect(secret_commands).not_to be_empty
    expect(secret_commands).to all(match(%r{\A(stat -c |runuser -u pe-(orchestration|console)-services -- test -r )}))
  end

  context 'with a spare replica in the inventory' do
    let(:targets) do
      [
        { 'name' => 'primary', 'vars' => { 'role' => 'primary' } },
        { 'name' => 'replica', 'vars' => { 'role' => 'spare-replica' } },
      ]
    end

    def replica_stat(mode)
      secret_paths.map { |p| "#{mode} pe-orchestration-services pe-orchestration-services #{p}" }.join("\n") + "\n"
    end

    it 'reports per-file stat, service user readability and active services, true only when all pass' do
      result = run

      expect(result).to be_ok
      expect(result.value.keys).to match_array(primary_keys + ['replica_secrets', 'replica_services_active', 'replica_secrets_readable'])
      expect(result.value['replica_secrets'].keys).to match_array(secret_paths)
      expect(result.value['replica_secrets'][secret_paths[0]]).to eq(
        'stat'         => "600 pe-orchestration-services pe-orchestration-services #{secret_paths[0]}",
        'service_user' => 'pe-orchestration-services',
        'readable'     => true,
      )
      expect(result.value['replica_secrets'][secret_paths[2]]['service_user']).to eq('pe-console-services')
      expect(result.value['replica_services_active']).to eq('ok' => true, 'states' => ['active', 'active'])
      expect(result.value['replica_secrets_readable']).to be(true)
    end

    it 'runs the read checks as the owning service users on the replica only' do
      run

      reads = commands.select { |_, c| c.start_with?('runuser') }
      expect(reads.map(&:first).flatten.uniq).to eq(['replica'])
      expect(reads.map(&:last)).to contain_exactly(
        "runuser -u pe-orchestration-services -- test -r #{secret_paths[0]}",
        "runuser -u pe-orchestration-services -- test -r #{secret_paths[1]}",
        "runuser -u pe-console-services -- test -r #{secret_paths[2]}",
      )
    end

    # Catches a mutation that reports readable while one service user is denied.
    it 'is false when one service user cannot read its key store' do
      overrides[%r{runuser -u pe-console-services}] = ['', 1]

      result = run

      expect(result.value['replica_secrets'][secret_paths[2]]['readable']).to be(false)
      expect(result.value['replica_secrets'][secret_paths[0]]['readable']).to be(true)
      expect(result.value['replica_secrets_readable']).to be(false)
    end

    it 'is false when a service is not active even though the files are readable' do
      overrides[%r{\Asystemctl is-active}] = ["active\ninactive\n", 3]

      result = run

      expect(result.value['replica_services_active']).to eq('ok' => false, 'states' => ['active', 'inactive'])
      expect(result.value['replica_secrets_readable']).to be(false)
    end
  end

  context 'with a target whose role is replica' do
    let(:targets) { [{ 'name' => 'primary', 'vars' => { 'role' => 'primary' } }, { 'name' => 'r1', 'vars' => { 'role' => 'replica' } }] }

    it 'treats it as the replica' do
      expect(run.value).to include('replica_secrets_readable' => true)
    end
  end

  context 'without a primary in the inventory' do
    let(:targets) { [{ 'name' => 'x', 'vars' => { 'role' => 'compiler' } }] }

    it 'fails' do
      result = run

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{role "primary" is required})
    end
  end
end

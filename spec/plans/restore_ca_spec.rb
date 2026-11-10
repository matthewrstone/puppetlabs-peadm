require 'spec_helper'

describe 'peadm::restore_ca' do
  include BoltSpec::Plans

  let(:params) do
    {
      'target' => 'myserver.example.com',
      'file_path' => '/tmp/backup_ca.tgz'
    }
  end
  let(:pe_conf) { nil }
  let(:production_command) do
    "      /opt/puppetlabs/bin/puppet-backup restore   --scope=certs   --tempdir=/tmp/peadm_recovery   --force   /tmp/backup_ca.tgz\n"
  end

  before(:each) do
    # The target's pe.conf, read when no environment is given. Empty means production.
    allow_task('peadm::read_file').return do |targets:, **|
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: { 'content' => pe_conf }) })
    end
  end

  it 'will run puppet-backup command' do
    expect_out_message.with_params('# Restoring ca and ssl certificates')
    allow_any_command
    expect(run_plan('peadm::restore_ca', params)).to be_ok
  end

  # Production clusters run exactly the command they always did.
  it 'adds no environment flag for production' do
    allow_out_message
    expect_command(production_command)
    expect(run_plan('peadm::restore_ca', params)).to be_ok
  end

  # PE-46598: puppet-backup restore defaults to production.
  it 'passes node_group_environment to puppet-backup restore' do
    allow_out_message
    expect_command(production_command.sub('--force', '--force --pe-environment=dev'))
    expect_task('peadm::read_file').not_be_called
    expect(run_plan('peadm::restore_ca', params.merge('node_group_environment' => 'dev'))).to be_ok
  end

  context 'when pe.conf on the target sets another environment' do
    let(:pe_conf) do
      '{"pe_install::install::classification::pe_node_group_environment": "staging", "puppet_enterprise::master::recover_configuration::pe_environment": "staging"}'
    end

    it 'uses it' do
      allow_out_message
      expect_command(production_command.sub('--force', '--force --pe-environment=staging'))
      expect(run_plan('peadm::restore_ca', params)).to be_ok
    end

    # Catches a mutation that lets pe.conf beat an explicit choice.
    it 'prefers the node_group_environment parameter' do
      allow_out_message
      expect_command(production_command.sub('--force', '--force --pe-environment=dev'))
      expect(run_plan('peadm::restore_ca', params.merge('node_group_environment' => 'dev'))).to be_ok
    end
  end

  it 'rejects a node_group_environment that is not a valid environment name' do
    result = run_plan('peadm::restore_ca', params.merge('node_group_environment' => '../etc'))
    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{parameter 'node_group_environment' expects a match for Peadm::Pe_environment})
  end
end

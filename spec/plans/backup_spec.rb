# frozen_string_literal: true

# rubocop:disable Layout/LineLength

require 'spec_helper'

describe 'peadm::backup' do
  include BoltSpec::Plans
  let(:primary_pe_conf) { nil }
  let(:default_params) { { 'targets' => 'primary', 'backup_type' => 'recovery' } }
  let(:classifier_only) do
    {
      'targets' => 'primary',
      'backup_type' => 'custom',
      'backup' => {
        'activity'     => false,
        'ca'           => false,
        'classifier'   => true,
        'code'         => false,
        'config'       => false,
        'orchestrator' => false,
        'puppetdb'     => false,
        'rbac'         => false,
      }
    }
  end
  let(:all_backup_options) do
    {
      'targets' => 'primary',
      'backup_type' => 'custom',
      'backup' => {} # set all to true
    }
  end

  before(:each) do
    # define a zero timestamp
    mocktime = Puppet::Pops::Time::Timestamp.new(0)
    # mock the timestamp to always return the zero timestamp
    # so the directory name is always the same - /tmp/pe-backup-1970-01-01T000000Z
    allow(Puppet::Pops::Time::Timestamp).to receive(:now).and_return(mocktime)

    allow_apply

    # The primary's pe.conf, read to record the node group environment. An empty
    # answer means production.
    allow_task('peadm::read_file').return do |targets:, **|
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: { 'content' => primary_pe_conf }) })
    end

    expect_task('peadm::get_peadm_config').always_return({
                                                           'params' => {
                                                             'primary_host' => 'primary',
                                                             'primary_postgresql_host' => 'postgres',
                                                           }
                                                         })
  end

  it 'runs with backup type recovery' do
    expect_out_message.with_params('# Backing up ca, certs, code and config for recovery')
    expect_out_message.with_params('# Backing up database pe-puppetdb')

    expect_command("/opt/puppetlabs/bin/puppet-backup create --dir=/tmp/pe-backup-1970-01-01T000000Z/recovery --scope=certs,code,config\n")
    expect_command('/opt/puppetlabs/server/bin/pg_dump -Fd -Z3 -j4   -f /tmp/pe-backup-1970-01-01T000000Z/puppetdb/pe-puppetdb.dump.d   "sslmode=verify-ca    host=postgres    user=pe-puppetdb    sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem    sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem    sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem    dbname=pe-puppetdb"' + "\n")
    expect_command('umask 0077   && cd /tmp   && tar -czf /tmp/pe-backup-1970-01-01T000000Z.tar.gz pe-backup-1970-01-01T000000Z   && rm -rf /tmp/pe-backup-1970-01-01T000000Z' + "\n")

    expect(run_plan('peadm::backup', default_params)).to be_ok
  end

  it 'runs with backup type recovery by default' do
    expect_out_message.with_params('# Backing up ca, certs, code and config for recovery')
    expect_out_message.with_params('# Backing up database pe-puppetdb')

    expect_command("/opt/puppetlabs/bin/puppet-backup create --dir=/tmp/pe-backup-1970-01-01T000000Z/recovery --scope=certs,code,config\n")
    expect_command('/opt/puppetlabs/server/bin/pg_dump -Fd -Z3 -j4   -f /tmp/pe-backup-1970-01-01T000000Z/puppetdb/pe-puppetdb.dump.d   "sslmode=verify-ca    host=postgres    user=pe-puppetdb    sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem    sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem    sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem    dbname=pe-puppetdb"' + "\n")
    expect_command('umask 0077   && cd /tmp   && tar -czf /tmp/pe-backup-1970-01-01T000000Z.tar.gz pe-backup-1970-01-01T000000Z   && rm -rf /tmp/pe-backup-1970-01-01T000000Z' + "\n")

    expect(run_plan('peadm::backup', { 'targets' => 'primary' })).to be_ok
  end

  it 'runs with backup and defined output folder' do
    expect_out_message.with_params('# Backing up ca, certs, code and config for recovery')
    expect_out_message.with_params('# Backing up database pe-puppetdb')

    expect_command("/opt/puppetlabs/bin/puppet-backup create --dir=/user/home/folder/pe-backup-1970-01-01T000000Z/recovery --scope=certs,code,config\n")
    expect_command('/opt/puppetlabs/server/bin/pg_dump -Fd -Z3 -j4   -f /user/home/folder/pe-backup-1970-01-01T000000Z/puppetdb/pe-puppetdb.dump.d   "sslmode=verify-ca    host=postgres    user=pe-puppetdb    sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem    sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem    sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem    dbname=pe-puppetdb"' + "\n")
    expect_command('umask 0077   && cd /user/home/folder   && tar -czf /user/home/folder/pe-backup-1970-01-01T000000Z.tar.gz pe-backup-1970-01-01T000000Z   && rm -rf /user/home/folder/pe-backup-1970-01-01T000000Z' + "\n")

    expect(run_plan('peadm::backup', { 'targets' => 'primary', 'output_directory' => '/user/home/folder' })).to be_ok
  end

  it 'runs with backup type custom, classifier only' do
    expect_task('peadm::backup_classification').with_params({ 'directory' => '/tmp/pe-backup-1970-01-01T000000Z/classifier' })
    expect_out_message.with_params('# Backing up classification')
    expect_command('umask 0077   && cd /tmp   && tar -czf /tmp/pe-backup-1970-01-01T000000Z.tar.gz pe-backup-1970-01-01T000000Z   && rm -rf /tmp/pe-backup-1970-01-01T000000Z' + "\n")

    expect(run_plan('peadm::backup', classifier_only)).to be_ok
  end

  it 'runs with backup type custom, all backup params set to true' do
    expect_task('peadm::backup_classification').with_params({ 'directory' => '/tmp/pe-backup-1970-01-01T000000Z/classifier' })

    expect_out_message.with_params('# Backing up classification')
    expect_out_message.with_params('# Backing up database pe-orchestrator')
    expect_out_message.with_params('# Backing up database pe-activity')
    expect_out_message.with_params('# Backing up database pe-rbac')
    expect_out_message.with_params('# Backing up database pe-puppetdb')

    expect_command("/opt/puppetlabs/bin/puppet-backup create --dir=/tmp/pe-backup-1970-01-01T000000Z/ca --scope=certs\n")
    expect_command("/opt/puppetlabs/bin/puppet-backup create --dir=/tmp/pe-backup-1970-01-01T000000Z/code --scope=code\n")
    expect_command('chown pe-postgres /tmp/pe-backup-1970-01-01T000000Z/config')
    expect_command("/opt/puppetlabs/bin/puppet-backup create --dir=/tmp/pe-backup-1970-01-01T000000Z/config --scope=config\n")
    expect_command("test -f /etc/puppetlabs/console-services/conf.d/secrets/keys.json   && cp -rp /etc/puppetlabs/console-services/conf.d/secrets /tmp/pe-backup-1970-01-01T000000Z/rbac/   || echo secret ldap key doesnt exist\n")
    expect_command("cp -rp /etc/puppetlabs/orchestration-services/conf.d/secrets /tmp/pe-backup-1970-01-01T000000Z/orchestrator/\n")
    expect_command('/opt/puppetlabs/server/bin/pg_dump -Fd -Z3 -j4   -f /tmp/pe-backup-1970-01-01T000000Z/orchestrator/pe-orchestrator.dump.d   "sslmode=verify-ca    host=primary    user=pe-orchestrator    sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem    sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem    sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem    dbname=pe-orchestrator"' + "\n")
    expect_command('/opt/puppetlabs/server/bin/pg_dump -Fd -Z3 -j4   -f /tmp/pe-backup-1970-01-01T000000Z/activity/pe-activity.dump.d   "sslmode=verify-ca    host=primary    user=pe-activity    sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem    sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem    sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem    dbname=pe-activity"' + "\n")
    expect_command('/opt/puppetlabs/server/bin/pg_dump -Fd -Z3 -j4   -f /tmp/pe-backup-1970-01-01T000000Z/rbac/pe-rbac.dump.d   "sslmode=verify-ca    host=primary    user=pe-rbac    sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem    sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem    sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem    dbname=pe-rbac"' + "\n")
    expect_command('/opt/puppetlabs/server/bin/pg_dump -Fd -Z3 -j4   -f /tmp/pe-backup-1970-01-01T000000Z/puppetdb/pe-puppetdb.dump.d   "sslmode=verify-ca    host=postgres    user=pe-puppetdb    sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem    sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem    sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem    dbname=pe-puppetdb"' + "\n")
    expect_command('umask 0077   && cd /tmp   && tar -czf /tmp/pe-backup-1970-01-01T000000Z.tar.gz pe-backup-1970-01-01T000000Z   && rm -rf /tmp/pe-backup-1970-01-01T000000Z' + "\n")

    expect(run_plan('peadm::backup', all_backup_options)).to be_ok
  end

  # With a database-backed CA the on-disk CA files (incl. $cadir/serial) lag
  # behind the pe-ca database, so they must be exported to disk before the
  # certs scope is backed up; a filesystem CA needs no export.
  context 'with only the ca scope' do
    let(:ca_only) do
      {
        'targets' => 'primary',
        'backup_type' => 'custom',
        'backup' => {
          'activity' => false, 'ca' => true, 'classifier' => false, 'code' => false,
          'config' => false, 'orchestrator' => false, 'puppetdb' => false, 'rbac' => false
        }
      }
    end
    let(:ca_export) { '/opt/puppetlabs/bin/puppetserver ca storage --export' }
    let(:certs_backup) { "/opt/puppetlabs/bin/puppet-backup create --dir=/tmp/pe-backup-1970-01-01T000000Z/ca --scope=certs\n" }

    def run_with_ca_backend(backend)
      call_log = []
      allow_out_message
      allow_any_command.return do |targets:, command:, **|
        call_log << command
        stdout = command.include?('database-storage-service') ? backend : ''
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: { 'stdout' => stdout }) })
      end
      expect(run_plan('peadm::backup', ca_only)).to be_ok
      call_log
    end

    it 'exports a database-backed CA to disk before backing up the certs scope' do
      call_log = run_with_ca_backend('database')
      expect(call_log.count(ca_export)).to eq(1)
      expect(call_log.index(ca_export)).to be < call_log.index(certs_backup)
    end

    it 'does not export a filesystem-backed CA' do
      call_log = run_with_ca_backend('filesystem')
      expect(call_log).to include(certs_backup)
      expect(call_log).not_to include(ca_export)
    end
  end

  # PE-46598: restore needs to know which environment the cluster was classified
  # into, so the backup records it. The apply() block is mocked by BoltSpec, so
  # the file itself is checked on the plan text; what the plan reads is checked
  # through the stubbed pe.conf.
  context 'recording the node group environment' do
    let(:plan_text) { File.read(File.expand_path('../../plans/backup.pp', __dir__)) }
    let(:dev_pe_conf) do
      '{"pe_install::install::classification::pe_node_group_environment": "dev", "puppet_enterprise::master::recover_configuration::pe_environment": "dev"}'
    end
    let(:primary_pe_conf) { dev_pe_conf }

    it 'reads the environment from pe.conf on the primary' do
      allow_any_command
      allow_out_message
      expect_task('peadm::read_file').with_targets(['primary']).with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').be_called_times(1)

      expect(run_plan('peadm::backup', default_params)).to be_ok
    end

    it 'fails before backing anything up when the pe.conf environment keys disagree' do
      pe_conf = '{"pe_install::install::classification::pe_node_group_environment": "dev", "puppet_enterprise::master::recover_configuration::pe_environment": "staging"}'
      allow_task('peadm::read_file').always_return({ 'content' => pe_conf })
      expect_command(%r{puppet-backup create}).not_be_called

      result = run_plan('peadm::backup', default_params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{need to be set to the same value})
    end

    # Catches a mutation that drops the file resource or changes its owner or mode.
    it 'writes peadm/node_group_environment.json as root with mode 0600, beside peadm_config.json' do
      region = plan_text[%r{file \{ "\$\{backup_directory\}/peadm/node_group_environment\.json":.*?\n    \}}m]
      expect(region).not_to be_nil
      expect(region).to include("stdlib::to_json_pretty({ 'node_group_environment' => $node_group_environment })")
      expect(region).to include("owner   => 'root'", "group   => 'root'", "mode    => '0600'")
    end
  end
end

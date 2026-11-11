require 'spec_helper'
require 'json'

# P1-23 (FND-05, plan output side): plant fake secrets in the parameters of
# peadm::install, peadm::subplans::install and peadm::upgrade and prove that
# none of them appears in any message the plans print, or in a fail_plan
# message. Task output is covered by the shell-task and Ruby-task specs.
#
# Every message goes through the executor's publish_event, which is wrapped to
# collect the :message events (out::message and friends). The out::message
# function is deliberately not stubbed, so the real text is captured.
describe 'plan output never carries secrets' do
  include BoltSpec::Plans

  let(:secret_marker) { 'FAKE-SECRET' }
  let(:console_password) { "#{secret_marker}-console" }
  let(:license_key) { "#{secret_marker}-license" }
  let(:r10k_key) { "-----BEGIN RSA PRIVATE KEY-----\n#{secret_marker}-key\n-----END RSA PRIVATE KEY-----" }
  let(:tarball) { 'puppet-enterprise-2025.12.1-el-9-x86_64.tar.gz' }
  let(:signed_url) do
    "https://pe-builds.s3.amazonaws.com/released/2025.12.1/#{tarball}?X-Amz-Credential=#{secret_marker}-cred&X-Amz-Signature=#{secret_marker}-sig"
  end

  let(:messages) { [] }
  let(:mockfile) { instance_double('Tempfile', path: '/mock', write: nil, flush: nil, close: nil, unlink: nil) }

  let(:secret_params) do
    {
      'primary_host' => 'primary',
      'console_password' => console_password,
      'version' => '2025.12.1',
      'license_key_content' => license_key,
      'code_manager_auto_configure' => true,
      'r10k_remote' => 'git@git.example.com:org/control-repo.git',
      'r10k_private_key_content' => r10k_key,
    }
  end

  # Collects every :message and :verbose event while still passing it on to the
  # mock executor, which needs them allowed (allow_any_out_message and
  # allow_any_out_verbose) but does not keep their text.
  def capture_messages
    allow_any_out_message
    allow_any_out_verbose
    allow(executor).to receive(:publish_event).and_wrap_original do |orig, event|
      messages << event[:message] if [:message, :verbose].include?(event[:type])
      orig.call(event)
    end
  end

  # The text of everything the run printed, plus a failing plan's message, so
  # a secret in a fail_plan is caught too.
  def printed_text(result)
    failure = result.ok? ? '' : result.value.to_s
    (messages + [failure]).join("\n")
  end

  def expect_no_secret(result)
    # A run that printed nothing would pass vacuously.
    expect(messages).not_to be_empty
    expect(printed_text(result)).not_to include(secret_marker)
  end

  before(:each) do
    capture_messages
    allow_apply
    allow_any_task
    allow_any_plan
    allow_any_command

    allow_task('peadm::precheck').return_for_targets(
      'primary' => { 'hostname' => 'primary', 'platform' => 'el-9-x86_64' },
      'postgres1' => { 'hostname' => 'postgres1', 'platform' => 'el-9-x86_64' },
      'compiler1' => { 'hostname' => 'compiler1', 'platform' => 'el-9-x86_64' },
    )

    # peadm::file_content_upload writes a Tempfile and uploads it; stub both
    # (same approach as spec/plans/subplans/install_spec.rb).
    # rubocop:disable RSpec/AnyInstance
    allow(Tempfile).to receive(:new).and_call_original
    allow(Pathname).to receive(:new).and_call_original
    allow(Puppet::FileSystem).to receive(:exist?).and_call_original
    allow_any_instance_of(BoltSpec::Plans::MockExecutor).to receive(:module_file_id).and_call_original

    mockpath = instance_double('Pathname', absolute?: true)
    allow(Tempfile).to receive(:new).with('peadm').and_return(mockfile)
    allow(Pathname).to receive(:new).with('/mock').and_return(mockpath)
    allow(Puppet::FileSystem).to receive(:exist?).with('/mock').and_return(true)
    allow_any_instance_of(BoltSpec::Plans::MockExecutor).to receive(:module_file_id).with('/mock').and_return('/mock')
    # rubocop:enable RSpec/AnyInstance
    allow_upload('/mock')
  end

  # The capture would be vacuous if the planted values never reached the plan,
  # so the plan is shown to receive them: the subplan is handed the values.
  describe 'peadm::install' do
    it 'prints none of the planted secrets and hands them to the install subplan' do
      handed = nil
      allow_plan('peadm::subplans::install').return do |params:, **|
        handed = params
        Bolt::PlanResult.new({}, 'success')
      end
      allow_plan('peadm::subplans::configure').return { Bolt::PlanResult.new({}, 'success') }

      result = run_plan('peadm::install', secret_params)

      expect(result).to be_ok
      expect(handed.values_at('console_password', 'license_key_content', 'r10k_private_key_content')).to eq([console_password, license_key, r10k_key])
      expect_no_secret(result)
    end

    it 'prints none of the planted secrets when the install subplan fails' do
      allow_plan('peadm::subplans::install').return { Bolt::PlanResult.new(Bolt::Error.new('install failed', 'bolt/plan-failure'), 'failure') }

      result = run_plan('peadm::install', secret_params)

      expect(result).not_to be_ok
      expect_no_secret(result)
    end
  end

  describe 'peadm::subplans::install' do
    let(:subplan_params) { secret_params.merge('pe_installer_source' => signed_url) }

    it 'prints none of the planted secrets, including the signed installer URL' do
      result = run_plan('peadm::subplans::install', subplan_params)

      expect(result).to be_ok
      expect_no_secret(result)
    end

    def record_downloads(downloads)
      allow_plan('peadm::util::retrieve_and_upload').return do |params:, **|
        downloads << params
        Bolt::PlanResult.new({}, 'success')
      end
    end

    def expect_signed_url_only_as_source(downloads)
      expect(downloads.map { |d| d['source'] }.uniq).to eq([signed_url])
      expect(downloads.map { |d| d['upload_path'] }.uniq).to eq(["/tmp/#{tarball}"])
      expect(downloads.map { |d| d['local_path'] }.uniq).to eq(["/tmp/#{tarball}"])
    end

    # Catches a mutation that derives the name by splitting the raw URL, which
    # puts the signature into the upload path the installer is run from.
    it 'uploads and installs from a name without the query string, and downloads from the signed URL' do
      downloads = []
      record_downloads(downloads)
      tarballs = []
      allow_task('peadm::pe_install').return do |targets:, params:, **|
        tarballs << params['tarball']
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
      end

      expect(run_plan('peadm::subplans::install', subplan_params)).to be_ok

      expect_signed_url_only_as_source(downloads)
      expect(tarballs).to eq(["/tmp/#{tarball}"])
    end

    # The installer directory is derived by stripping .tar or .tar.gz from the
    # end of the name, which does nothing while a query string follows it.
    it 'names the installer directory without the query string in a split-database install' do
      downloads = []
      record_downloads(downloads)
      installer_dirs = []
      allow_task('peadm::pe_reinstall').return do |targets:, params:, **|
        installer_dirs << params['installer_dir']
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
      end
      split_params = subplan_params.merge('primary_postgresql_host' => 'postgres1', 'compiler_hosts' => ['compiler1'])

      result = run_plan('peadm::subplans::install', split_params)

      expect(result).to be_ok
      expect(installer_dirs).to eq(['/tmp/puppet-enterprise-2025.12.1-el-9-x86_64'])
      expect_no_secret(result)
    end
  end

  describe 'peadm::upgrade' do
    let(:trusted_primary) do
      JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'trusted-primary.json')))
    end
    let(:upgrade_params) { { 'primary_host' => 'primary', 'pe_installer_source' => signed_url } }

    before(:each) do
      allow_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })
      allow_task('peadm::read_file').with_params('path' => '/opt/puppetlabs/server/pe_build').return_for_targets('primary' => { 'content' => '2023.8.13' })
      allow_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').return_for_targets('primary' => { 'content' => '{}' })
      allow_task('peadm::cert_data').return_for_targets('primary' => trusted_primary)
      allow_task('peadm::check_pe_master_rules').always_return('updated' => 'true', 'message' => 'a message')
    end

    # Catches a mutation that logs the raw last path segment of the URL: the
    # signature is in the query string that segment carries.
    it 'prints none of the planted secrets, including the signed installer URL' do
      result = run_plan('peadm::upgrade', upgrade_params)

      expect(result).to be_ok
      expect(messages).to include("Parameter 'pe_installer_source': [#{tarball}]")
      expect_no_secret(result)
    end

    it 'uploads to a path without the query string and still downloads from the signed URL' do
      downloads = []
      allow_plan('peadm::util::retrieve_and_upload').return do |params:, **|
        downloads << params
        Bolt::PlanResult.new({}, 'success')
      end

      expect(run_plan('peadm::upgrade', upgrade_params)).to be_ok

      expect(downloads.map { |d| d['source'] }).to eq([signed_url])
      expect(downloads.map { |d| d['upload_path'] }).to eq(["/tmp/#{tarball}"])
      expect(downloads.map { |d| d['local_path'] }).to eq(["/tmp/#{tarball}"])
    end
  end
end

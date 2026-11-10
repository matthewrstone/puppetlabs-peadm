require 'spec_helper'

# P1-17: the first spec for this @api private plan. It covers the handling of
# /tmp/pe.conf (which carries console_admin_password) and the availability
# deadline; the rest of the plan is stubbed.
describe 'peadm::util::init_db_server' do
  include BoltSpec::Plans

  let(:inventory_data) do
    {
      'targets' => [
        { 'name' => 'primary', 'vars' => { 'role' => 'primary' } },
        { 'name' => 'compiler1', 'vars' => { 'role' => 'compiler' } },
        { 'name' => 'db', 'vars' => {} },
      ],
    }
  end
  let(:mockfile) { instance_double('Tempfile', path: '/mock', write: nil, flush: nil, close: nil, unlink: nil) }
  let(:ok_command) { { 'stdout' => '', 'stderr' => '', 'exit_code' => 0 } }

  before(:each) do
    allow_any_task
    allow_any_plan
    allow_any_command
    allow_any_out_message

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

    allow_command('hostname -f').return do |targets:, **|
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: { 'stdout' => "#{target.name}.example.com\n", 'stderr' => '', 'exit_code' => 0 }) })
    end
  end

  # Records the pe.conf commands and the installer task, in order.
  def record_events(events)
    ['chmod 0600 /tmp/pe.conf', 'rm -f /tmp/pe.conf'].each do |command|
      allow_command(command).return do |targets:, **|
        events << [command.split.first.to_sym, targets.map(&:name)]
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: ok_command) })
      end
    end
    allow_task('peadm::pe_install').return do |targets:, **|
      events << [:pe_install, targets.map(&:name)]
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
    end
  end

  describe 'with install_pe' do
    let(:params) { { 'db_host' => 'db', 'install_pe' => true } }

    # Catches a mutation that drops the chmod, or moves it after the installer.
    it 'restricts /tmp/pe.conf to 0600 after the upload and before the installer reads it' do
      events = []
      record_events(events)
      expect(run_plan('peadm::util::init_db_server', params)).to be_ok
      expect(events.index([:chmod, ['db']])).not_to be_nil
      expect(events.index([:chmod, ['db']])).to be < events.index([:pe_install, ['db']])
    end

    # Catches a mutation that never removes the file, or removes it before the installer.
    it 'removes /tmp/pe.conf after the installer ran' do
      events = []
      record_events(events)
      expect(run_plan('peadm::util::init_db_server', params)).to be_ok
      expect(events.index([:rm, ['db']])).to be > events.index([:pe_install, ['db']])
    end

    # Catches a mutation that lets a failing installer skip the removal, or swallows its error.
    it 'removes /tmp/pe.conf and fails with the installer error when pe_install fails' do
      events = []
      record_events(events)
      expect_task('peadm::pe_install').error_with({ 'msg' => 'installer exploded', 'kind' => 'puppetlabs.tasks/task-error' })
      result = run_plan('peadm::util::init_db_server', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to include('installer exploded')
      expect(events).to include([:rm, ['db']])
    end
  end

  describe 'without install_pe' do
    it 'does not upload, chmod or remove a pe.conf' do
      events = []
      record_events(events)
      expect(run_plan('peadm::util::init_db_server', 'db_host' => 'db')).to be_ok
      expect(events).to be_empty
    end
  end

  describe 'wait_time' do
    # BoltSpec's MockExecutor drops wait_until_available's options, so check the
    # plan source. Bolt's own default is 120 s, so the default keeps today's
    # behaviour. Catches a mutation that stops passing the value, or changes the default.
    let(:source) { File.read(File.expand_path('../../../plans/util/init_db_server.pp', __dir__)) }

    it 'passes the wait_time parameter to wait_until_available' do
      calls = source.scan(%r{wait_until_available\([^)]*\)})
      expect(calls).not_to be_empty
      expect(calls).to all(include('wait_time => $wait_time'))
    end

    it 'defaults wait_time to 120 seconds' do
      expect(source).to match(%r{Integer\[1\]\s+\$wait_time\s*=\s*120})
    end

    it 'accepts an operator-given wait_time' do
      expect(run_plan('peadm::util::init_db_server', 'db_host' => 'db', 'wait_time' => 300)).to be_ok
    end

    it 'rejects a wait_time of 0' do
      expect(run_plan('peadm::util::init_db_server', 'db_host' => 'db', 'wait_time' => 0)).not_to be_ok
    end
  end
end

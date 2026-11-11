require 'spec_helper'

# P1-21: the first spec for this @api private plan. It pins the mode the copied
# file gets: secrets/ key stores 0600, everything else 0644 unless a mode is
# passed.
describe 'peadm::util::copy_file' do
  include BoltSpec::Plans

  let(:inventory_data) do
    {
      'targets' => [
        { 'name' => 'primary', 'vars' => { 'role' => 'primary' } },
        { 'name' => 'replica', 'vars' => { 'role' => 'replica' } },
      ],
    }
  end

  let(:secret_paths) do
    [
      '/etc/puppetlabs/orchestration-services/conf.d/secrets/keys.json',
      '/etc/puppetlabs/orchestration-services/conf.d/secrets/orchestrator-encryption-keys.json',
      '/etc/puppetlabs/console-services/conf.d/secrets/keys.json',
    ]
  end

  before(:each) do
    allow_any_out_message
  end

  def read_file_returns(path, content)
    allow_task('peadm::read_file').with_params('path' => path).return_for_targets('primary' => { 'content' => content })
  end

  def expect_mkdir(path, params)
    expect_task('peadm::mkdir_p_file').be_called_times(1)
                                      .with_params({ 'path' => path, 'owner' => 'root', 'group' => 'root', 'content' => 'KEYS' }.merge(params))
                                      .always_return({})
  end

  # Catches a mutation that goes back to a literal 0644, which left the
  # orchestrator and console encryption keys world-readable on every replica.
  it 'copies each secrets/ key store with mode 0600' do
    secret_paths.each do |path|
      read_file_returns(path, 'KEYS')
      expect_mkdir(path, 'mode' => '0600')

      expect(run_plan('peadm::util::copy_file', 'targets' => 'replica', 'source_host' => 'primary', 'path' => path)).to be_ok
    end
  end

  # Catches a mutation that gives every path 0600, which would lock other
  # services out of files such as hiera.yaml.
  it 'copies a path outside secrets/ with mode 0644' do
    path = '/etc/puppetlabs/puppet/hiera.yaml'
    read_file_returns(path, 'KEYS')
    expect_mkdir(path, 'mode' => '0644')

    expect(run_plan('peadm::util::copy_file', 'targets' => 'replica', 'source_host' => 'primary', 'path' => path)).to be_ok
  end

  # Catches a mutation that matches "secrets" anywhere in the path instead of
  # as a directory component.
  it 'does not treat a file merely named like secrets as a secrets/ path' do
    path = '/etc/puppetlabs/puppet/secrets.yaml'
    read_file_returns(path, 'KEYS')
    expect_mkdir(path, 'mode' => '0644')

    expect(run_plan('peadm::util::copy_file', 'targets' => 'replica', 'source_host' => 'primary', 'path' => path)).to be_ok
  end

  it 'uses an explicit mode for any path, including a secrets/ one' do
    path = secret_paths.first
    read_file_returns(path, 'KEYS')
    expect_mkdir(path, 'mode' => '0640')

    expect(run_plan('peadm::util::copy_file', 'targets' => 'replica', 'source_host' => 'primary', 'path' => path, 'mode' => '0640')).to be_ok
  end

  it 'accepts a mode written without the leading zero' do
    path = '/etc/puppetlabs/puppet/hiera.yaml'
    read_file_returns(path, 'KEYS')
    expect_mkdir(path, 'mode' => '600')

    expect(run_plan('peadm::util::copy_file', 'targets' => 'replica', 'source_host' => 'primary', 'path' => path, 'mode' => '600')).to be_ok
  end

  ['777x', '0888', '07777', 'rw-r--r--', ''].each do |bad_mode|
    it "rejects the invalid mode #{bad_mode.inspect} through the parameter type" do
      result = run_plan('peadm::util::copy_file', 'targets' => 'replica', 'source_host' => 'primary', 'path' => '/etc/puppetlabs/puppet/hiera.yaml', 'mode' => bad_mode)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{mode})
    end
  end

  it 'prints the skip message and writes nothing when the source has no content' do
    path = secret_paths.first
    read_file_returns(path, nil)
    expect_task('peadm::mkdir_p_file').not_be_called
    expect_out_message.with_params("Skipping file copy: #{path} on primary had no content")

    expect(run_plan('peadm::util::copy_file', 'targets' => 'replica', 'source_host' => 'primary', 'path' => path)).to be_ok
  end
end

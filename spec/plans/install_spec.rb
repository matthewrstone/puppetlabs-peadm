require 'spec_helper'

describe 'peadm::install' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    it 'runs successfully with the minimum required parameters' do
      allow_out_message
      expect_plan('peadm::subplans::install')
      expect_plan('peadm::subplans::configure')
      expect(run_plan('peadm::install', 'primary_host' => 'primary', 'console_password' => 'puppetLabs123!', 'version' => '2021.7.9')).to be_ok
    end
  end

  describe 'default version' do
    # bolt-spec's with_params is strict equality, so the params the subplan was
    # called with are captured in the return block instead.
    # Catches a mutation that puts a literal version back as the plan default:
    # it would no longer follow data/pe_versions.yaml.
    it 'passes the default from data/pe_versions.yaml to the install subplan when no version is given' do
      captured = nil
      allow_out_message
      allow_plan('peadm::subplans::install').return do |params:, **|
        captured = params
        Bolt::PlanResult.new({}, 'success')
      end
      expect_plan('peadm::subplans::configure')
      expect(run_plan('peadm::install', 'primary_host' => 'primary', 'console_password' => 'puppetLabs123!')).to be_ok
      expect(captured).not_to be_nil, 'peadm::subplans::install was never called with captured params'
      expect(captured['version']).to eq(YAML.safe_load_file(File.join(__dir__, '..', '..', 'data', 'pe_versions.yaml')).fetch('default'))
    end
  end

  describe 'node_group_environment from pe_conf_data (P1-15)' do
    let(:base_params) { { 'primary_host' => 'primary', 'console_password' => 'puppetLabs123!', 'version' => '2021.7.9' } }
    let(:env_keys) do
      ->(pe_install, puppet_enterprise) do
        {
          'pe_install::install::classification::pe_node_group_environment' => pe_install,
          'puppet_enterprise::master::recover_configuration::pe_environment' => puppet_enterprise,
        }
      end
    end

    # bolt-spec's with_params is strict equality, so the params are captured.
    def run_install_capturing_subplan_params(params)
      captured = nil
      allow_out_message
      allow_plan('peadm::subplans::install').return do |params:, **|
        captured = params
        Bolt::PlanResult.new({}, 'success')
      end
      allow_plan('peadm::subplans::configure').return { Bolt::PlanResult.new({}, 'success') }
      result = run_plan('peadm::install', params)
      [result, captured]
    end

    # Catches a mutation that forgets to resolve the environment, or resolves it from the wrong place.
    it 'passes the environment named in pe_conf_data to the install subplan' do
      result, captured = run_install_capturing_subplan_params(base_params.merge('pe_conf_data' => env_keys.call('dev', 'dev')))
      expect(result).to be_ok
      expect(captured['node_group_environment']).to eq('dev')
    end

    it 'passes production when pe_conf_data names no environment' do
      result, captured = run_install_capturing_subplan_params(base_params)
      expect(result).to be_ok
      expect(captured['node_group_environment']).to eq('production')
    end

    it 'fails before any subplan runs when the two environment keys disagree' do
      allow_out_message
      expect_plan('peadm::subplans::install').not_be_called
      expect(run_plan('peadm::install', base_params.merge('pe_conf_data' => env_keys.call('dev', 'test')))).not_to be_ok
    end

    it 'fails before any subplan runs when the environment is not a valid name' do
      allow_out_message
      expect_plan('peadm::subplans::install').not_be_called
      expect(run_plan('peadm::install', base_params.merge('pe_conf_data' => env_keys.call('Dev-1', 'Dev-1')))).not_to be_ok
    end
  end

  describe 'forwarding to both subplans (P1-16)' do
    let(:base_params) { { 'primary_host' => 'primary', 'console_password' => 'puppetLabs123!', 'version' => '2021.7.9' } }
    let(:pe_conf_data) do
      {
        'pe_install::install::classification::pe_node_group_environment' => 'dev',
        'puppet_enterprise::master::recover_configuration::pe_environment' => 'dev',
      }
    end

    # bolt-spec's with_params is strict equality, so the params are captured.
    def run_install_capturing_both_subplans(params)
      captured = {}
      allow_out_message
      allow_plan('peadm::subplans::install').return do |params:, **|
        captured[:install] = params
        Bolt::PlanResult.new({}, 'success')
      end
      allow_plan('peadm::subplans::configure').return do |params:, **|
        captured[:configure] = params
        Bolt::PlanResult.new({}, 'success')
      end
      expect(run_plan('peadm::install', params)).to be_ok
      captured
    end

    # Catches a mutation that forwards the environment to only one subplan.
    it 'passes the environment to the configure subplan as well as the install subplan' do
      captured = run_install_capturing_both_subplans(base_params.merge('pe_conf_data' => pe_conf_data))
      expect(captured[:install]['node_group_environment']).to eq('dev')
      expect(captured[:configure]['node_group_environment']).to eq('dev')
    end

    it 'passes service_ready_timeout to both subplans' do
      captured = run_install_capturing_both_subplans(base_params.merge('service_ready_timeout' => 300))
      expect(captured[:install]['service_ready_timeout']).to eq(300)
      expect(captured[:configure]['service_ready_timeout']).to eq(300)
    end

    it 'passes 60 to both subplans when service_ready_timeout is omitted' do
      captured = run_install_capturing_both_subplans(base_params)
      expect(captured[:install]['service_ready_timeout']).to eq(60)
      expect(captured[:configure]['service_ready_timeout']).to eq(60)
    end

    it 'rejects a service_ready_timeout of 0' do
      allow_out_message
      expect(run_plan('peadm::install', base_params.merge('service_ready_timeout' => 0))).not_to be_ok
    end
  end

  describe 'cloud_database_host plumbing' do
    # bolt-spec's `with_params` compares for strict equality and does not
    # honour rspec matchers like hash_including, so fine-grained param
    # assertions are awkward here. Confirm at minimum that providing
    # cloud_database_host does not break the install plan; the more
    # specific tests for the parameter's effect live in
    # spec/classes/setup/node_manager_spec.rb (verifying what the value
    # produces) and the configure subplan accepts the same parameter
    # signature by virtue of compiling.
    it 'accepts cloud_database_host and runs the plan to completion' do
      allow_out_message
      expect_plan('peadm::subplans::install')
      expect_plan('peadm::subplans::configure')
      expect(run_plan('peadm::install',
        'primary_host'        => 'primary',
        'console_password'    => 'puppetLabs123!',
        'version'             => '2021.7.9',
        'cloud_database_host' => 'cloud-sql.example.com')).to be_ok
    end
  end
end

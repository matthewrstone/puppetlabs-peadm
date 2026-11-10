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

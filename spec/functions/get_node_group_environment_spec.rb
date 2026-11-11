# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::get_node_group_environment' do
  include BoltSpec::BoltContext
  around(:each) do |example|
    in_bolt_context do
      example.run
    end
  end
  let(:primary) do
    ['test-vm.puppet.vm']
  end

  context 'returns production on empty pe.conf' do
    it do
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
      is_expected.to run.with_params(primary).and_return('production')
    end
  end

  context 'returns production on non-empty pe.conf with unrelated settings' do
    it do
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{"foo": true}' })
      is_expected.to run.with_params(primary).and_return('production')
    end
  end
  context 'returns environment from pe.conf when set twice correctly' do
    it do
      pe = '{"pe_install::install::classification::pe_node_group_environment": "foo", "puppet_enterprise::master::recover_configuration::pe_environment": "foo"}'
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => pe })
      is_expected.to run.with_params(primary).and_return('foo')
    end
  end
  context 'fails when both PE options are different' do
    it do
      pe = '{"pe_install::install::classification::pe_node_group_environment": "foo", "puppet_enterprise::master::recover_configuration::pe_environment": "bar"}'
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => pe })
      is_expected.to run.with_params(primary).and_raise_error(Puppet::PreformattedError,
%r{pe_install::install::classification::pe_node_group_environment and puppet_enterprise::master::recover_configuration::pe_environment})
    end
  end

  # P1-15: peadm::install has no pe.conf on any node yet, so it hands the
  # pe_conf_data Hash straight in. No task may be called for a Hash.
  context 'when given a pe.conf Hash instead of a target' do
    let(:both_keys) do
      ->(pe_install, puppet_enterprise) do
        {
          'pe_install::install::classification::pe_node_group_environment' => pe_install,
          'puppet_enterprise::master::recover_configuration::pe_environment' => puppet_enterprise,
        }
      end
    end

    # Catches a mutation that reads the Hash through a task, or ignores it.
    it 'returns production for an empty Hash without calling any task' do
      expect_task('peadm::read_file').not_be_called
      is_expected.to run.with_params({}).and_return('production')
    end

    it 'returns production for a Hash with unrelated settings' do
      is_expected.to run.with_params({ 'foo' => true }).and_return('production')
    end

    it 'returns the environment when both keys are set to it' do
      is_expected.to run.with_params(both_keys.call('dev', 'dev')).and_return('dev')
    end

    it 'fails naming both values when the keys differ' do
      is_expected.to run.with_params(both_keys.call('dev', 'test')).and_raise_error(Puppet::PreformattedError, %r{not 'dev' and 'test'})
    end

    # Catches a mutation that drops the name check: a name like this one would
    # reach the code-staging path of the site.pp stub.
    it 'fails when both keys hold a name that is not a valid Puppet environment name' do
      is_expected.to run.with_params(both_keys.call('Dev-1', 'Dev-1')).and_raise_error(Puppet::PreformattedError, %r{'Dev-1' is not a valid Puppet environment name})
    end

    it 'fails for a name that tries to leave the environments directory' do
      is_expected.to run.with_params(both_keys.call('../etc', '../etc')).and_raise_error(Puppet::PreformattedError, %r{not a valid Puppet environment name})
    end
  end
end

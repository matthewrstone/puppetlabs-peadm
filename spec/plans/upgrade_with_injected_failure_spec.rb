# frozen_string_literal: true

require 'spec_helper'

# TST-04, D-14: the injected-failure upgrade lives in a test-only plan, so
# peadm::upgrade carries no test knob. These examples stub peadm::upgrade and
# prove the plan's own contract: the fault is injected, the first upgrade must
# fail, the fault is removed on every path, and the resume uses the step each
# fault variant is meant for.
describe 'peadm_spec::upgrade_with_injected_failure' do
  include BoltSpec::Plans

  let(:inventory_data) do
    { 'targets' => targets }
  end
  let(:targets) { [{ 'name' => 'primary', 'vars' => { 'role' => 'primary' } }] }
  let(:code_manager_enabled) { true }
  let(:events) { [] }
  let(:upgrade_calls) { [] }
  let(:pe_versions) { ['2025.12.1', '2026.0.1'] }
  # Outcomes of successive peadm::upgrade calls: true succeeds, false fails.
  let(:upgrade_outcomes) { [false, true] }
  let(:upgrade_failure_message) { "upgrade exploded token=hunter2\nsecond line" }

  def command_result(target, stdout = '', exit_code = 0, stderr = '')
    Bolt::Result.for_command(target, { 'stdout' => stdout, 'stderr' => stderr, 'exit_code' => exit_code }, 'command', 'cmd', [])
  end

  # What a failing plan looks like to the caller: the Puppet evaluator wraps
  # the Bolt::PlanFailure in a PreformattedError, which run_plan turns into an
  # Error value only when the caller passed _catch_errors.
  def raise_plan_failure(message)
    raise Bolt::PlanFailure.new(message, 'bolt/plan-failure')
  rescue Bolt::PlanFailure
    raise Puppet::PreformattedError, message
  end

  before(:each) do
    allow_out_message
    version_reads = 0
    allow_any_command.return do |targets:, command:, **|
      events << [:command, command]
      stdout = case command
               when 'hostname -f' then "primary.example.com\n"
               when %r{\Acat /opt/puppetlabs/server/pe_version}
                 version = pe_versions[[version_reads, pe_versions.length - 1].min]
                 version_reads += 1
                 "#{version}\n"
               else ''
               end
      Bolt::ResultSet.new(targets.map { |t| command_result(t, stdout) })
    end
    allow_task('peadm::code_manager_enabled').always_return('code_manager_enabled' => code_manager_enabled)
    allow_task('peadm::code_manager').return do |targets:, params:, **|
      events << [:code_manager, params['action']]
      Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, value: {}) })
    end
    allow_task('peadm::puppet_runonce').return do |targets:, **|
      events << [:puppet_runonce]
      Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, value: {}) })
    end

    outcomes = upgrade_outcomes.dup
    allow_plan('peadm::upgrade').return do |params:, **|
      upgrade_calls << params
      events << [:upgrade, params['begin_at_step']]
      if outcomes.shift
        Bolt::PlanResult.new({}, 'success')
      else
        raise_plan_failure(upgrade_failure_message)
      end
    end
  end

  def run(params = {})
    run_plan('peadm_spec::upgrade_with_injected_failure', { 'version' => '2026.0.1' }.merge(params))
  end

  def command_events
    events.select { |e| e.first == :command }.map(&:last)
  end

  def index_of(kind, matcher = nil)
    events.index { |e| e.first == kind && (matcher.nil? || matcher.match?(e.last.to_s)) }
  end

  describe 'fault post-installer' do
    it 'injects a failing site.pp, fails the first upgrade, removes the fault and resumes at upgrade-node-groups' do
      result = run

      expect(result).to be_ok
      expect(result.value).to include(
        'fault'                 => 'post-installer',
        'resume_step'           => 'upgrade-node-groups',
        'resume_ok'             => true,
        'resume_error'          => nil,
        'version_after_failure' => '2025.12.1',
        'final_version'         => '2026.0.1',
      )
      expect(upgrade_calls.map { |p| p['begin_at_step'] }).to eq([nil, 'upgrade-node-groups'])
      expect(command_events.join("\n")).to include('peadm_spec injected failure')
    end

    it 'injects, restores and resumes in that order' do
      run

      injected = index_of(:command, %r{peadm_spec injected failure})
      first_upgrade = index_of(:upgrade, nil)
      restored = index_of(:command, %r{cp -p /root/peadm_spec_site\.pp\.orig})
      resume = events.rindex { |e| e.first == :upgrade }

      expect([injected, first_upgrade, restored, resume]).to all(be_a(Integer))
      expect(injected).to be < first_upgrade
      expect(first_upgrade).to be < restored
      expect(restored).to be < resume
    end

    it 'writes the fault under code-staging and commits it and the restore when Code Manager is enabled' do
      run

      commands = command_events.join("\n")
      expect(commands).to include('/etc/puppetlabs/code-staging/environments/production/manifests/site.pp')
      expect(commands).not_to match(%r{> /etc/puppetlabs/code/environments})
      expect(events.count { |e| e == [:code_manager, 'file-sync commit'] }).to eq(2)
    end

    context 'without Code Manager' do
      let(:code_manager_enabled) { false }

      it 'writes the fault to the live code dir and runs no file-sync commit' do
        run

        commands = command_events.join("\n")
        expect(commands).to include('> /etc/puppetlabs/code/environments/production/manifests/site.pp')
        expect(commands).not_to include('code-staging')
        expect(events.map(&:first)).not_to include(:code_manager)
      end
    end

    # Catches a mutation that skips the removal when the first upgrade unexpectedly succeeds.
    context 'when the first upgrade succeeds despite the fault' do
      let(:upgrade_outcomes) { [true] }

      it 'removes the fault, then fails with "injected fault did not trigger"' do
        result = run

        expect(result).not_to be_ok
        expect(result.value.msg).to include('injected fault did not trigger')
        expect(command_events.join("\n")).to match(%r{cp -p /root/peadm_spec_site\.pp\.orig})
        expect(upgrade_calls.length).to eq(1)
      end
    end

    context 'when the resume fails' do
      let(:upgrade_outcomes) { [false, false] }

      it 'fails the plan, after the fault was removed' do
        result = run

        expect(result).not_to be_ok
        expect(result.value.msg).to match(%r{Resume at 'upgrade-node-groups' failed})
        expect(index_of(:command, %r{cp -p /root/peadm_spec_site\.pp\.orig})).to be < events.rindex { |e| e.first == :upgrade }
      end
    end

    it 'records the first upgrade error sanitized to one line' do
      result = run

      expect(result.value['first_error']).to eq('upgrade exploded token=hunter2 second line')
      expect(result.value['first_error']).not_to include("\n")
    end
  end

  describe 'fault installer' do
    it 'resumes at upgrade-primary and reports resume_ok false without failing when the resume fails (UPG-04 baseline)' do
      outcomes = [false, false]
      allow_plan('peadm::upgrade').return do |params:, **|
        upgrade_calls << params
        events << [:upgrade, params['begin_at_step']]
        if outcomes.shift
          Bolt::PlanResult.new({}, 'success')
        else
          raise_plan_failure('no tarball to install')
        end
      end

      result = run('fault' => 'installer')

      expect(result).to be_ok
      expect(result.value).to include(
        'fault'        => 'installer',
        'resume_step'  => 'upgrade-primary',
        'resume_ok'    => false,
        'resume_error' => 'no tarball to install',
      )
      expect(upgrade_calls.map { |p| p['begin_at_step'] }).to eq([nil, 'upgrade-primary'])
    end

    it 'adds a pe-puppetdb drop-in, then removes it and reloads systemd before the resume' do
      run('fault' => 'installer')

      injected = index_of(:command, %r{ExecReload=.*peadm_spec_fault_reload\.sh})
      removed = index_of(:command, %r{rm -f /etc/systemd/system/pe-puppetdb\.service\.d/peadm-spec-fault\.conf})
      resume = events.rindex { |e| e.first == :upgrade }

      expect([injected, removed, resume]).to all(be_a(Integer))
      expect(injected).to be < removed
      expect(removed).to be < resume
      expect(command_events.join("\n")).to include('systemctl daemon-reload')
      expect(events.map(&:first)).not_to include(:code_manager)
    end
  end

  # Catches a mutation that lets the fault outlive a failed fault injection.
  describe 'when injection itself fails' do
    it 'still tries the removal and fails without running peadm::upgrade' do
      allow_any_command.return do |targets:, command:, **|
        events << [:command, command]
        failing = command.include?('peadm_spec injected failure')
        Bolt::ResultSet.new(targets.map do |t|
          failing ? command_result(t, '', 1, 'disk full') : command_result(t, "primary.example.com\n")
        end)
      end

      result = run

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Could not inject fault 'post-installer'})
      expect(upgrade_calls).to be_empty
      expect(command_events.join("\n")).to match(%r{cp -p /root/peadm_spec_site\.pp\.orig})
    end
  end

  describe 'inventory checks' do
    let(:targets) do
      [
        { 'name' => 'primary', 'vars' => { 'role' => 'primary' } },
        { 'name' => 'spare', 'vars' => { 'role' => 'spare-replica' } },
      ]
    end

    it 'refuses an inventory with roles other than primary (standard architecture only)' do
      result = run

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{standard architecture only.*spare})
      expect(upgrade_calls).to be_empty
    end
  end

  it 'rejects an unknown fault name' do
    result = run('fault' => 'nonsense')

    expect(result).not_to be_ok
    expect(upgrade_calls).to be_empty
  end
end

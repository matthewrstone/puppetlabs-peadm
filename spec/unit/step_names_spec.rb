# frozen_string_literal: true

require 'spec_helper'

# P0-1 was a step-name/type mismatch: the plan named its steps one thing and the
# begin_at_step type listed another, so a resumed convert skipped every step.
# These examples read the .pp sources and fail when the two drift apart.
module StepNamesHelper
  ROOT = File.expand_path('../..', __dir__)

  # plan file => [type name, type file]
  PLANS = {
    'plans/upgrade.pp' => ['Peadm::UpgradeSteps', 'types/upgradesteps.pp'],
    'plans/convert.pp' => ['Peadm::ConvertSteps', 'types/convertsteps.pp'],
    'plans/add_database.pp' => ['Peadm::AddDatabaseSteps', 'types/adddatabasesteps.pp'],
  }.freeze

  # @return [Array<String>] names passed to peadm::plan_step in the given plan text
  def self.step_names(plan_text)
    plan_text.scan(%r{plan_step\('([^']+)'\)}).flatten
  end

  # @return [Array<String>] the Enum values declared by a type file's text
  def self.enum_values(type_text)
    type_text[%r{Enum\[(.*?)\]}m, 1].to_s.scan(%r{'([^']+)'}).flatten
  end

  def self.read(path)
    File.read(File.join(ROOT, path))
  end
end

describe 'plan step names' do
  StepNamesHelper::PLANS.each do |plan, (type_name, type_file)|
    describe plan do
      it "uses #{type_name} for begin_at_step" do
        expect(StepNamesHelper.read(plan)).to match(%r{Optional\[#{Regexp.escape(type_name)}\]\s+\$begin_at_step})
      end

      it "names exactly the steps #{type_name} lists, in the same order" do
        expect(StepNamesHelper.step_names(StepNamesHelper.read(plan))).to eq(StepNamesHelper.enum_values(StepNamesHelper.read(type_file)))
      end
    end
  end

  it 'declares a Peadm::*Steps begin_at_step in every plan that calls plan_step' do
    offenders = Dir.glob(File.join(StepNamesHelper::ROOT, 'plans/**/*.pp')).select do |f|
      text = File.read(f)
      text.include?('plan_step(') && text !~ %r{Optional\[Peadm::\w+Steps\]\s+\$begin_at_step}
    end
    expect(offenders.map { |f| f.sub("#{StepNamesHelper::ROOT}/", '') }).to eq([])
  end

  describe 'the parsing helpers' do
    let(:plan_text) do
      <<~PUPPET
        peadm::plan_step('one') || { }
        peadm::plan_step('two') || { }
      PUPPET
    end

    it 'extracts step names in order' do
      expect(StepNamesHelper.step_names(plan_text)).to eq(['one', 'two'])
    end

    # Catches a mutation that renames one step: the comparison used by the drift
    # example must then differ from the type's values.
    it 'reports a difference when one step is renamed' do
      type_values = StepNamesHelper.enum_values("type Peadm::X = Enum['one', 'two']")
      expect(StepNamesHelper.step_names(plan_text)).to eq(type_values)
      expect(StepNamesHelper.step_names(plan_text.sub("'two'", "'twp'"))).not_to eq(type_values)
    end

    it 'reads multi-line Enum values' do
      expect(StepNamesHelper.enum_values("type Peadm::X = Enum[\n  'a',\n  'b'\n]")).to eq(['a', 'b'])
    end
  end
end

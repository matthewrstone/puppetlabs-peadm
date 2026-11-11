# frozen_string_literal: true

require 'spec_helper'
require_relative '../acceptance/scenarios'

describe PeadmScenarios do
  let(:scenarios) { described_class.load }

  it 'has a well-formed catalog' do
    expect(described_class.validate(scenarios)).to eq([])
  end

  it 'keeps documentation/test-scenarios.md in sync with the catalog' do
    expect(File.read(described_class::DOC)).to eq(described_class.markdown(scenarios))
  end

  it 'reports a downgrade scenario that the upgrade plan spec covers' do
    expect(scenarios.find { |s| s['id'] == 'D-01' }['status']).to eq('unit')
  end

  describe '.matrix' do
    it 'only includes scenarios with an existing workflow and concrete versions' do
      matrix = described_class.matrix(scenarios.select { |s| s['status'] == 'ci' })['include']
      expect(matrix).not_to be_empty
      expect(matrix.map { |m| m['workflow'] }.uniq).to all(match(%r{\Atest-.*\.ya?ml\z}))
      expect(matrix.map { |m| m['version'] }).to all(match(described_class::CONCRETE))
    end
  end
end

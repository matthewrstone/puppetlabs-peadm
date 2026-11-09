# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::supported_pe_versions' do
  it 'returns the oldest and newest supported PE versions from data/pe_versions.yaml' do
    is_expected.to run.with_params.and_return({ 'oldest' => '2019.7', 'newest' => '2026.0' })
  end

  it 'reads a range that assert_supported_pe_version accepts as a semver range' do
    range = YAML.safe_load_file(File.join(__dir__, '..', '..', 'data', 'pe_versions.yaml'))
    expect(range.keys).to contain_exactly('oldest', 'newest')
    expect(range.values).to all(match(%r{\A\d{4}\.\d+\z}))
  end
end

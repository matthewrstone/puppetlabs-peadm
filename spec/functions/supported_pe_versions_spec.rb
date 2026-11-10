# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::supported_pe_versions' do
  let(:data) { YAML.safe_load_file(File.join(__dir__, '..', '..', 'data', 'pe_versions.yaml')) }

  it 'returns the oldest, newest and default supported PE versions from data/pe_versions.yaml' do
    is_expected.to run.with_params.and_return({ 'oldest' => '2019.7', 'newest' => '2026.0', 'default' => '2025.12.1' })
  end

  it 'reads a range that assert_supported_pe_version accepts as a semver range' do
    expect(data.keys).to contain_exactly('oldest', 'newest', 'default')
    expect(data.values_at('oldest', 'newest')).to all(match(%r{\A\d{4}\.\d+\z}))
  end

  # Catches a mutation that lets `default` drift outside the supported range
  # (for example a newest bump that forgets the default, or a default bump past
  # newest): peadm::install would then install a version its own
  # assert_supported_pe_version refuses, or one that is only safe with
  # permit_unsafe_versions.
  it 'keeps the default inside oldest..newest and shaped like a Peadm::Pe_version' do
    expect(data['default']).to match(%r{\A\d+\.\d+\.\d+(-.+)?\z})
    range = SemanticPuppet::VersionRange.parse(">= #{data['oldest']} <= #{data['newest']}")
    expect(range.include?(SemanticPuppet::Version.parse(data['default']))).to be(true),
                                                                              "default #{data['default']} is outside the supported range #{data['oldest']}..#{data['newest']}"
  end
end

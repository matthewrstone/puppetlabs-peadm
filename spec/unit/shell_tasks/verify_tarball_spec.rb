# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

describe 'tasks/verify_tarball.sh' do
  let(:harness) { ShellTaskHarness.new }
  let(:good) { File.join(harness.root, 'good.tar.gz') }
  let(:message_suffix) { 'Remove the file and download it again before re-running the plan.' }

  before(:each) do
    src = File.join(harness.root, 'src', 'puppet-enterprise-2025.12.1-el-9-x86_64')
    FileUtils.mkdir_p(src)
    File.write(File.join(src, 'puppet-enterprise-installer'), "#!/bin/bash\n# padding #{'x' * 20_000}\n")
    system('tar', '-C', File.join(harness.root, 'src'), '-czf', good,
           'puppet-enterprise-2025.12.1-el-9-x86_64/puppet-enterprise-installer', exception: true)
  end

  after(:each) { harness.cleanup }

  def verify(path)
    harness.run('verify_tarball.sh', { path: path })
  end

  # Catches a mutation that rejects a healthy archive, which would block every upgrade.
  it 'accepts a good archive and reports its size' do
    result = verify(good)
    expect(result[:status]).to eq(0)
    expect(result[:json]).to eq('valid' => true, 'size' => File.size(good))
  end

  # Catches a mutation that lets a truncated download through to the extraction
  # step, after services are stopped.
  it 'rejects a truncated archive' do
    truncated = File.join(harness.root, 'truncated.tar.gz')
    File.binwrite(truncated, File.binread(good, 200))
    result = verify(truncated)
    expect(result[:status]).not_to eq(0)
    expect(result[:stderr]).to include("Puppet Enterprise tarball #{truncated} failed verification: gzip integrity check failed")
    expect(result[:stderr]).to include(message_suffix)
  end

  # Catches a mutation that drops the empty-file check.
  it 'rejects an empty file' do
    empty = File.join(harness.root, 'empty.tar.gz')
    FileUtils.touch(empty)
    result = verify(empty)
    expect(result[:status]).not_to eq(0)
    expect(result[:stderr]).to include('failed verification: file is empty')
  end

  # Catches a mutation that accepts any readable tar, not only a PE installer.
  it 'rejects an archive with no puppet-enterprise-installer' do
    src = File.join(harness.root, 'other', 'some-dir')
    FileUtils.mkdir_p(src)
    File.write(File.join(src, 'readme.txt'), 'hello')
    wrong = File.join(harness.root, 'wrong.tar.gz')
    system('tar', '-C', File.join(harness.root, 'other'), '-czf', wrong, 'some-dir/readme.txt', exception: true)
    result = verify(wrong)
    expect(result[:status]).not_to eq(0)
    expect(result[:stderr]).to include('archive does not contain puppet-enterprise-installer')
  end

  # Catches a mutation that drops the existence check.
  it 'rejects a missing file' do
    result = verify(File.join(harness.root, 'missing.tar.gz'))
    expect(result[:status]).not_to eq(0)
    expect(result[:stderr]).to include('failed verification: file does not exist')
  end
end

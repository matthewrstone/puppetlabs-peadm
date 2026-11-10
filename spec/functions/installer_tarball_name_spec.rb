# frozen_string_literal: true

require 'spec_helper'

# P1-23: the installer file name is derived from the URL in three plan sites;
# a pre-signed URL must not leak its query string through any of them.
describe 'peadm::installer_tarball_name' do
  name = 'puppet-enterprise-2025.12.1-el-9-x86_64.tar.gz'

  # Catches a mutation that splits on "/" only, which returns the file name
  # with the signature attached.
  it 'strips a query string' do
    is_expected.to run.with_params("https://h/p/#{name}?X-Amz-Signature=abc").and_return(name)
  end

  it 'strips a fragment' do
    is_expected.to run.with_params('https://h/p/puppet-enterprise-2025.12.1-el-9-x86_64.tar#frag').and_return('puppet-enterprise-2025.12.1-el-9-x86_64.tar')
  end

  # A slash inside the query (an S3 credential scope) must not be taken for
  # the last path segment.
  it 'is not fooled by slashes inside the query string' do
    is_expected.to run.with_params("https://h/p/#{name}?X-Amz-Credential=KEY/20251201/us-east-1/s3/aws4_request&X-Amz-Signature=abc").and_return(name)
  end

  it 'strips a query string followed by a fragment' do
    is_expected.to run.with_params("https://h/p/#{name}?a=b#frag").and_return(name)
  end

  it 'leaves the name of a plain URL unchanged' do
    is_expected.to run.with_params("https://h/p/#{name}").and_return(name)
  end

  it 'returns the name of a URL with no path beyond the host directory' do
    is_expected.to run.with_params("https://h/#{name}").and_return(name)
  end

  it 'rejects an empty string' do
    is_expected.to run.with_params('').and_raise_error(ArgumentError)
  end
end

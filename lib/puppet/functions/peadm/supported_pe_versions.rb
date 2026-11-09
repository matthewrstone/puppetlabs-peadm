# frozen_string_literal: true

require 'yaml'

# Returns the range of PE versions this release of peadm supports, from
# data/pe_versions.yaml, as a Hash with 'oldest' and 'newest' keys.
Puppet::Functions.create_function(:'peadm::supported_pe_versions') do
  dispatch :supported_pe_versions do
    return_type 'Struct[{oldest => String, newest => String}]'
  end

  def supported_pe_versions
    path = File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'data', 'pe_versions.yaml')
    data = YAML.safe_load_file(path)
    { 'oldest' => data.fetch('oldest').to_s, 'newest' => data.fetch('newest').to_s }
  end
end

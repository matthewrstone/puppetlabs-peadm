# frozen_string_literal: true

require 'yaml'

# Returns the supported PE version range and the install default from
# data/pe_versions.yaml, as a Hash with 'oldest', 'newest' and 'default' keys.
Puppet::Functions.create_function(:'peadm::supported_pe_versions') do
  dispatch :supported_pe_versions do
    # `default` is a reserved word in the Puppet language, so as a Struct key it must be quoted.
    return_type 'Struct[{oldest => String, newest => String, "default" => String}]'
  end

  def supported_pe_versions
    path = File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'data', 'pe_versions.yaml')
    data = YAML.safe_load_file(path)
    { 'oldest' => data.fetch('oldest').to_s, 'newest' => data.fetch('newest').to_s, 'default' => data.fetch('default').to_s }
  end
end

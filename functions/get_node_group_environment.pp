#
# @summary check if a custom PE environment is set in pe.conf
#
# @param primary
#   Either the FQDN (or Target) of the primary, whose pe.conf is read, or a Hash
#   holding pe.conf data directly (for example the `pe_conf_data` given to
#   peadm::install, before any pe.conf exists on a node).
#
# @return [Peadm::Pe_environment] the desired environment for PE specific node groups
#
# @see https://www.puppet.com/docs/pe/latest/upgrade_pe#update_environment
#
# @author Tim Meusel <tim@bastelfreak.de>
#
function peadm::get_node_group_environment(Variant[Peadm::SingleTargetSpec, Hash] $primary) {
  $peconf = $primary ? {
    Hash    => $primary,
    default => peadm::get_pe_conf(get_target($primary)),
  }
  # if both are set, they need to be set to the same value
  # if they are not set, we assume that the user runs their infra in production
  $pe_install = $peconf['pe_install::install::classification::pe_node_group_environment']
  $puppet_enterprise = $peconf['puppet_enterprise::master::recover_configuration::pe_environment']

  # check if both are equal
  # This also evaluates to true if both are undef
  if $pe_install == $puppet_enterprise {
    # check if the option isn't undef
    if $pe_install =~ String[1] {
      # The name ends up in a path under code-staging, so reject anything that
      # is not a valid Puppet environment name before it gets there.
      assert_type(Peadm::Pe_environment, $pe_install) |$expected, $actual| {
        fail("The PE node group environment '${pe_install}' is not a valid Puppet environment name: use only lowercase letters, digits and underscores (set in pe_install::install::classification::pe_node_group_environment and puppet_enterprise::master::recover_configuration::pe_environment)") # lint:ignore:140chars
      }
      return $pe_install
    } else {
      return 'production'
    }
  } else {
    fail("pe_install::install::classification::pe_node_group_environment and puppet_enterprise::master::recover_configuration::pe_environment need to be set to the same value, not '${pe_install}' and '${puppet_enterprise}'") # lint:ignore:140chars
  }
}

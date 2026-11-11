# @summary Restore the CA and ssl certificates from a puppet-backup certs archive
#
# @param target The primary puppetserver to restore the certificates on
# @param file_path The puppet-backup archive (scope certs) to restore from
# @param recovery_directory Temporary directory puppet-backup restore works in
# @param node_group_environment
#   The environment passed to `puppet-backup restore --pe-environment` when it is not production.
#   Defaults to the one set in the target's pe.conf, then to production.
plan peadm::restore_ca(
  Peadm::SingleTargetSpec         $target,
  String                          $file_path,
  Optional[String]                $recovery_directory = '/tmp/peadm_recovery',
  Optional[Peadm::Pe_environment] $node_group_environment = undef,
) {
  # PE defaults to production; anything else has to be named. The value is
  # typed Peadm::Pe_environment (parameter or pe.conf) and shell-quoted before
  # it reaches the command line. (PE-46598)
  $restore_environment = $node_group_environment ? {
    undef   => peadm::get_node_group_environment($target),
    default => $node_group_environment,
  }

  # Appended right after `--force`. Empty for production, so production
  # clusters run the command they always did.
  $pe_environment_flag = $restore_environment ? {
    'production' => '',
    default      => " --pe-environment=${shellquote($restore_environment)}",
  }

  out::message('# Restoring ca and ssl certificates')

  # lint:ignore:strict_indent
  run_command(@("CMD"/L), $target)
        /opt/puppetlabs/bin/puppet-backup restore \
    --scope=certs \
    --tempdir=${shellquote($recovery_directory)} \
    --force${pe_environment_flag} \
    ${shellquote($file_path)}
  | CMD
  # lint:endignore
}

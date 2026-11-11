# @api private
#
# @summary Copy one file's content from a source host to the target hosts
#
# @param targets
#   The hosts that receive the file
# @param source_host
#   The single host the content is read from
# @param path
#   Absolute path of the file, the same on the source and on every target
# @param mode
#   File mode written on the targets. When omitted, a path with a `/secrets/`
#   directory in it gets 0600 and any other path 0644.
plan peadm::util::copy_file(
  TargetSpec                           $targets,
  Peadm::SingleTargetSpec              $source_host,
  Stdlib::Absolutepath                 $path,
  Optional[Pattern[/\A0?[0-7]{3}\z/]] $mode = undef
) {
  $source_target   = peadm::get_targets($source_host, 1)
  $replica_target  = $targets

  # The key stores under a secrets/ directory (orchestration and console
  # encryption keys) must not be readable by other users on the target, so they
  # default to 0600, not the old blanket 0644. Why 0600 and not the source file's
  # mode: the source may itself be world-readable on an older primary, and
  # reading its mode would need a stat through peadm::read_file. Ownership stays
  # root:root; PE's own Puppet run on the replica sets the final owner and mode
  # before its services read the files, which plan 01-13's replica read check
  # confirms. mkdir_p_file applies the mode to the empty file before it writes
  # the content, so there is no world-readable window.
  $effective_mode = $mode ? {
    undef   => $path ? {
      /\/secrets\// => '0600',
      default       => '0644',
    },
    default => $mode,
  }

  $source_content = run_task('peadm::read_file', $source_target,
    path => $path
  ).first['content']

  if $source_content {
    run_task('peadm::mkdir_p_file', $replica_target,
      path    => $path,
      owner   => 'root',
      group   => 'root',
      mode    => $effective_mode,
      content => $source_content,
    )
  } else {
    out::message("Skipping file copy: ${path} on ${source_target.peadm::certname()} had no content")
  }
}

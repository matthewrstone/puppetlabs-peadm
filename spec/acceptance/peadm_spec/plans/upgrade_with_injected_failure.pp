# TST-04, D-14: upgrade a standard cluster n to n+1, inject a failure, remove it
# and resume with begin_at_step. The fault lives here, in a test-only plan; there
# is no test knob in peadm::upgrade.
#
# Fault placement (RESEARCH Pitfall 6):
#   post-installer  The installer exits 0 and the next Puppet run fails, so the
#                   first peadm::upgrade stops inside the upgrade-primary step
#                   after the PE packages are upgraded. The plan resumes at
#                   upgrade-node-groups. This is the Phase 1 gate.
#   installer       pe-puppetdb fails its first reload, so the installer fails.
#                   The plan resumes at upgrade-primary, which has no tarball
#                   because pe_install deletes it before running the installer
#                   (UPG-04, Phase 2). The resume is expected to fail today; the
#                   outcome is recorded as the UPG-04 baseline, not as a defect.
#
# The fault is removed on every path that returns or fails after injection. If a
# run is interrupted before that, clean up by hand:
#   post-installer  restore /root/peadm_spec_site.pp.orig over the site.pp it
#                   was taken from (code-staging when Code Manager is enabled,
#                   the live code dir otherwise), or delete site.pp when only
#                   /root/peadm_spec_site.pp.orig.absent exists, then run
#                   `puppet code deploy production --wait` or
#                   `puppet-code file-sync commit` as appropriate.
#   installer       delete /etc/systemd/system/pe-puppetdb.service.d/peadm-spec-fault.conf,
#                   /usr/local/bin/peadm_spec_fault_reload.sh and
#                   /var/tmp/peadm_spec_fault_reload.marker, then run
#                   `systemctl daemon-reload`.
#
# Standard architecture only: the inventory must hold one `primary` target.
plan peadm_spec::upgrade_with_injected_failure(
  String[1]           $version,
  Optional[String[1]] $pe_installer_source    = undef,
  String              $download_mode          = 'direct',
  Boolean             $permit_unsafe_versions = false,
  Enum['post-installer', 'installer'] $fault  = 'post-installer',
) {
  $t = get_targets('*')
  wait_until_available($t)

  parallelize($t) |$target| {
    $fqdn = run_command('hostname -f', $target)
    $target.set_var('certname', $fqdn.first['stdout'].chomp)
  }

  $unsupported = $t.filter |$n| { $n.vars['role'] != 'primary' }
  unless $unsupported == [] {
    $unsupported_names = $unsupported.map |$n| { $n.name }.join(', ')
    fail_plan(@("EOL"/L))
      peadm_spec::upgrade_with_injected_failure supports the standard architecture only; \
      the inventory has targets with a role other than 'primary': ${unsupported_names}. \
      Add the spare replica after this plan has run.
      | EOL
  }

  $primary_target = $t.filter |$n| { $n.vars['role'] == 'primary' }
  unless $primary_target.length == 1 {
    fail_plan('Exactly one target with role "primary" is required in the inventory')
  }

  $code_manager_enabled = run_task('peadm::code_manager_enabled', $primary_target).first.value['code_manager_enabled']

  # With Code Manager, file-sync overwrites the live code dir from code-staging,
  # so the fault goes into code-staging and is committed.
  $site_path = $code_manager_enabled ? {
    true    => '/etc/puppetlabs/code-staging/environments/production/manifests/site.pp',
    default => '/etc/puppetlabs/code/environments/production/manifests/site.pp',
  }
  $site_backup = '/root/peadm_spec_site.pp.orig'
  $dropin_dir  = '/etc/systemd/system/pe-puppetdb.service.d'
  $dropin_conf = "${dropin_dir}/peadm-spec-fault.conf"
  $reload_script = '/usr/local/bin/peadm_spec_fault_reload.sh'
  $reload_marker = '/var/tmp/peadm_spec_fault_reload.marker'

  # An existing backup means an earlier run was interrupted with the fault still
  # in place; keep that backup instead of copying the fault over the original.
  $inject_command = $fault ? {
    'post-installer' => @("EOS"/L$),
      set -e; \
      mkdir -p "\$(dirname ${site_path})"; \
      if [ ! -e ${site_backup} ] && [ ! -e ${site_backup}.absent ]; then \
        if [ -f ${site_path} ]; then cp -p ${site_path} ${site_backup}; else touch ${site_backup}.absent; fi; \
      fi; \
      echo "fail('peadm_spec injected failure')" > ${site_path}; \
      chown --reference="\$(dirname ${site_path})" ${site_path}
      | EOS
    default          => @("EOS"/L$),
      set -e; \
      mkdir -p ${dropin_dir}; \
      printf '%s\n' '#!/bin/sh' 'if [ ! -e ${reload_marker} ]; then touch ${reload_marker}; exit 1; fi' 'exit 0' > ${reload_script}; \
      chmod 755 ${reload_script}; \
      printf '%s\n' '[Service]' 'ExecReload=' 'ExecReload=${reload_script}' > ${dropin_conf}; \
      rm -f ${reload_marker}; \
      systemctl daemon-reload
      | EOS
  }

  $remove_command = $fault ? {
    'post-installer' => @("EOS"/L$),
      set -e; \
      if [ -f ${site_backup} ]; then \
        cp -p ${site_backup} ${site_path}; rm -f ${site_backup}; \
      elif [ -f ${site_backup}.absent ]; then \
        rm -f ${site_path} ${site_backup}.absent; \
      fi
      | EOS
    default          => @("EOS"/L$),
      set -e; \
      rm -f ${dropin_conf} ${reload_script} ${reload_marker}; \
      systemctl daemon-reload
      | EOS
  }

  $upgrade_params = {
    primary_host           => $primary_target,
    download_mode          => $download_mode,
    version                => $version,
    pe_installer_source    => $pe_installer_source,
    permit_unsafe_versions => $permit_unsafe_versions,
  }

  $resume_step = $fault ? {
    'post-installer' => 'upgrade-node-groups',
    default          => 'upgrade-primary',
  }

  out::message("Injecting fault '${fault}' on ${$primary_target[0].name}")
  $injected = run_command($inject_command, $primary_target, '_catch_errors' => true)
  if $code_manager_enabled and $fault == 'post-installer' and $injected.ok {
    run_task('peadm::code_manager', $primary_target, action => 'file-sync commit')
  }

  # From here every path removes the fault before it returns or fails.
  if $injected.ok {
    $first = run_plan('peadm::upgrade', $upgrade_params + { '_catch_errors' => true })
  } else {
    $first = undef
  }

  $first_failed = $first =~ Error
  $first_error = $first_failed ? {
    true    => peadm::sanitize_log_text("${first.message}", 500),
    default => undef,
  }

  # Every read after injection tolerates failure so that the removal below still runs.
  $after_failure = run_command('cat /opt/puppetlabs/server/pe_version', $primary_target, '_catch_errors' => true).first
  $version_after_failure = $after_failure.ok ? {
    true    => $after_failure['stdout'].strip,
    default => undef,
  }

  out::message("Removing fault '${fault}'")
  $removed = run_command($remove_command, $primary_target, '_catch_errors' => true)
  if $removed.ok and $code_manager_enabled and $fault == 'post-installer' {
    run_task('peadm::code_manager', $primary_target, action => 'file-sync commit', '_catch_errors' => true)
  }

  unless $injected.ok {
    $inject_error = peadm::sanitize_log_text("${injected.first.error.message}", 300)
    fail_plan("Could not inject fault '${fault}': ${inject_error}")
  }

  unless $removed.ok {
    $remove_error = peadm::sanitize_log_text("${removed.first.error.message}", 300)
    fail_plan(@("EOL"/L))
      Could not remove fault '${fault}' from ${$primary_target[0].name}; clean it up by hand \
      (see the header of peadm_spec::upgrade_with_injected_failure): ${remove_error}
      | EOL
  }

  if $fault == 'post-installer' and ! $first_failed {
    fail_plan('injected fault did not trigger: the first peadm::upgrade succeeded with the fault in place')
  }

  out::message("Resuming peadm::upgrade at '${resume_step}'")
  $resume_params = $upgrade_params + { 'begin_at_step' => $resume_step, '_catch_errors' => true }
  $resume = run_plan('peadm::upgrade', $resume_params)
  $resume_failed = $resume =~ Error
  $resume_error = $resume_failed ? {
    true    => peadm::sanitize_log_text("${resume.message}", 500),
    default => undef,
  }

  if $resume_failed and $fault == 'post-installer' {
    fail_plan("Resume at '${resume_step}' failed after the fault was removed: ${resume_error}")
  }

  $final_run = run_task('peadm::puppet_runonce', $primary_target, '_catch_errors' => true)
  $final_version_result = run_command('cat /opt/puppetlabs/server/pe_version', $primary_target, '_catch_errors' => true).first
  $final_version = $final_version_result.ok ? {
    true    => $final_version_result['stdout'].strip,
    default => undef,
  }

  $report = {
    'fault'                 => $fault,
    'first_error'           => $first_error,
    'version_after_failure' => $version_after_failure,
    'resume_step'           => $resume_step,
    'resume_ok'             => ! $resume_failed,
    'resume_error'          => $resume_error,
    'final_version'         => $final_version,
    'final_puppet_run_ok'   => $final_run.ok,
  }

  out::message("Result: ${stdlib::to_json_pretty($report)}")
  return $report
}

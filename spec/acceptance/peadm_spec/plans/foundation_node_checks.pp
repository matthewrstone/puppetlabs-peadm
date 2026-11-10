# TST-03, TST-02, TRC-01: answer, on a real node, the questions Phase 1 research
# could not settle from the repo alone (PE 2026 CA backend location, the CA
# status endpoint, validate_cert's shared-file path on a node, /tmp/pe.conf
# removal, secret file and token modes) and, when a replica is in the inventory,
# the FND-06 gate (the replica's service users can still read the copied
# secrets/ key stores).
#
# Every check tolerates its own failure so one missing file never hides the rest.
# The returned hash holds modes, finding codes, booleans and versions only; it
# never contains file contents, so it is safe to paste into the change ledger.
#
# Inventory: one target with role `primary`; optionally one with role
# `spare-replica` or `replica`.
plan peadm_spec::foundation_node_checks() {
  $t = get_targets('*')
  wait_until_available($t)

  $primary_target = $t.filter |$n| { $n.vars['role'] == 'primary' }
  unless $primary_target.length == 1 {
    fail_plan('Exactly one target with role "primary" is required in the inventory')
  }
  $replica_target = $t.filter |$n| { $n.vars['role'] in ['spare-replica', 'replica'] }

  # Key stores that peadm::add_replica copies to the replica, and the service
  # user that has to be able to read each one.
  $secret_files = {
    '/etc/puppetlabs/orchestration-services/conf.d/secrets/keys.json'                         => 'pe-orchestration-services',
    '/etc/puppetlabs/orchestration-services/conf.d/secrets/orchestrator-encryption-keys.json' => 'pe-orchestration-services',
    '/etc/puppetlabs/console-services/conf.d/secrets/keys.json'                               => 'pe-console-services',
  }
  $secret_paths = $secret_files.keys.join(' ')
  $stat_secrets = "stat -c '%a %U %G %n' ${secret_paths} 2>&1"

  # CA backend: the shipped task against a grep of the files it should be reading.
  $ca_backend_result = run_task('peadm::ca_storage_backend', $primary_target, '_catch_errors' => true).first
  $ca_backend = $ca_backend_result.ok ? {
    true    => $ca_backend_result.value - '_output',
    default => { 'error_kind' => $ca_backend_result.error.kind },
  }

  $grep_command = @("EOS"/L)
    grep -rnHF -e 'puppetlabs.services.ca.database-storage-service' \
    /etc/puppetlabs/puppetserver /opt/puppetlabs/server/apps/puppetserver/config 2>/dev/null | cut -d: -f1,2
    | EOS
  $grep_result = run_command($grep_command.strip, $primary_target, '_catch_errors' => true).first
  $ca_backend_grep = $grep_result['stdout'].split("\n").filter |$l| { $l != '' }

  # Does the CA status endpoint answer within 30 seconds (FND-07)?
  $ca_status_result = run_task('peadm::wait_until_service_ready', $primary_target,
    service         => 'ca',
    port            => '8140',
    timeout         => 30,
    '_catch_errors' => true,
  ).first
  $ca_status = {
    'ok'         => $ca_status_result.ok,
    'error_kind' => $ca_status_result.ok ? { true => undef, default => $ca_status_result.error.kind },
  }

  # validate_cert against the node's own certificate files: proves the shared
  # cert_check.rb layout resolves on a node (RESEARCH A2).
  $ssl_settings = 'hostcert hostprivkey localcacert hostcrl'
  $ssl_command = "/opt/puppetlabs/bin/puppet config print ${ssl_settings} --section agent"
  $ssl_paths_result = run_command($ssl_command, $primary_target, '_catch_errors' => true).first
  $ssl_paths = $ssl_paths_result['stdout'].split("\n").reduce({}) |$memo, $line| {
    $m = $line.match(/\A(\w+) = (.+)\z/)
    $m ? {
      undef   => $memo,
      default => $memo + { $m[1] => $m[2] },
    }
  }

  if $ssl_paths_result.ok and $ssl_paths['hostcert'] =~ String[1] {
    $validate_result = run_task('peadm::validate_cert', $primary_target,
      cert_path       => $ssl_paths['hostcert'],
      key_path        => $ssl_paths['hostprivkey'],
      chain_path      => $ssl_paths['localcacert'],
      crl_path        => $ssl_paths['hostcrl'],
      '_catch_errors' => true,
    ).first
    $validate_cert = $validate_result.ok ? {
      true    => {
        'task_ok'  => true,
        'cert_ok'  => $validate_result['ok'],
        'findings' => $validate_result['findings'].map |$f| { "${f['severity']}:${f['code']}" },
      },
      default => { 'task_ok' => false, 'error_kind' => $validate_result.error.kind },
    }
  } else {
    $validate_cert = { 'task_ok' => false, 'error_kind' => 'peadm_spec/ssl-paths-unavailable' }
  }

  $pe_conf_absent = run_command('test ! -e /tmp/pe.conf', $primary_target, '_catch_errors' => true).ok
  $secret_file_modes = run_command($stat_secrets, $primary_target, '_catch_errors' => true).first['stdout'].split("\n")
  $token_stat = run_command("stat -c '%a %U %G %n' /root/.puppetlabs/token 2>&1", $primary_target, '_catch_errors' => true).first
  $token_mode = $token_stat['stdout'].strip

  $pe_version_result = run_command('cat /opt/puppetlabs/server/pe_version', $primary_target, '_catch_errors' => true).first
  $puppet_version_result = run_command('/opt/puppetlabs/bin/puppet --version', $primary_target, '_catch_errors' => true).first

  $primary_report = {
    'ca_backend'        => $ca_backend,
    'ca_backend_grep'   => $ca_backend_grep,
    'ca_status'         => $ca_status,
    'validate_cert'     => $validate_cert,
    'pe_conf_absent'    => $pe_conf_absent,
    'secret_file_modes' => $secret_file_modes,
    'token_mode'        => $token_mode,
    'pe_version'        => $pe_version_result['stdout'].strip,
    'puppet_version'    => $puppet_version_result['stdout'].strip,
    'bolt_version'      => peadm::bolt_version(),
  }

  # FND-06 gate: after add_replica, the replica's service users read the key
  # stores peadm::util::copy_file wrote 0600, and both services are active.
  if $replica_target.length > 0 {
    $replica_stat = run_command($stat_secrets, $replica_target, '_catch_errors' => true).first['stdout'].split("\n")

    $replica_secrets = $secret_files.reduce({}) |$memo, $pair| {
      $path = $pair[0]
      $user = $pair[1]
      $read = run_command("runuser -u ${user} -- test -r ${path}", $replica_target, '_catch_errors' => true).ok
      $stat_lines = $replica_stat.filter |$l| { $l.regsubst(/\A\S+ \S+ \S+ /, '') == $path }
      $memo + {
        $path => {
          'stat'         => $stat_lines[0],
          'service_user' => $user,
          'readable'     => $read,
        },
      }
    }

    $services = run_command(
      'systemctl is-active pe-orchestration-services pe-console-services',
      $replica_target,
      '_catch_errors' => true,
    ).first
    $replica_services_active = {
      'ok'     => $services.ok,
      'states' => $services['stdout'].split("\n").filter |$l| { $l != '' },
    }

    $all_readable = $replica_secrets.values.all |$s| { $s['readable'] }
    $replica_report = {
      'replica_secrets'          => $replica_secrets,
      'replica_services_active'  => $replica_services_active,
      'replica_secrets_readable' => $all_readable and $services.ok,
    }
  } else {
    $replica_report = {}
  }

  $report = $primary_report + $replica_report
  out::message("Node checks: ${stdlib::to_json_pretty($report)}")
  return $report
}

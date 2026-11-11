#!/bin/bash
# Output stays plain text (this task does not source task_helper.sh); Bolt
# wraps it in _output itself. The helper below only defines functions.
source "$(dirname $0)/../../peadm/files/failure_report.sh"

# The report size can be set with the report_log_lines and report_unit_lines
# task parameters (or by exporting the PEADM_REPORT_* variables directly).
[ -n "$PT_report_log_lines" ] && export PEADM_REPORT_LOG_LINES="$PT_report_log_lines"
[ -n "$PT_report_unit_lines" ] && export PEADM_REPORT_UNIT_LINES="$PT_report_unit_lines"

# Try and ensure locale is correctly configured
[ -z "${LANG}" ] && export LANG=$(localectl status | sed -n 's/.* LANG=\(.*\)/\1/p')

if [ ! -f "${PT_installer_dir}/puppet-enterprise-installer" ]; then
	echo "Puppet Enterprise installer not found at ${PT_installer_dir}/puppet-enterprise-installer"
	exit 1
fi

/bin/bash "${PT_installer_dir}/puppet-enterprise-installer" -y -c "$PT_peconf"

# The exit code of the installer script will be the exit code of the task
exit_code=$?

if [ "$PT_puppet_service_ensure" = "stopped" ]; then
	systemctl stop puppet.service
fi

# Explain a failed run: the redacted tail of the newest installer log and the
# state of any failed pe-* services (see files/failure_report.sh).
if [ "$exit_code" -ne 0 ]; then
	installer_log_dir="${PE_INSTALLER_LOG_DIR:-/var/log/puppetlabs/installer}"
	latest_log=$(ls -t "$installer_log_dir"/*.install.log 2>/dev/null | head -n 1)
	peadm_failure_report "$exit_code" "Puppet Enterprise installer" "$latest_log"
fi

exit $exit_code

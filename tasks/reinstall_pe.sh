#!/bin/bash
# This task reinstalls PE and needs to run as root.
#
# The shebang carries no -e: Bolt honours the shebang and a spec runs the file
# as `/bin/bash <file>`, so errexit is set explicitly to behave the same in both.
set -e

# Output stays plain text (this task does not source task_helper.sh); Bolt
# wraps it in _output itself. The helper below only defines functions.
source "$(dirname $0)/../../peadm/files/failure_report.sh"

# The report size can be set with the report_log_lines and report_unit_lines
# task parameters (or by exporting the PEADM_REPORT_* variables directly).
[ -n "$PT_report_log_lines" ] && export PEADM_REPORT_LOG_LINES="$PT_report_log_lines"
[ -n "$PT_report_unit_lines" ] && export PEADM_REPORT_UNIT_LINES="$PT_report_unit_lines"

# Uninstall PE if installed. PEADM_PE_UNINSTALLER is a test seam; production
# always uses the default.
if [[ "$PT_uninstall" == true ]]; then
  "${PEADM_PE_UNINSTALLER:-/opt/puppetlabs/bin/puppet-enterprise-uninstaller}" -p -d -y || true
fi

# Download PE
INSTALLER="puppet-enterprise-${PT_version}-${PT_arch}"
curl -O "https://s3.amazonaws.com/pe-builds/released/${PT_version}/${INSTALLER}.tar.gz"
tar xf "${INSTALLER}.tar.gz"

# Install PE. We need to pass "y" through stdin since the flag -y requires pe.conf to be present.
# errexit is suspended around the installer so a failure can be explained
# before the task exits with the installer's own exit code.
cd $INSTALLER
set +e
echo 'y' | ./puppet-enterprise-installer
exit_code=$?
set -e

# Explain a failed run: the redacted tail of the newest installer log and the
# state of any failed pe-* services (see files/failure_report.sh).
if [ "$exit_code" -ne 0 ]; then
  installer_log_dir="${PE_INSTALLER_LOG_DIR:-/var/log/puppetlabs/installer}"
  latest_log=$(ls -t "$installer_log_dir"/*.install.log 2>/dev/null | head -n 1)
  peadm_failure_report "$exit_code" "Puppet Enterprise installer" "$latest_log"
  exit "$exit_code"
fi

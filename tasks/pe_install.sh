#!/bin/bash
source "$(dirname $0)/../../peadm/files/task_helper.sh"
source "$(dirname $0)/../../peadm/files/failure_report.sh"

# Try and ensure locale is correctly configured
[ -z "${LANG}" ] && export LANG=$(localectl status | sed -n 's/.* LANG=\(.*\)/\1/p')

# This stanza configures PuppetDB to quickly fail on start. This is desirable
# in situations where PuppetDB WILL fail, such as when PostgreSQL is not yet
# configured, and we don't want to let PuppetDB wait five minutes before
# giving up on it.
if [ "$PT_install_extra_large" = "true" ]; then
	mkdir /etc/systemd/system/pe-puppetdb.service.d
	cat > /etc/systemd/system/pe-puppetdb.service.d/10-shortcircuit.conf <<-EOF
		[Service]
		TimeoutStartSec=1
		TimeoutStopSec=1
		Restart=no
	EOF
	systemctl daemon-reload
fi

# On failure, print what a person would otherwise have to log in and look up:
# the redacted tail of the most recent installer log and the state of any
# failed pe-* services (see files/failure_report.sh). This goes to stdout so
# Bolt includes it in the task failure.
report_installer_failure() {
	local installer_log_dir="${PE_INSTALLER_LOG_DIR:-/var/log/puppetlabs/installer}"
	local latest_log
	latest_log=$(ls -t "$installer_log_dir"/*.install.log 2>/dev/null | head -n 1)
	peadm_failure_report "$1" "Puppet Enterprise installer" "$latest_log"
}

tgzdir=$(dirname "$PT_tarball")
pedir=$(tar -tf "$PT_tarball" | head -n 1 | xargs dirname)

if file "$PT_tarball" | grep -q gzip; then
  tar_options="-xzf"
else
  tar_options="-xf"
fi 

tar -C "$tgzdir" "$tar_options" "$PT_tarball"

if [ $? -ne 0 ]; then
	echo "Failed to extract Puppet Enterprise tarball"
	exit 1
fi

if [ ! -f "${tgzdir}/${pedir}/puppet-enterprise-installer" ]; then
	echo "Puppet Enterprise installer not found at ${tgzdir}/${pedir}/puppet-enterprise-installer"
	exit 1
fi

# Clean up the tarball
rm -f "$PT_tarball"

if [ ! -z "$PT_peconf" ]; then
	/bin/bash "${tgzdir}/${pedir}/puppet-enterprise-installer" -y -c "$PT_peconf"
else
	/bin/bash "${tgzdir}/${pedir}/puppet-enterprise-installer" -y
fi

# The exit code of the installer script will be the exit code of the task
exit_code=$?

if [ "$PT_install_extra_large" = "true" ]; then
	systemctl stop pe-puppetdb.service
	rm /etc/systemd/system/pe-puppetdb.service.d/10-shortcircuit.conf
	systemctl daemon-reload
fi

if [ "$PT_puppet_service_ensure" = "stopped" ]; then
	systemctl stop puppet.service
fi

# In an extra large install, the installer is known to exit with code 1, even
# on an otherwise successful install, because PuppetDB cannot start yet. The
# task should indicate successful completion even if the exit code is 1, as
# long as some basic "did it install?" health checks pass.
if [ "$PT_install_extra_large" = "true" ]; then
	for svc in pe-puppetserver pe-orchestration-services pe-console-services; do
		if ! systemctl is-active --quiet $svc.service; then
			report_installer_failure "$exit_code"
			exit $exit_code
		fi
	done
	exit 0
else
	[ "$exit_code" -ne 0 ] && report_installer_failure "$exit_code"
	# Exit with the installer script's exit code
	exit $exit_code
fi

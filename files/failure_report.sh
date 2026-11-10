#!/bin/bash
# Shared failure-report helpers for peadm shell tasks.
#
# Source this file from a task; it only defines functions. It sets no traps,
# redirects no file descriptors and has no top-level side effects, so it is
# safe for tasks that do not source task_helper.sh (task_helper.sh changes the
# output contract: JSON _output wrapping, fd 6/7 redirects, an EXIT trap and
# PT_ variable munging).
#
#   source "$(dirname $0)/../../peadm/files/failure_report.sh"
#   peadm_failure_report "$exit_code" "Puppet Enterprise installer" "$latest_log"
#
# Report sizes: PEADM_REPORT_LOG_LINES (default 40) lines of the log and
# PEADM_REPORT_UNIT_LINES (default 15) lines per failed unit. Tasks map their
# report_log_lines and report_unit_lines parameters onto these variables.
#
# Everything printed from a log or from service status goes through
# peadm_redact first, because Bolt prints task output unredacted.

# Filter stdin to stdout, hiding secrets: private key blocks, URL userinfo
# passwords, signed-URL query values, auth headers and password-like keys.
# Over-redaction (for example token_lifetime: 1y) is the accepted safe direction.
peadm_redact() {
	sed -E \
		-e '/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/,/-----END [A-Z0-9 ]*PRIVATE KEY-----/c\
[REDACTED PRIVATE KEY]' \
		-e 's#(://[^/@[:space:]:]+):[^/@[:space:]]+@#\1:[REDACTED]@#g' \
		-e 's/([?&;](X-Amz-Signature|X-Amz-Credential|X-Amz-Security-Token|Signature|sig|token|access_token|api[_-]?key|key)=)[^&[:space:]"'"'"']+/\1[REDACTED]/Ig' \
		-e 's/((Authorization|X-Authentication|Proxy-Authorization)[[:space:]]*:[[:space:]]*(Bearer |Basic |Token )?)[^[:space:]"]+/\1[REDACTED]/Ig' \
		-e 's/("?[A-Za-z0-9_:.-]*(password|passwd|passphrase|secret|token|api[_-]?key|private[_-]?key|credential)[A-Za-z0-9_:.-]*"?[[:space:]]*[=:][[:space:]]*)("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:],}]+)/\1[REDACTED]/Ig'
}

# Print the last LINES lines of FILE, redacted. The whole file is redacted
# before the tail so a private key whose BEGIN line falls outside the window
# cannot leak its body.
peadm_report_log_tail() {
	local file="$1"
	local lines="${2:-${PEADM_REPORT_LOG_LINES:-40}}"
	if [ -n "$file" ] && [ -s "$file" ]; then
		echo "--- Last ${lines} lines of ${file}"
		peadm_redact < "$file" | tail -n "$lines"
	else
		echo "--- No log found at ${file}"
	fi
}

# Print the redacted systemctl status of every failed pe-* unit.
peadm_report_failed_units() {
	local lines="${1:-${PEADM_REPORT_UNIT_LINES:-15}}"
	local unit
	for unit in $(systemctl list-units 'pe-*' --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}'); do
		echo "--- systemctl status ${unit}"
		systemctl status "$unit" --no-pager -l -n "$lines" 2>&1 | peadm_redact
	done
}

# Print the whole report: header, log tail and failed units.
peadm_failure_report() {
	local exit_code="$1"
	local title="$2"
	local file="$3"
	echo
	echo "=== ${title} failed with exit code ${exit_code} ==="
	peadm_report_log_tail "$file"
	peadm_report_failed_units
}

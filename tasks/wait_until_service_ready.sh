#!/bin/bash
# Wait until a PE service answers HTTP 200 on its status API, or give up after
# a deadline and explain why it was not ready.
#
# Parameters (environment): PT_service, PT_port, PT_timeout (seconds, default
# 60), PT_interval (seconds between attempts, default 3).
#
# Output stays plain text and this task does not source task_helper.sh, for the
# reason recorded in files/failure_report.sh.
#
# Seam for specs: PEADM_LOG_ROOT (default /var/log/puppetlabs) is where the
# service logs are read from for the timeout report.

source "$(dirname $0)/../../peadm/files/failure_report.sh"

timeout="${PT_timeout:-60}"
interval="${PT_interval:-3}"
log_root="${PEADM_LOG_ROOT:-/var/log/puppetlabs}"

# The values reach shell arithmetic below, so accept only positive integers
# and never evaluate them as anything else.
for name in timeout interval; do
	value="${!name}"
	if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
		echo "wait_until_service_ready: ${name} must be a positive whole number of seconds, got '${value}'" >&2
		exit 1
	fi
done

if [[ "$PT_service" == 'all' ]]; then
	path='/status/v1/simple'
else
	path="/status/v1/simple/${PT_service}"
fi
url="https://localhost:${PT_port}${path}"

case "$PT_service" in
	orchestrator-service) service_log="${log_root}/orchestration-services/orchestration-services.log" ;;
	*) service_log="${log_root}/puppetserver/puppetserver.log" ;;
esac

# Attempts come from the deadline, not the wall clock, so the loop ends even
# when sleep is stubbed in a spec: ceiling(timeout / interval).
attempts=$(( (timeout + interval - 1) / interval ))

body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT

curl_exit=0
http_code='000'
n=0
while [ "$n" -lt "$attempts" ]; do
	http_code=$(curl -ks --max-time 10 -o "$body_file" -w '%{http_code}' "$url")
	curl_exit=$?
	if [ "$curl_exit" -eq 0 ] && [ "$http_code" = '200' ]; then
		exit 0
	fi
	n=$((n + 1))
	if [ "$n" -lt "$attempts" ]; then
		sleep "$interval"
	fi
done

echo "Timed out after ${timeout}s waiting for ${PT_service} on ${url}"
echo "Last result: curl exit ${curl_exit}, HTTP ${http_code}"
if [ -s "$body_file" ]; then
	echo "--- Last response body"
	peadm_redact < "$body_file"
	echo
fi
peadm_report_failed_units
peadm_report_log_tail "$service_log"
exit 1

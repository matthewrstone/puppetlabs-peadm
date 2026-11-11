# A convenience function to help remember port numbers for services and handle
# running the wait_until_service_ready task
#
# @param service The service to wait for: all, ca, pe-master or orchestrator-service
# @param target The node to check
# @param timeout Seconds to keep waiting before the task fails with a report. Defaults to 60.
function peadm::wait_until_service_ready(
  String     $service,
  TargetSpec $target,
  Integer[1] $timeout = 60,
) {
  $port = case $service {
    'orchestrator-service': { '8143' }
    default: { '8140' }
  }
  run_task('peadm::wait_until_service_ready', $target,
    service => $service,
    port    => $port,
    timeout => $timeout,
  )
}

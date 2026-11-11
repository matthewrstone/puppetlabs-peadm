---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 06
subsystem: testing
tags: [bash, shell-tasks, readiness-wait, timeout, bolt-plans, rspec, change-ledger, fix-log]
status: complete

requires: ["01-05"]
provides:
  - tasks/wait_until_service_ready.sh honours timeout and interval (defaults 60 and 3 s) and, on expiry, prints the service, URL, last curl exit and HTTP code, redacted response body, failed pe-* units and the redacted service log tail before exiting 1
  - peadm::wait_until_service_ready takes Integer[1] $timeout = 60
  - service_ready_timeout (Integer[1], default 60) on peadm::add_replica, peadm::upgrade and peadm::convert, reaching every wait_until_service_ready call in those plans
  - The fixed 120 s wait_until_available reconnect waits in upgrade (2) and convert (1) become max(120, $service_ready_timeout)
  - spec/unit/shell_tasks/wait_until_service_ready_spec.rb (14 examples) plus forwarding and default examples in the add_replica, upgrade and convert plan specs
  - Ledger rows P1-08 and P1-09, fix-log entry P1-08
affects: [01-09, 01-10, 01-11, 01-13, 01-14]

actuals:
  tokens: 7300
  tasks: 2
  commits: 2
plan_head_before: 7d49f06e337270648511154bdf3266ffa3b7fdc8
plan_head_after: 5bb9f1cbf7cc78b22637394f9e25ec5f90d32360
commits: 2

tech-stack:
  added: []
  patterns:
    - "Attempt count is ceiling(timeout / interval), not wall-clock SECONDS, so a spec with a stubbed sleep still terminates"
    - "Naming for later plans: task params timeout/interval, function argument $timeout, plan parameter service_ready_timeout"
    - "BoltSpec with_params is strict equality, so forwarding examples assert the whole hash (service, port, timeout); wait_time on wait_until_available is checked statically because BoltSpec does not expose it"

key-files:
  created:
    - spec/unit/shell_tasks/wait_until_service_ready_spec.rb
  modified:
    - tasks/wait_until_service_ready.sh
    - tasks/wait_until_service_ready.json
    - functions/wait_until_service_ready.pp
    - plans/add_replica.pp
    - plans/upgrade.pp
    - plans/convert.pp
    - spec/plans/add_replica_spec.rb
    - spec/plans/upgrade_spec.rb
    - spec/plans/convert_spec.rb
    - REFERENCE.md
    - documentation/change-ledger.md
    - documentation/fix-log.md

key-decisions:
  - "Task, function and plan parameter names are timeout/interval, $timeout and service_ready_timeout; plans 01-10 (install) and 01-11 (restore) reuse them"
  - "No ca readiness wait is added to add_replica: the /status/v1/simple/ca endpoint is unconfirmed on a real primary, so plan 01-14 wires it only after plan 01-13 probes it. The ca wait already takes the deadline at task and function level"
  - "wait_until_available uses max(120, service_ready_timeout), so the default keeps today's 120 s and a larger operator deadline extends the PCP reconnect wait too"
  - "The wait task stays plain text and does not source task_helper.sh (same reason as ledger P1-05)"

patterns-established:
  - "A task that polls ends its report with the redacted tail of the service log chosen by the service parameter, behind a PEADM_LOG_ROOT seam"

requirements-completed: [FND-07, FND-01, TRC-01, TRC-02]

coverage:
  - id: D1
    description: "wait_until_service_ready takes timeout/interval and a timed-out wait reports the service, URL, last HTTP result, redacted body, failed units and redacted log tail"
    requirement: "FND-07"
    verification:
      - kind: unit
        ref: "bundle exec rspec spec/unit/shell_tasks/wait_until_service_ready_spec.rb"
        status: pass
    human_judgment: false
  - id: D2
    description: "service_ready_timeout reaches the pe-master wait in add_replica and every wait in upgrade and convert; wait_until_available keeps its 120 s floor"
    requirement: "FND-07"
    verification:
      - kind: unit
        ref: "bundle exec rspec spec/plans/add_replica_spec.rb spec/plans/upgrade_spec.rb spec/plans/convert_spec.rb"
        status: pass
    human_judgment: false
  - id: D3
    description: "Behaviour on a real slow primary or replica (the deadline actually lets a slow node finish, and the report reads usefully)"
    verification: []
    human_judgment: true
    rationale: "Only specs ran; no cluster run. Needs an acceptance run on a provisioned cluster (plan 01-13/01-14)."

duration: 35min
completed: 2026-11-10
---

# Phase 1 Plan 06: Overridable readiness deadline and timeout report Summary

**`peadm::wait_until_service_ready` now takes a deadline end to end (task `timeout`/`interval`, function `$timeout`, plan `service_ready_timeout` on add_replica, upgrade and convert) and a timed-out wait prints what it awaited, the last HTTP result, failed pe-* units and the redacted service log tail.**

## Performance

- **Duration:** about 35 min (start time not captured by the executor, estimated)
- **Tasks:** 2 (1 tracer, 1 auto)
- **Files modified:** 13 (1 created)

## Accomplishments

- The wait task polls ceiling(timeout / interval) times (default 20 x 3 s, as before), treats HTTP 200 as ready, and on expiry prints `Timed out after <n>s waiting for <service> on <url>`, `Last result: curl exit <n>, HTTP <code>`, the redacted body, failed units and the redacted log tail (puppetserver.log for all, ca and pe-master; orchestration-services.log for orchestrator-service), then exits 1. Non-numeric `PT_timeout` or `PT_interval` is rejected before any arithmetic.
- add_replica passes `service_ready_timeout` to its pe-master wait on the replica, between provision and enable. No `ca` wait was added (W5).
- upgrade (both orchestrator waits) and convert (three pe-master waits, one orchestrator wait) pass the deadline, and the three `wait_until_available` calls use `max(120, $service_ready_timeout)`.
- Specs: the new task spec has 14 examples, 11 of which fail on the unmodified script. Plan specs assert the exact `with_params` hash, the provision/wait/enable order, defaults of 60, and a static check on `wait_time`.
- REFERENCE.md regenerated with `rake strings:generate:reference`; its diff covers only the new parameters and the function description. `rake strings:validate:reference` exits 0.

## Task Commits

1. **Task 1 (tracer): deadline from add_replica through the function to the task, with a timeout report** - `a2b3575` (P1-08)
2. **Task 2: service_ready_timeout on upgrade and convert, including wait_until_available** - `5bb9f1c` (P1-09)

The tracer gate ran in end-of-phase mode with an automated-only `<verify>`; it passed end to end, then expansion proceeded.

## Verification

- `bundle exec rake parallel_spec`: 644 examples, 0 failures, 6 pending (plus 187 more examples in the puppet class and function run, 0 failures).
- `bundle exec rake validate lint check rubocop`: exit 0, 119 files, no RuboCop offenses. puppet-lint warnings in `plans/upgrade.pp`, `plans/convert.pp` and `plans/add_replica.pp` are the same count as at HEAD before the plan (23 for upgrade plus convert).
- Plan-level grep: two-argument `wait_until_service_ready` calls remain only in `plans/subplans/install.pp` (two, plan 01-10), `plans/subplans/configure.pp` (plan 01-10) and `plans/restore.pp` (plan 01-11).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Added `--max-time 10` to the curl call in the wait task**
- **Found during:** Task 1
- **Issue:** a curl that hangs on an unresponsive service would hold the task past its deadline, defeating the new timeout.
- **Fix:** `curl -ks --max-time 10 -o <file> -w '%{http_code}'`. The attempt count still comes from timeout / interval.
- **Files modified:** `tasks/wait_until_service_ready.sh`
- **Commit:** a2b3575

**2. [Rule 3 - Blocking] Fixture modules were missing, so plan specs could not find the plans**
- **Found during:** Task 1
- **Issue:** `spec/fixtures/modules` was empty and `peadm::add_replica` was "not found" in BoltSpec.
- **Fix:** ran `bundle exec rake spec_prep` (git-ignored output, nothing committed).

**3. Function documentation kept.** I first replaced the function's existing description with a new `@summary`, then restored the original text so the REFERENCE.md diff only adds what the plan needs. No behavioural effect.

**Total deviations:** 2 auto-fixed (1 missing functionality, 1 blocking environment), 1 self-correction. **Impact:** none on scope.

## Issues Encountered

None open. Not run on a cluster: the deadline and the report were exercised only through stubbed `curl`, `sleep` and `systemctl`.

## Known Stubs

None.

## Threat Flags

None. T-01-10 (PT_timeout/PT_interval into shell arithmetic) is mitigated by `Integer[1]` types and a `^[1-9][0-9]*$` check with a spec that plants `5; touch pwned`. T-01-11 (secrets in the report) is mitigated by `peadm_redact` on the body and the log, with a planted `password=FAKE-SECRET-pw` spec.

## Next Phase Readiness

Plan 01-10 (install, configure) and 01-11 (restore) add `service_ready_timeout` to their waits using the same naming. Plan 01-13 probes `/status/v1/simple/ca` on 2025.12.1 and 2026.0.1; plan 01-14 adds the add_replica `ca` wait only if it answered. Ledger Commit cells for P1-08 and P1-09 are filled by plan 01-14 from the `Ledger-ID` trailers (`a2b3575`, `5bb9f1c`).

## Self-Check: PASSED

- Created file present: `spec/unit/shell_tasks/wait_until_service_ready_spec.rb`.
- Commits `a2b3575` and `5bb9f1c` are ancestors of HEAD.

---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 05
subsystem: testing
tags: [bash, shell-tasks, code-manager, failure-report, redaction, rspec, bolt, change-ledger, fix-log]
status: complete

requires: ["01-04"]
provides:
  - peadm::code_manager fails with the method, URL path, curl exit, HTTP code, redacted response body and failed pe-* units when a file-sync or environment-cache API call fails
  - peadm::subplans::install waits for pe-master before its file-sync commit
  - peadm::reinstall_pe prints the redacted installer log tail and failed pe-* units and keeps the installer's exit code
  - spec/unit/shell_tasks/code_manager_spec.rb (18 examples) and reinstall_pe_spec.rb (13 examples)
  - Ledger rows P1-07 (new) and P1-06 (extended), fix-log entries P1-07 (new) and P1-05 (extended)
affects: [01-06, 01-10, 01-13, 01-14]

actuals:
  tokens: 14000
  tasks: 3
  commits: 3
plan_head_before: 3871043d9c78f5de012520fea986347425cf633d
plan_head_after: fcf221ad2d4965fdff05766f6e8350eafa6a7e20
commits: 3

tech-stack:
  added: []
  patterns:
    - "Env seams (PEADM_PUPPET_BIN, PEADM_PE_UNINSTALLER) let a spec point a task at stubs for absolute-path binaries"
    - "curl -o tempfile -w '%{http_code}' so a wrapper can fail on HTTP status and print the body through peadm_redact"
    - "Explicit set -e plus set +e around the one command whose exit code is reported, instead of a shebang -e"

key-files:
  created:
    - spec/unit/shell_tasks/code_manager_spec.rb
    - spec/unit/shell_tasks/reinstall_pe_spec.rb
  modified:
    - tasks/code_manager.sh
    - tasks/code_manager.json
    - tasks/reinstall_pe.sh
    - tasks/reinstall_pe.json
    - plans/subplans/install.pp
    - spec/plans/subplans/install_spec.rb
    - REFERENCE.md
    - documentation/change-ledger.md
    - documentation/fix-log.md

key-decisions:
  - "code_manager keeps plain-text output and does not source task_helper.sh (same reason as ledger P1-05)"
  - "A failed file-sync commit is no longer masked by the force-sync that follows it; commit returns 1 on the first failure"
  - "Any 2xx is success; specs use 200 for commit and force-sync and 204 for the cache flush"
  - "Added a PEADM_PE_UNINSTALLER seam to reinstall_pe (not in the plan) so the 'uninstall=false never calls the uninstaller' behaviour can be observed"

requirements-completed: [FND-01, FND-05, TRC-01, TRC-02]

coverage:
  - id: D1
    description: "code_manager fails on a curl error or non-2xx HTTP status instead of reporting success, naming method, path, curl exit and HTTP code"
    requirement: "FND-01"
    verification:
      - kind: unit
        ref: "bundle exec rspec spec/unit/shell_tasks/code_manager_spec.rb (18 examples, 0 failures; 8 fail on the unmodified script)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A token or password planted in an API response body, or in the reinstall_pe installer log, never appears in task output"
    requirement: "FND-05"
    verification:
      - kind: unit
        ref: "code_manager_spec.rb 'never prints the planted secrets'; reinstall_pe_spec.rb 'never prints planted secrets'"
        status: pass
    human_judgment: false
  - id: D3
    description: "peadm::subplans::install waits for pe-master before the file-sync commit"
    requirement: "FND-01"
    verification:
      - kind: unit
        ref: "spec/plans/subplans/install_spec.rb 'waits for pe-master before the file-sync commit' (fails with the new wait removed, as does the adjusted timeout example); awk order check on plans/subplans/install.pp"
        status: pass
    human_judgment: false
  - id: D4
    description: "reinstall_pe prints the failure header with the exit code, the log tail and failed units, exits with the installer's code, prints nothing on success, and runs no installer after a failed download"
    requirement: "FND-01"
    verification:
      - kind: unit
        ref: "bundle exec rspec spec/unit/shell_tasks/reinstall_pe_spec.rb (13 examples, 0 failures; 5 fail on the old script)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Ledger P1-06 (extended) and P1-07, fix-log P1-05 (extended) and P1-07"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "grep '^| P1-07 |' and 'reinstall_pe' in documentation/change-ledger.md; P1-07 heading in documentation/fix-log.md"
        status: pass
    human_judgment: false
  - id: D6
    description: "The code_manager report and the extra pe-master wait behave well on a real cluster install with DR"
    requirement: "FND-01"
    verification: []
    human_judgment: true
    rationale: "Specs use a stub curl and a stubbed plan task; the acceptance slice (plan 01-13) is where it meets a real puppetserver"

duration: 11min
completed: 2026-11-10
---

# Phase 1 Plan 05: code_manager failure propagation and reinstall_pe report Summary

**`peadm::code_manager` now fails (with method, path, curl exit, HTTP code and a redacted body) when a file-sync or cache API call fails instead of reporting success, the install subplan waits for pe-master before its commit, and `peadm::reinstall_pe` prints the shared redacted failure report.**

## Performance

- **Duration:** about 11 min
- **Tasks:** 3 of 3 (one tracer, two auto)
- **Files modified:** 11 (2 created, 9 modified), 3 commits

## Accomplishments

- Task 1 (tracer): the code_manager spec was written first and failed 8 of 18 examples on the unmodified script (HTTP 500 exited 0). `curl_wrapper` now reads the HTTP code through curl's `-w`, treats a curl error or non-2xx as failure and prints the report through `peadm_redact` and `peadm_report_failed_units`. `commit` returns on a failed commit rather than letting force-sync mask it, and `main` propagates the action's status. Task JSON ships the helper. Ledger P1-07, fix-log P1-07. Tracer verified end to end before expansion.
- Task 2: `peadm::wait_until_service_ready('pe-master', $primary_target)` now precedes the `file-sync commit` in the install subplan. Ordering example added; the existing post-install timeout example now fails only the second wait so its intent is unchanged.
- Task 3: `reinstall_pe.sh` sources the helper, uses `#!/bin/bash` plus an explicit `set -e`, suspends errexit around the installer, reports and exits with the installer's code. JSON ships the helper and gains `report_log_lines` and `report_unit_lines`. REFERENCE.md regenerated with `rake strings:generate:reference`. Ledger P1-06 and fix-log P1-05 extended.

## Task Commits

1. Task 1 (tracer): `eb324a2` (P1-07) Fail peadm::code_manager when a file-sync or cache API call fails, with the redacted response
2. Task 2: `4d47baf` (P1-07) Wait for pe-master before the install subplan's file-sync commit
3. Task 3: `fcf221a` (P1-06) Report the installer log tail and failed units when reinstall_pe fails

## Verification

- `bundle exec rspec spec/unit/shell_tasks/code_manager_spec.rb`: 18 examples, 0 failures (8 failed before the fix)
- `bundle exec rspec spec/plans/subplans/install_spec.rb`: 32 examples, 0 failures; with the new wait removed, 2 fail (the ordering example and the adjusted timeout example)
- `bundle exec rspec spec/unit/shell_tasks/reinstall_pe_spec.rb`: 13 examples, 0 failures (5 failed on the old script)
- `bundle exec rake parallel_spec`: 623 examples, 0 failures, 6 pending (final block; 167 + 159 + 623 across lanes)
- `bundle exec rake validate lint check rubocop`: rc 0
- `bundle exec rake strings:validate:reference`: rc 0

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added a `PEADM_PE_UNINSTALLER` seam to reinstall_pe**
- **Found during:** Task 3
- **Issue:** the plan requires a spec that `uninstall=false` never calls the uninstaller, but the task calls it through the absolute path `/opt/puppetlabs/bin/puppet-enterprise-uninstaller`, which a spec cannot observe or stub.
- **Fix:** `"${PEADM_PE_UNINSTALLER:-/opt/puppetlabs/bin/puppet-enterprise-uninstaller}"`, default unchanged; documented in ledger P1-06 as a test-only seam.
- **Files modified:** `tasks/reinstall_pe.sh`, `documentation/change-ledger.md`
- **Commit:** `fcf221a`

**2. [Rule 3 - Blocking] Ran `rake spec_prep` to restore empty fixtures**
- **Found during:** Task 2
- **Issue:** `spec/fixtures/modules/` was empty, so every plan spec failed with "Could not find a plan named ...". Not caused by the change.
- **Fix:** `bundle exec rake spec_prep`; fixtures are untracked, no repository change.

**Total deviations:** 2 (one test seam, one environment restore). **Impact:** none on scope.

## Issues Encountered

- The fix-log "Reproduce (before)" recipes were not run as a worktree walk-through; what was run is the equivalent: the new spec against the unmodified script (8 of 18 failures for code_manager, 5 of 13 for reinstall_pe). Both entries say "spec shows it, not run on a cluster".
- `puppet-lint` run directly on `plans/subplans/install.pp` prints strict_indent warnings on lines unrelated to this change; the rake lint task disables that check and exits 0.

## Known Stubs

None. The stub curl, fake installer and stub systemctl live only inside specs.

## Threat Flags

None. The new surface matches the register: T-01-08 and T-01-38 are mitigated by sending the response body and installer log through `peadm_redact` (planted-secret specs), T-01-35 by the pe-master wait before the commit and a failure message naming method, path, curl exit and HTTP code.

## Next Phase Readiness

- Plan 01-10 can pass the operator's deadline to the new pe-master wait call in the install subplan.
- Plan 01-14 fills the ledger Commit column by trailer: P1-07 is in `eb324a2` and `4d47baf`, P1-06 (reinstall_pe part) is in `fcf221a` alongside `a149fb0`.

## Self-Check: PASSED

- Files exist: spec/unit/shell_tasks/code_manager_spec.rb, spec/unit/shell_tasks/reinstall_pe_spec.rb
- Commits eb324a2, 4d47baf and fcf221a are ancestors of HEAD

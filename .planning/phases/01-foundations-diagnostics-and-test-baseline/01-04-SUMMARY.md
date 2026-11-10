---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 04
subsystem: testing
tags: [bash, shell-tasks, redaction, failure-report, rspec, bolt, change-ledger, fix-log]
status: complete

requires: ["01-03"]
provides:
  - ShellTaskHarness (spec/support/shell_task_harness.rb) for running shell tasks under rake spec with stub executables on PATH
  - files/failure_report.sh with peadm_redact, peadm_report_log_tail, peadm_report_failed_units, peadm_failure_report
  - pe_install and pe_reinstall print a redacted log tail, failed pe-* units and the installer exit code on failure
  - report_log_lines and report_unit_lines task parameters (defaults 40 and 15) on both installer tasks
  - Four shell-task spec files (60 examples in a directory run) that replace the hand-run P0-4 and P0-6 checks
  - Ledger rows P1-04, P1-05, P1-06 and fix-log entry P1-05 (P0-4 and P0-6 entries now say "spec shows it")
affects: [01-05, 01-06, 01-13, 01-14]

actuals:
  tokens: 14000
  tasks: 3
  commits: 3
plan_head_before: f377862808d32529ae98206a612f6c343ef0fff3
plan_head_after: a149fb0e64538c5121f68b07bd41b7f4926ec978
commits: 3

tech-stack:
  added: []
  patterns:
    - "Functions-only shell helper sourced as \"$(dirname $0)/../../peadm/files/<file>\" and shipped through the task JSON files array"
    - "Redact the whole log, then tail, so a private key split by the tail window cannot leak"
    - "Env seams (PE_INSTALLER_LOG_DIR, PE_SYSTEMD_DROPIN_DIR) let specs point a task at a temp tree"

key-files:
  created:
    - spec/support/shell_task_harness.rb
    - files/failure_report.sh
    - spec/unit/shell_tasks/pe_install_spec.rb
    - spec/unit/shell_tasks/pe_reinstall_spec.rb
    - spec/unit/shell_tasks/failure_report_spec.rb
    - spec/unit/shell_tasks/verify_tarball_spec.rb
  modified:
    - spec/spec_helper_local.rb
    - tasks/pe_install.sh
    - tasks/pe_install.json
    - tasks/pe_reinstall.sh
    - tasks/pe_reinstall.json
    - REFERENCE.md
    - documentation/change-ledger.md
    - documentation/fix-log.md

key-decisions:
  - "Harness uses the real tar with a real tarball holding a fake installer, and stubs systemctl (user-approved deviation from D-10, recorded in ledger row P1-04)"
  - "files/failure_report.sh is a functions-only sibling of task_helper.sh because several tasks cannot source task_helper.sh without changing their output contract"
  - "Over-redaction of the rest of a signed-URL query string (the generic token/credential rule eats trailing &params) is kept as the accepted safe direction; the spec asserts only that the host, path and secret handling are right"

patterns-established:
  - "Shell-task specs: ShellTaskHarness.new, stub('systemctl', body), run('<task>.sh', params, env), assert on status and JSON _output (or stdout for plain-text tasks)"

requirements-completed: [TST-05, FND-01, FND-05, TRC-01, TRC-02]

coverage:
  - id: D1
    description: "Maintainer can run a shell task under rake spec with stub executables and PT_* parameters, with no PE installer"
    requirement: "TST-05"
    verification:
      - kind: unit
        ref: "bundle exec rspec spec/unit/shell_tasks/ (60 examples, 0 failures across the four files at the end of the plan)"
        status: pass
    human_judgment: false
  - id: D2
    description: "pe_install and pe_reinstall failures show the redacted log tail, every failed pe-* unit and the installer exit code, and exit with that code"
    requirement: "FND-01"
    verification:
      - kind: unit
        ref: "spec/unit/shell_tasks/pe_install_spec.rb, spec/unit/shell_tasks/pe_reinstall_spec.rb"
        status: pass
    human_judgment: false
  - id: D3
    description: "No planted secret appears in the report, including a private key whose BEGIN line is outside the tail window"
    requirement: "FND-05"
    verification:
      - kind: unit
        ref: "spec/unit/shell_tasks/failure_report_spec.rb (every redaction rule, BEGIN line 50 / END line 70 / tail 40), pe_install_spec.rb and pe_reinstall_spec.rb (never prints planted secrets). Mutation check: replacing the redact-then-tail with a plain cat makes 2 pe_install examples fail"
        status: pass
    human_judgment: false
  - id: D4
    description: "Report size is overridable with report_log_lines / report_unit_lines (defaults 40 and 15)"
    requirement: "FND-01"
    verification:
      - kind: unit
        ref: "pe_install_spec.rb 'when the report size is overridden', pe_reinstall_spec.rb 'when report_log_lines is set', failure_report_spec.rb"
        status: pass
    human_judgment: false
  - id: D5
    description: "Hand-run P0-4 (verify_tarball) and P0-6 (pe_install report) checks are now specs"
    requirement: "TST-05"
    verification:
      - kind: unit
        ref: "spec/unit/shell_tasks/verify_tarball_spec.rb, spec/unit/shell_tasks/pe_install_spec.rb"
        status: pass
    human_judgment: false
  - id: D6
    description: "Ledger rows P1-04 to P1-06 and the fix-log entries"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "grep for '^| P1-04 |', '^| P1-05 |', '^| P1-06 |' in documentation/change-ledger.md; '^## Phase 1' and verify_tarball_spec.rb in documentation/fix-log.md"
        status: pass
    human_judgment: false
  - id: D7
    description: "The report is useful on a real failed PE installer run on a cluster"
    requirement: "FND-01"
    verification: []
    human_judgment: true
    rationale: "Specs use a fake installer and a stub systemctl; the acceptance slice (plan 01-13) is where it meets a real failure"

duration: 25min
completed: 2026-11-10
---

# Phase 1 Plan 04: Shell-task harness and redacting installer failure report Summary

**A stub-PATH shell-task harness runs under `rake spec`, and `pe_install` and `pe_reinstall` now print a redacted log tail, every failed pe-* unit and the installer exit code through one shared `files/failure_report.sh`.**

## Performance

- **Duration:** about 25 min (start time was not captured at spawn; estimated)
- **Tasks:** 3 of 3 (one tracer, two auto)
- **Files modified:** 14 (6 created, 8 modified)

## Accomplishments

- Task 1 (tracer): `ShellTaskHarness`, `files/failure_report.sh` (redaction filter verbatim from the plan), `pe_install` moved onto the helper and shipping it in its JSON, planted-secret spec, ledger rows P1-04 and P1-05, fix-log entry P1-05. Tracer re-verified end to end before expansion.
- Task 2: `failure_report_spec` (30 examples: RSA/EC/PKCS8/ENCRYPTED keys, certificate untouched, URL userinfo, seven signed-URL params, auth headers, five key=value forms, ordinary line, BEGIN-outside-window, size overrides, failed units), `PE_SYSTEMD_DROPIN_DIR` seam and the extra-large branch specced (exit 0 on installer exit 1 with services up, drop-in written and removed, two daemon-reloads, inactive service reports and exits with the installer code), `verify_tarball_spec` for the five P0-4 archive cases, `report_log_lines` and `report_unit_lines` params on `pe_install`, REFERENCE.md regenerated, P0-4/P0-6 ledger and fix-log entries moved from "run by hand" to "spec shows it".
- Task 3: `pe_reinstall` sources the helper, keeps plain-text output and its exit code, stops Puppet before reporting, ships the helper and the two size parameters. 11 examples. Ledger row P1-06 and fix-log P1-05 extended.

## Task Commits

1. Task 1 (tracer): `50ea224` (P1-05) Redact secrets in the pe_install failure report via a shared helper, with a stub-PATH shell-task harness
2. Task 2: `f746c9b` (P1-04) Turn the hand-run P0-4 and P0-6 shell checks into harness specs and cover every redaction rule
3. Task 3: `a149fb0` (P1-06) Report the installer log tail and failed units when pe_reinstall fails

## Verification

- `bundle exec rspec spec/unit/shell_tasks/`: 60 examples, 0 failures (four files; the full suite runs these in `rake parallel_spec`)
- `bundle exec rake strings:validate:reference`: rc 0
- `bundle exec rake parallel_spec`: 593 examples, 0 failures, 6 pending (harness specs run inside `rake spec`, D-10)
- `bundle exec rake validate lint check rubocop`: rc 0, 116 files, no offenses
- Mutation check: replacing `peadm_redact < "$file" | tail` with `cat "$file" | tail` fails 2 pe_install examples; restored afterwards

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Spec expectation] Signed-URL query examples do not keep trailing params**
- **Found during:** Task 2
- **Issue:** the first draft asserted `&b=2` survives after `token=`, `access_token=`, `api_key=`, `X-Amz-Credential=` and `X-Amz-Security-Token=`. The generic password-like-key rule runs after the query rule, matches the already redacted `token=[REDACTED]&b=2` and swallows the rest of the line. No secret leaks; it is over-redaction.
- **Fix:** kept the rule as is (the plan says over-redaction is the accepted safe direction, RESEARCH Pitfall 8, and not to loosen patterns). The spec asserts the secret is gone and the URL host and path are kept, with a comment explaining why.
- **Files modified:** `spec/unit/shell_tasks/failure_report_spec.rb`
- **Commit:** `f746c9b`

**2. [Naming] Wrapper function renamed**
- **Found during:** Task 1
- **Issue:** the plan's verify says the string `report_install_failure` must be gone from `pe_install.sh`, while both call sites still need the log-file lookup. A small wrapper keeps that lookup in one place.
- **Fix:** wrapper is `report_installer_failure` (calls `peadm_failure_report`), so the old inline function is gone and the check passes.
- **Files modified:** `tasks/pe_install.sh`
- **Commit:** `50ea224`

**Total deviations:** 2 (one spec expectation adjusted to the documented safe direction, one naming choice). **Impact:** none on behaviour or scope.

## Issues Encountered

- The "Reproduce (before)" steps in the new fix-log entry and the updated P0-6 entry describe running the new specs on the parent commit with the specs copied in. That recipe was not run in this plan; only the mutation check above was. The entries' Status says "spec shows it" and "Not run against a real installer failure".
- RuboCop prints an "unsupported parameters" configuration warning before its results. It predates this plan and does not affect the exit code.

## Known Stubs

None. All fake installers and stub `systemctl` scripts live only inside specs.

## Threat Flags

None. The new surface is the failure report itself and matches register items T-01-04 to T-01-07: whole-log redaction before tail, a dedicated BEGIN-outside-window spec, unit status piped through `peadm_redact`, all expansions quoted, no eval, helper is functions-only, report sizes come from `Integer[1]`-typed task parameters.

## Next Phase Readiness

- Plans 01-05 (`code_manager`) and 01-06 (`wait_until_service_ready`) can source `files/failure_report.sh` and reuse the harness.
- Plan 01-14 fills the ledger Commit column by matching the `Ledger-ID` trailers: P1-04 and P1-05 are in `50ea224` and `f746c9b`, P1-06 is in `a149fb0`.

## Self-Check: PASSED

- Files exist: spec/support/shell_task_harness.rb, files/failure_report.sh, spec/unit/shell_tasks/{pe_install,pe_reinstall,failure_report,verify_tarball}_spec.rb
- Commits 50ea224, f746c9b and a149fb0 are ancestors of HEAD

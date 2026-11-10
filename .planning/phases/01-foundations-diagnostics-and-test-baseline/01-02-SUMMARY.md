---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 02
subsystem: testing
tags: [ruby, ci, github-actions, change-ledger]
status: complete

requires: ["01-01"]
provides:
  - Ruby 3.3 pin and step name in all 13 remaining acceptance workflows (25 of 25 pins total)
  - Change ledger row P1-01 Files cell complete
affects: [01-03, 01-13, 01-14]

actuals:
  tokens: 5000
  tasks: 1
  commits: 1
plan_head_before: d4e1fa2a1158387831eadff73628cb8133664af9
plan_head_after: f59326e08de65a1c2f387318f3c609e62cbadd62
commits: 1

tech-stack:
  added: []
  patterns:
    - "Sweep version pins with an anchored sed so unrelated '3.1' text (provision >= v3.1.0 comments) is untouched"

key-files:
  created: []
  modified:
    - .github/workflows/test-install-latest-dev.yaml
    - .github/workflows/test-install-latest-xlarge-dev-nightly.yaml
    - .github/workflows/test-install-matrix.yaml
    - .github/workflows/test-install-rhel-9.yaml
    - .github/workflows/test-legacy-compilers.yaml
    - .github/workflows/test-legacy-upgrade.yaml
    - .github/workflows/test-migration.yaml
    - .github/workflows/test-replace-failed-postgresql.yaml
    - .github/workflows/test-upgrade.yaml
    - .github/workflows/test-upgrade-latest-dev.yaml
    - .github/workflows/test-upgrade-latest-xlarge-dev-nightly.yaml
    - .github/workflows/test-upgrade-matrix.yaml
    - .github/workflows/test-upgrade-pg-major-ha-nightly.yaml
    - documentation/change-ledger.md

key-decisions:
  - "Only `ruby-version: '3.1'` and `Activate Ruby 3.1` were rewritten; the `provision >= v3.1.0` comments in six workflows are about the provision module and were deliberately left alone"

requirements-completed: [TST-01, TRC-01]

coverage:
  - id: D1
    description: "All 25 workflow ruby-version pins and step names on 3.3, none on 3.1"
    requirement: "TST-01"
    verification:
      - kind: integration
        ref: "Task 1 verify: 25 pins of '3.3', no '3.1' pins or step names, all workflows parse as YAML, ruby spec/acceptance/scenarios.rb --validate exits 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "Ledger row P1-01 lists the 13 workflows and records the 25 of 25 sweep"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "git diff of documentation/change-ledger.md row P1-01"
        status: pass
    human_judgment: false
  - id: D3
    description: "Acceptance workflows run on Ruby 3.3 with the current gem set"
    requirement: "TST-01"
    verification: []
    human_judgment: true
    rationale: "Acceptance workflows are dispatched on demand against real clusters; the first run confirms it (threat T-01-34, accepted)"
---

# Phase 1 Plan 02: Ruby 3.3 in the remaining workflows Summary

**Finished the Ruby 3.3 floor sweep: 13 more acceptance workflows moved from 3.1 to 3.3, so 25 of 25 pins and step names now say 3.3 ahead of the puppetlabs_spec_helper 9 bump in plan 01-03.**

## Accomplishments

- Rewrote `ruby-version: '3.1'` to `'3.3'` and `Activate Ruby 3.1` to `Activate Ruby 3.3` in the install, legacy, migration, replace-postgresql and upgrade workflows (one pin and one step name per file).
- `grep -rh ruby-version .github/workflows` now shows 25 pins of '3.3', one of '4.0' and the matrix-driven pin.
- Ledger row P1-01 Files cell lists the 13 files and notes the sweep is complete (25 of 25 pins, 23 workflow files).

## Task Commits

1. Task 1 (tracer): `f59326e` - 13 workflows plus ledger row P1-01 (`Ledger-ID: P1-01` trailer)

Tracer gate: auto mode off, human_verify_mode end-of-phase and the verify is automated only, so the verify was re-run end-to-end after the commit state (identical tree) and passed; no checkpoint.

## Deviations from Plan

None - plan executed exactly as written.

## Verification

- 25 pins of '3.3'; no `ruby-version: '3.1'`; no `Activate Ruby 3.1`.
- Every `.github/workflows/*.{yml,yaml}` parses with `YAML.safe_load_file`.
- `ruby spec/acceptance/scenarios.rb --validate` exits 0.
- Ruby 3.3 behavior on real acceptance runs is unproven until the workflows are dispatched.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- Commit `f59326e` is an ancestor of HEAD.
- No `3.1` Ruby pin remains under `.github/workflows`.

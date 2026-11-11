---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 09
subsystem: testing
tags: [puppet, bolt-plans, begin_at_step, step-names, rspec, change-ledger]
status: complete

requires:
  - phase: 01-foundations-diagnostics-and-test-baseline
    provides: Phase 1 change ledger section, Ledger-ID trailer rule, service_ready_timeout parameters (plans 01-01, 01-06)
provides:
  - "Peadm::AddDatabaseSteps type replacing the inline Enum in peadm::add_database"
  - "spec/unit/step_names_spec.rb: fails when plan_step names drift from the Peadm::*Steps types"
  - "node_group_environment resolved in the body (not a remote parameter default) in add_database, upgrade and convert"
  - "Ledger rows P1-13 and P1-14, fix-log entry P1-13"
affects: [01-13, 01-14]

actuals:
  tokens: 8400
  tasks: 2
  commits: 2
plan_head_before: 5ef9babd2fd78e3a27064c08b9d5b04619b9ed9b
plan_head_after: d2c69767f8787e9fbb57cb15a26cfe595d4389b2
commits: 2

tech-stack:
  added: []
  patterns:
    - "A remote lookup that used to be a parameter default is an Optional parameter (undef) resolved at the top of the plan body, so parameter type errors fire before any task runs"
    - "Static repo-consistency spec reading .pp sources (step names vs type Enum values), with mutation-tested parsing helpers"

key-files:
  created:
    - types/adddatabasesteps.pp
    - spec/unit/step_names_spec.rb
  modified:
    - plans/add_database.pp
    - plans/upgrade.pp
    - plans/convert.pp
    - spec/plans/add_database_spec.rb
    - spec/plans/upgrade_spec.rb
    - spec/plans/convert_spec.rb
    - REFERENCE.md
    - documentation/change-ledger.md
    - documentation/fix-log.md

key-decisions:
  - "No fail_plan for unknown step names: the parameter type error already names the type and lists the valid steps, and fires before the body"
  - "Resolved value lives in a new local ($resolved_node_group_environment) rather than reassigning the parameter, which Puppet forbids"

requirements-completed: [FND-04, TRC-01, TRC-02]

coverage:
  - id: D1
    description: "An invalid begin_at_step fails peadm::add_database, peadm::upgrade and peadm::convert before any task runs, naming the type and the valid steps"
    requirement: "FND-04"
    verification:
      - kind: unit
        ref: "spec/plans/add_database_spec.rb#rejects an unknown begin_at_step naming the type and valid steps, before any task runs"
        status: pass
      - kind: unit
        ref: "spec/plans/upgrade_spec.rb#rejects an unknown begin_at_step naming the type and valid steps, before any task, command or plan runs"
        status: pass
      - kind: unit
        ref: "spec/plans/convert_spec.rb#rejects an unknown begin_at_step naming the type and valid steps, before any task runs"
        status: pass
    human_judgment: false
  - id: D2
    description: "A spec fails if a plan's plan_step names drift from its Peadm::*Steps type"
    requirement: "FND-04"
    verification:
      - kind: unit
        ref: "spec/unit/step_names_spec.rb"
        status: pass
    human_judgment: false
  - id: D3
    description: "node_group_environment is still read from pe.conf when omitted and not read when given; upgrade logs the resolved value"
    requirement: "FND-04"
    verification:
      - kind: unit
        ref: "spec/plans/upgrade_spec.rb#reads node_group_environment from pe.conf when omitted and logs the resolved value"
        status: pass
      - kind: unit
        ref: "spec/plans/convert_spec.rb#reads node_group_environment from pe.conf when omitted"
        status: pass
    human_judgment: false
  - id: D4
    description: "Ledger rows P1-13 and P1-14, fix-log entry P1-13, regenerated REFERENCE.md"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "grep '^| P1-13 |' and '^| P1-14 |' documentation/change-ledger.md; bundle exec rake strings:validate:reference exits 0"
        status: pass
    human_judgment: false
---

# Phase 1 Plan 09: begin_at_step validation and step-name drift guard Summary

**An invalid `begin_at_step` now fails `peadm::upgrade`, `peadm::convert` and `peadm::add_database` on its `Peadm::*Steps` type, listing the valid names, before any task contacts the primary; a new static spec fails when a plan's `peadm::plan_step` names drift from their type.**

## Accomplishments

- `types/adddatabasesteps.pp` defines `Peadm::AddDatabaseSteps` with the six steps in run order; `peadm::add_database` uses it instead of an inline `Enum`.
- `spec/unit/step_names_spec.rb` reads the `.pp` sources and checks, per plan (upgrade, convert, add_database), that the `plan_step('...')` names equal the type's Enum values in the same order and that `begin_at_step` uses that type. A further example fails if any plan under `plans/` calls `plan_step(` without a `Peadm::*Steps` `begin_at_step`. The two parsing helpers are mutation-checked on inline strings (a renamed step must make the comparison differ).
- `node_group_environment` is `Optional[String[1]] = undef` in all three plans and resolved at the top of the body into `$resolved_node_group_environment` (selector on undef calling `peadm::get_node_group_environment`). Before, the parameter default ran a remote `peadm::read_file` before the `begin_at_step` type error, so an unreachable primary hid the real error. In upgrade the `log_plan_parameters` hash now logs the resolved value.
- Bogus-step examples in the three plan specs: no task, command or plan is called (BoltSpec fails on any unstubbed call).
- `REFERENCE.md` regenerated with `rake strings:generate:reference`; `strings:validate:reference` exits 0. The diff covers only the new type entry, the add_database `begin_at_step` type and the three `node_group_environment` type/default/doc changes.
- Ledger rows P1-13 and P1-14 and fix-log entry P1-13 (covering both rows) written; Commit column left for plan 01-14.

## Task Commits

1. Task 1 (tracer): `2851398` - `(P0-1) Add Peadm::AddDatabaseSteps and a spec that fails when plan step names drift from their types` (`Ledger-ID: P1-13`)
2. Task 2: `d2c6976` - `(P0-1) Reject an invalid begin_at_step in upgrade and convert before contacting the primary` (`Ledger-ID: P1-14`)

Tracer gate: the tracer `<verify>` is automated-only; it was re-run end to end after the commit's content was final and passed (21 examples, lint, grep checks) before Task 2 started.

## Deviations from Plan

**1. [Rule 3 - Blocker] Fixture modules were missing**
- **Found during:** Task 1 (first spec run)
- **Issue:** `spec/fixtures/modules` was empty, so plan specs failed with `Could not find a plan named 'peadm::add_database'` (10 spurious failures).
- **Fix:** ran `bundle exec rake spec_prep` (untracked build output; nothing committed).
- **Commit:** none

**2. [Rule 1 - Style] RuboCop `Style/BlockDelimiters` in the new drift spec**
- Multi-line `select { ... }` changed to `do ... end` before committing.

**Total deviations:** 2 (1 Rule 3, 1 Rule 1). **Impact:** none on behaviour.

## Verification

- Reproduce check done: with the parent versions of the three plans swapped back in, the new bogus-step examples fail (`Expected peadm::read_file to be called 0 times` for add_database; `Unexpected call to 'run_task(peadm::read_file, ["primary"], ...pe.conf)'` for upgrade and convert).
- `bundle exec rspec spec/plans/upgrade_spec.rb spec/plans/convert_spec.rb spec/unit/step_names_spec.rb`: 57 examples, 0 failures.
- `bundle exec rake parallel_spec`: 705 examples, 0 failures, 6 pending (pre-existing).
- `bundle exec rake validate lint check rubocop`: exit 0 (124 files, no offenses). `puppet-lint` run directly on `plans/add_database.pp` shows the pre-existing `strict_indent` warnings, which the rake lint task disables.
- `bundle exec rake strings:validate:reference`: exit 0.
- Grep check: no `String[1] $node_group_environment = peadm::get_node_group_environment` default remains in upgrade, convert or add_database (3 at the parent).

## Known Stubs

None.

## Threat Flags

None. Threat T-01-17 (step-name drift skipping steps) is mitigated as planned: drift spec, `Peadm::AddDatabaseSteps`, parameter validation before any remote call.

## Self-Check: PASSED

- FOUND: types/adddatabasesteps.pp, spec/unit/step_names_spec.rb
- FOUND commits: 2851398, d2c6976 (ancestors of HEAD)
- Ledger rows P1-13 and P1-14 present in documentation/change-ledger.md

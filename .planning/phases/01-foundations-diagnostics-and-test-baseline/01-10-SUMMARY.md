---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 10
subsystem: install
tags: [puppet, bolt-plans, pe-environment, pe-conf, readiness-deadline, rspec, change-ledger]
status: complete

requires:
  - phase: 01-foundations-diagnostics-and-test-baseline
    provides: service_ready_timeout naming and the timeout argument of peadm::wait_until_service_ready (plan 01-06), the pre-commit pe-master wait (plan 01-05), Ledger-ID trailer rule (plan 01-01)
provides:
  - "Peadm::Pe_environment type and peadm::get_node_group_environment accepting a pe.conf Hash"
  - "peadm::install resolves the PE environment from pe_conf_data and passes it to the install and configure subplans"
  - "service_ready_timeout on peadm::install, reaching all three readiness waits on the install path"
  - "/tmp/pe.conf chmod 0600 after upload and removed after the installers, on success and failure, in the install subplan and init_db_server"
  - "init_db_server wait_time parameter (default 120)"
  - "Ledger rows P1-15 to P1-17, fix-log entries P1-15 to P1-17"
affects: [01-13, 01-14]

actuals:
  tokens: 13000
  tasks: 3
  commits: 3
plan_head_before: e2b1ee4ec15d8ce618046c7c76c15e0ca9ab763e
plan_head_after: 9faec421d0eca7c4a0fcdf2311c67d4bb77ea44b
commits: 3

tech-stack:
  added: []
  patterns:
    - "A function that reads pe.conf from a node also accepts the pe.conf Hash directly, so install can resolve config before any node has one"
    - "Installer runs wrapped in catch_errors() so cleanup runs before fail_plan(Error) re-raises Bolt's own run-failure"
    - "Apply-block parameters, which BoltSpec cannot see, are checked by a region-scoped static assertion on the plan text"

key-files:
  created:
    - types/pe_environment.pp
    - spec/plans/util/init_db_server_spec.rb
  modified:
    - functions/get_node_group_environment.pp
    - plans/install.pp
    - plans/subplans/install.pp
    - plans/subplans/configure.pp
    - plans/util/init_db_server.pp
    - spec/functions/get_node_group_environment_spec.rb
    - spec/plans/install_spec.rb
    - spec/plans/subplans/install_spec.rb
    - spec/plans/subplans/configure_spec.rb
    - REFERENCE.md
    - documentation/change-ledger.md
    - documentation/fix-log.md

key-decisions:
  - "Environment resolved once in peadm::install from pe_conf_data and passed down; the subplans keep a 'production' default so other callers are unchanged"
  - "init_db_server stays public (no @api private) because documentation/backup_restore.md tells operators to run it; it only gains @summary/@param docs"
  - "On installer failure the plan fails with the original Bolt Error (kind bolt/run-failure, result set intact) rather than a rewritten message"

requirements-completed: [FND-02, FND-07, FND-06, TRC-01, TRC-02]

coverage:
  - id: D1
    description: "peadm::install with pe_conf_data naming a non-production environment stubs and commits that environment (site.pp path), production when unset; an invalid name or disagreeing keys fail before any subplan runs"
    requirement: "FND-02"
    verification:
      - kind: unit
        ref: "spec/functions/get_node_group_environment_spec.rb#when given a pe.conf Hash instead of a target"
        status: pass
      - kind: unit
        ref: "spec/plans/subplans/install_spec.rb#node_group_environment"
        status: pass
      - kind: unit
        ref: "spec/plans/install_spec.rb#node_group_environment from pe_conf_data (P1-15)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The PE node groups created by peadm::setup::node_manager at install time use the configured environment (static check of the apply-block declaration)"
    requirement: "FND-02"
    verification:
      - kind: unit
        ref: "spec/plans/subplans/configure_spec.rb#is mapped into the peadm::setup::node_manager class declaration"
        status: pass
    human_judgment: true
    rationale: "BoltSpec cannot see apply() parameters; the static check proves the mapping is written, not that a real cluster classifies into the environment (scenario I-02)"
  - id: D3
    description: "service_ready_timeout reaches every wait_until_service_ready call on the install path; default 60"
    requirement: "FND-07"
    verification:
      - kind: unit
        ref: "spec/plans/install_spec.rb#forwarding to both subplans (P1-16)"
        status: pass
      - kind: unit
        ref: "spec/plans/subplans/install_spec.rb#service_ready_timeout"
        status: pass
      - kind: unit
        ref: "spec/plans/subplans/configure_spec.rb#service_ready_timeout"
        status: pass
    human_judgment: false
  - id: D4
    description: "/tmp/pe.conf is chmod 0600 after upload and removed after the last installer run, on success and on installer failure, in the install subplan and init_db_server; init_db_server wait_time default 120"
    requirement: "FND-06"
    verification:
      - kind: unit
        ref: "spec/plans/subplans/install_spec.rb#/tmp/pe.conf hygiene"
        status: pass
      - kind: unit
        ref: "spec/plans/util/init_db_server_spec.rb"
        status: pass
    human_judgment: true
    rationale: "Specs assert command order and the failure path; the acceptance node check that the file is really gone is plan 01-13"
  - id: D5
    description: "Ledger rows P1-15 to P1-17, fix-log entries P1-15 to P1-17, regenerated REFERENCE.md"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "grep '^| P1-1[567] |' documentation/change-ledger.md; bundle exec rake strings:validate:reference exits 0"
        status: pass
    human_judgment: false
---

# Phase 1 Plan 10: PE environment, readiness deadline and pe.conf hygiene on the install path Summary

**`peadm::install` now stubs and classifies into the PE environment named in `pe_conf_data` (validated by `Peadm::Pe_environment`), passes an operator `service_ready_timeout` to every readiness wait, and no longer leaves a world-readable `/tmp/pe.conf` with the console password behind, on success or on installer failure.**

## Accomplishments

- `Peadm::Pe_environment` (`\A[a-z0-9_]+\z`) and `peadm::get_node_group_environment` taking either a target or a pe.conf Hash. The equality rule and the existing differing-keys message are unchanged; an invalid name now fails naming it before it can reach a path (T-01-19).
- `peadm::install` resolves the environment once from `pe_conf_data` and passes it to both subplans. The install subplan builds the `site.pp` stub path from it (the hard-coded production path is gone, 1 occurrence at the parent, 0 now); the configure subplan passes it into the `peadm::setup::node_manager` declaration, so the class default no longer wins.
- `service_ready_timeout` (`Integer[1]`, default 60) on `peadm::install`, forwarded to both subplans, and from there to the two `pe-master` waits in the install subplan and the `all` wait in configure. Two-argument waits in those files: 3 at the parent, 0 now.
- `/tmp/pe.conf`: `chmod 0600` right after upload; installer runs (primary `pe_install`, database-host `pe_install`, split-database `pe_reinstall`) wrapped in `catch_errors()`. On an Error the file is removed from the upload targets and the plan `fail_plan`s with the same Error; on success it is removed right after the block, before the RBAC token step (T-01-18, T-01-20). `peadm::util::init_db_server` does the same around its `pe_install` and gains `wait_time` (default 120, Bolt's own default).
- First spec for `peadm::util::init_db_server`.
- `REFERENCE.md` regenerated with `rake strings:generate:reference` in each task; diffs cover only the new type, the function signature/doc, the new `peadm::install` parameter and the `init_db_server` docs and parameter. Ledger rows P1-15, P1-16, P1-17 and fix-log entries for each written; Commit column left for plan 01-14.

## Task Commits

1. Task 1 (tracer): `ff12038` - `(PE-39789) Install into the environment set in pe_conf_data instead of assuming production` (`Ledger-ID: P1-15`)
2. Task 2: `ddfe93e` - `(PE-39789) Classify PE node groups into the configured environment and pass the readiness deadline through peadm::install` (`Ledger-ID: P1-16`)
3. Task 3: `9faec42` - `(P1-17) Restrict /tmp/pe.conf to 0600 and remove it after the installer has used it` (`Ledger-ID: P1-17`)

Tracer gate: the tracer `<verify>` is automated-only; it was re-run after the commit content was final and passed (spec files 52 examples, grep check, puppet-lint, ledger row) before Task 2 started.

## Deviations from Plan

**1. [Rule 3 - Blocker] Fixture modules were missing**
- **Found during:** Task 1 (first spec run: every function spec failed with `undefined method 'func_name' for nil`, including the untouched ones).
- **Fix:** `bundle exec rake spec_prep` (untracked build output; nothing committed).
- **Commit:** none

**2. [Rule 3 - Scope] REFERENCE.md regenerated in Task 1 as well as Tasks 2 and 3**
- The plan lists REFERENCE.md only for Tasks 2 and 3, but Task 1 adds a public type and changes a public function signature, so the file was regenerated in that commit to keep `strings:validate:reference` green at every commit. Ledger row P1-15 lists it.

**3. [Rule 1 - Style] RuboCop `Style/Lambda`** in new spec helpers: `lambda do` changed to `->` before committing.

**4. [Decision] `init_db_server` not marked `@api private`**
- The plan is under `plans/util/`, but `documentation/backup_restore.md` tells operators to run it. Marking it private would drop it from the public REFERENCE.md. It gains a `@summary` and `@param` header only.

**5. [Process] Task 2 specs written after the edits.** The wiring edits were made before the specs. The configure specs were then checked by mutation (mapping line removed, timeout argument removed: the two matching examples fail). Task 1 and Task 3 followed RED then GREEN.

**Total deviations:** 5 (1 Rule 3 blocker, 1 Rule 3 scope, 1 style, 1 decision, 1 process). **Impact:** none on behaviour.

## Verification

- Task 1, 2 and 3 `<automated>` commands: pass.
- `bundle exec rake strings:validate:reference`: exit 0.
- `bundle exec rake validate lint check rubocop`: exit 0.
- `bundle exec rake parallel_spec`: 744 examples, 0 failures, 6 pending (pre-existing).
- `spec/classes/setup/node_manager_spec.rb` unchanged and passing (12 examples).
- Mutation checks: with the parent `plans/util/init_db_server.pp` swapped back in, 6 of 9 new examples fail; with the node_manager mapping and the deadline removed from `configure.pp`, the two matching examples fail.

## Known Stubs

None.

## Threat Flags

None. Threats T-01-18, T-01-19 and T-01-20 are mitigated as planned: chmod and removal on success and failure, `Peadm::Pe_environment` on the function and both subplan parameters. A plan killed mid-run can still leave `/tmp/pe.conf`, at mode 0600 (accepted in the plan).

## Self-Check: PASSED

- FOUND: types/pe_environment.pp, spec/plans/util/init_db_server_spec.rb
- FOUND commits: ff12038, ddfe93e, 9faec42 (ancestors of HEAD)
- Ledger rows P1-15, P1-16, P1-17 present in documentation/change-ledger.md

---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 08
subsystem: testing
tags: [puppet, bolt-plans, pe-versions, rspec, change-ledger]
status: complete

requires:
  - phase: 01-foundations-diagnostics-and-test-baseline
    provides: Phase 1 change ledger section and Ledger-ID trailer rule (plan 01-01)
provides:
  - "`default` key in data/pe_versions.yaml, returned by peadm::supported_pe_versions"
  - "peadm::install `version` default derived from the data file"
  - "Spec that fails when the default is not x.y.z or lies outside oldest..newest"
  - "Ledger row P1-12"
affects: [01-13, 01-14]

actuals:
  tokens: 4340
  tasks: 1
  commits: 1
plan_head_before: cd652dfdc325b9228561b2666e2abb0f178d9a21
plan_head_after: 3e47730719f440b5b892a30b6528d1679d45220d
commits: 1

tech-stack:
  added: []
  patterns:
    - "A plan parameter default may call a module function (peadm::supported_pe_versions()['default'])"
    - "Struct keys that are Puppet reserved words (`default`) are quoted in return_type strings"

key-files:
  created: []
  modified:
    - data/pe_versions.yaml
    - lib/puppet/functions/peadm/supported_pe_versions.rb
    - spec/functions/supported_pe_versions_spec.rb
    - plans/install.pp
    - spec/plans/install_spec.rb
    - REFERENCE.md
    - documentation/change-ledger.md

key-decisions:
  - "Struct key is written \"default\" (quoted): `default` is a reserved word in the Puppet language and an unquoted key fails to load the function"
  - "No fix-log entry: the change is a refactor with no reported complaint behind it, and the plan does not list documentation/fix-log.md"

requirements-completed: [TST-06, TRC-01]

coverage:
  - id: D1
    description: "peadm::install default PE version comes from data/pe_versions.yaml through peadm::supported_pe_versions"
    requirement: "TST-06"
    verification:
      - kind: unit
        ref: "spec/plans/install_spec.rb#default version (install subplan receives the data file's default when no version is given)"
        status: pass
      - kind: unit
        ref: "spec/functions/supported_pe_versions_spec.rb#returns the oldest, newest and default supported PE versions"
        status: pass
    human_judgment: false
  - id: D2
    description: "A spec fails when default lies outside oldest..newest or is not an x.y.z Peadm::Pe_version"
    requirement: "TST-06"
    verification:
      - kind: unit
        ref: "spec/functions/supported_pe_versions_spec.rb#keeps the default inside oldest..newest and shaped like a Peadm::Pe_version"
        status: pass
    human_judgment: false
  - id: D3
    description: "Ledger row P1-12 and regenerated REFERENCE.md"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "grep '^| P1-12 |' documentation/change-ledger.md; bundle exec rake strings:validate:reference exits 0"
        status: pass
    human_judgment: false
---

# Phase 1 Plan 08: Install default PE version from data Summary

**`peadm::install` now takes its default `version` from a new `default` key in `data/pe_versions.yaml` (read through `peadm::supported_pe_versions`), and a spec fails when that default leaves the supported range or stops being a full x.y.z version.**

## Accomplishments

- `data/pe_versions.yaml` has `default: '2025.12.1'` (the value the plan used to carry) and a header comment saying what it is and what must hold.
- `peadm::supported_pe_versions` returns `{oldest, newest, default}`; header comment and return type updated.
- `plans/install.pp`: `$version = peadm::supported_pe_versions()['default']`, with a new `@param version` doc. Before, the parameter was undocumented and the literal lived only in the plan. `assert_supported_pe_version` still runs on the resolved value.
- Function spec: exact hash updated, the oldest/newest shape check no longer applies to `default`, and a new example checks `default` against `\A\d+\.\d+\.\d+(-.+)?\z` and against `SemanticPuppet::VersionRange` built from oldest and newest (same semantics as `assert_supported_pe_version`).
- Install spec: running the plan without `version` makes the install subplan receive the data file's `default` (captured via an `allow_plan(...).return` block, since bolt-spec's `with_params` is strict equality). The expectation reads the data file, so reintroducing a literal that differs from it is caught.
- `REFERENCE.md` regenerated with `rake strings:generate:reference`; `strings:validate:reference` exits 0. The diff covers only the function's description and return type, and the `version` parameter (now documented, so it moved up in the parameter list with its doc text).
- Ledger row P1-12 added (Commit column left empty for plan 01-14).

## Task Commits

1. Task 1 (tracer): `3e47730` - `(PE-47850) Read the peadm::install default PE version from data/pe_versions.yaml` (carries `Ledger-ID: P1-12`)

Tracer gate: the plan has a single task, so there is nothing to expand into; the `<verify>` command was run end to end after the commit's content was final and passed.

## Deviations from Plan

**1. [Rule 1 - Bug] `default` must be quoted as a Struct key**
- **Found during:** Task 1 (GREEN)
- **Issue:** The plan's artifact pattern is `default => String`. With the key unquoted the function fails to load: `Illegal Struct member key type. Expected NotUndef, Optional, String, or Enum. Got: Symbol`, because `default` is a Puppet reserved word. This broke `assert_supported_pe_version` too (13 spec failures at first run).
- **Fix:** `return_type 'Struct[{oldest => String, newest => String, "default" => String}]'`, with a comment explaining why.
- **Files modified:** `lib/puppet/functions/peadm/supported_pe_versions.rb`, `REFERENCE.md`
- **Commit:** `3e47730`
- **Note:** the plan's `contains: "default => String"` check for the artifact does not literally match; the quoted form is the working equivalent.

**2. [Rule 3 - Blocker] Fixture modules were missing**
- **Found during:** Task 1 (RED)
- **Issue:** `spec/fixtures/modules` was empty, so plan specs failed with `Could not find a plan named 'peadm::install'`.
- **Fix:** ran `bundle exec rake spec_prep` (clones/installs fixture modules; the directory is untracked build output, nothing committed).
- **Commit:** none

**3. [Rule 3 - Adjustment] `@param version` doc did not exist**
- The plan says to "update the `@param version` doc"; `plans/install.pp` had none, so one was added. This is why the REFERENCE.md `version` entry moved in the parameter list.

**Total deviations:** 3 (1 Rule 1, 2 Rule 3). **Impact:** none on behavior; the default is still 2025.12.1.

## Verification

- Task `<verify>` command: 24 examples, 0 failures across the three spec files, all greps pass.
- `bundle exec rake parallel_spec`: 688 examples, 0 failures, 6 pending.
- `bundle exec rake validate lint check rubocop`: exits 0 (123 files, no offenses).
- `bundle exec rake strings:validate:reference`: exits 0.
- RED was observed first: the three function-spec examples failed before the data and function change (the install-spec example passes before and after because the default value is unchanged; it guards against future drift).

## Known Stubs

None.

## Threat Flags

None. T-01-16 is mitigated as planned: the spec fails unless `default` is inside `oldest..newest` and matches the `Peadm::Pe_version` shape, and `peadm::install` still calls `assert_supported_pe_version` on the resolved value.

## Self-Check: PASSED

- Commit `3e47730` is an ancestor of HEAD.
- `data/pe_versions.yaml` contains `default: '2025.12.1'`; `plans/install.pp` contains `supported_pe_versions()['default']` and no `= '2025.12.1'`; ledger has the `| P1-12 |` row.

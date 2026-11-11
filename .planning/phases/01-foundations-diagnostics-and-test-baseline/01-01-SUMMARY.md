---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 01
subsystem: testing
tags: [ruby, ci, github-actions, change-ledger]
status: complete

requires: []
provides:
  - Ruby 3.3 as the repo and CI floor (.ruby-version 3.3.0, spec.yml and the nine acceptance workflows)
  - spec.yml Puppet 8 Spec matrix rewritten to Ruby 3.3
  - Phase 1 section of the change ledger with row P1-01
affects: [01-02, 01-03, 01-13, 01-14]

actuals:
  tokens: 6000
  tasks: 2
  commits: 2
plan_head_before: 123d0ac942b47d36109b94ebcd446f08ce95a7c6
plan_head_after: f19c4f2f7b183caf47d5665c5f183d0fcec2e0f7
commits: 2

tech-stack:
  added: []
  patterns:
    - "Rewrite puppet_litmus matrix output with a safe sed so the Ruby floor is ours, not the tool's"

key-files:
  created: []
  modified:
    - .ruby-version
    - .github/workflows/spec.yml
    - .github/workflows/test-add-compiler-matrix.yml
    - .github/workflows/test-add-compiler.yaml
    - .github/workflows/test-add-replica.yaml
    - .github/workflows/test-add-replica-matrix.yaml
    - .github/workflows/test-backup-restore.yaml
    - .github/workflows/test-backup-restore-migration.yaml
    - .github/workflows/test-failover.yaml
    - .github/workflows/test-fips-install-matrix.yaml
    - .github/workflows/test-install.yaml
    - documentation/change-ledger.md
    - .claude/CLAUDE.md (on disk only, gitignored)

key-decisions:
  - "Ruby floor is 3.3, but the shared ci.yml (module_ci) Puppet 8 job still runs Ruby 3.2, so code must stay Ruby 3.2 compatible"
  - "spec.yml get-matrix post-processes matrix_from_metadata_v2 output; if the format changes the sed does not match and 3.2 stays (safe)"

requirements-completed: [TST-01, TRC-01]

coverage:
  - id: D1
    description: "Ruby floor 3.3 in .ruby-version, spec.yml (static, coverage, Puppet 8 Spec matrix) and the nine acceptance workflows"
    requirement: "TST-01"
    verification:
      - kind: integration
        ref: "get-matrix step run locally: emits {\"puppet_version\":\"~> 8.0\",\"ruby_version\":3.3}; bundle exec rake validate lint check rubocop exits 0; workflows parse as YAML"
        status: pass
    human_judgment: false
  - id: D2
    description: "Phase 1 ledger section with the ticket-key convention, Ledger-ID trailer rule and row P1-01"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "grep for the Phase 1 heading and the P1-01 row in documentation/change-ledger.md"
        status: pass
    human_judgment: false
  - id: D3
    description: "First CI run on the branch confirms the old gem set installs and runs on Ruby 3.3"
    requirement: "TST-01"
    verification: []
    human_judgment: true
    rationale: "Needs a real GitHub Actions run; plan 01-13's checkpoint asks for the static and coverage job results"
---

# Phase 1 Plan 01: Ruby 3.3 floor and Phase 1 ledger Summary

**Ruby floor raised from 3.1 to 3.3 in `.ruby-version` and 12 of the 25 CI pins, with the spec.yml Puppet 8 matrix rewritten to Ruby 3.3 and the Phase 1 ledger section (row P1-01) opened.**

## Accomplishments

- `.ruby-version` is 3.3.0; `spec.yml` static-check and coverage jobs install Ruby 3.3.
- The `get-matrix` step now captures `matrix_from_metadata_v2` output in a temp file and appends it to `$GITHUB_OUTPUT` through a `sed` that turns `"ruby_version":3.2` into 3.3. Running the real step locally emits `{"include":[{"puppet_version":"~> 8.0","ruby_version":3.3}]}`.
- Nine acceptance workflows moved to Ruby 3.3 (10 pins; the migration workflow has two). Remaining 13 pins belong to plan 01-02.
- `.claude/CLAUDE.md` Ruby mentions updated (floor 3.3.0, 3.2 local fallback, `ci.yml` module_ci Puppet 8 job still on Ruby 3.2 so code must stay 3.2 compatible).
- Change ledger has the Phase 1 section, ticket-key note, Ledger-ID trailer rule and row P1-01 (Commit column left empty for plan 01-14).

## Task Commits

1. Task 1 (tracer): `f464f59` - `.ruby-version`, `spec.yml`, ledger section
2. Task 2: `f19c4f2` - nine workflows, ledger Files cell

## Deviations from Plan

**1. [Rule 3 - Blocker] `.claude/CLAUDE.md` is gitignored and untracked**
- **Found during:** Task 2
- **Issue:** The plan lists CLAUDE.md in `files_modified`, but `git check-ignore` matches it and `git ls-files` does not list it, so it cannot be committed (force-adding is not allowed).
- **Fix:** The three Ruby mentions were edited on disk as approved; the file is not in the Task 2 commit. The commit message says so. Ledger row P1-01 still lists CLAUDE.md because the change was made.
- **Files modified:** `.claude/CLAUDE.md` (disk only)
- **Commit:** none

**Total deviations:** 1 (Rule 3). **Impact:** The CLAUDE.md edit is local only; anyone cloning the repo does not get it. If the team wants it versioned, un-ignore or track the file in a separate decision.

## Verification

- Tracer and Task 2 `<verify>` commands pass.
- `bundle exec rake validate lint check rubocop` exits 0 (111 files, no offenses).
- `ruby spec/acceptance/scenarios.rb --validate` exits 0.
- Local Ruby is 3.2.3 (accepted fallback); the Ruby 3.3 behavior is unproven until the first CI run.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- Commits `f464f59` and `f19c4f2` are ancestors of HEAD.
- `.ruby-version` contains 3.3.0; no `ruby-version: '3.1'` remains in the ten files this plan owns.

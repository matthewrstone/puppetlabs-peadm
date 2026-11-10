---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 03
subsystem: testing
tags: [rspec-puppet, puppetlabs_spec_helper, fixtures, github-actions, bolt, puppet9, change-ledger]
status: complete

requires: ["01-02"]
provides:
  - Specs run on puppetlabs_spec_helper 9.0.0 / rspec-puppet 5.0.0 / lint plugins 7.0.0 (534 examples, 0 failures, 6 pending)
  - All 14 fixtures in .fixtures.yml pinned to a tag or commit
  - Non-blocking Puppet 9 spec lane and a token-gated Bolt 5.2 / Puppet 9 lane in spec.yml
  - Gemfile BOLT_GEM_VERSION switch resolving Bolt through the puppetcore source
  - Change ledger rows P1-02 and P1-03 plus a Deferred follow-ups list
affects: [01-04, 01-13, 01-14]

actuals:
  tokens: 3800
  tasks: 2
  commits: 2
plan_head_before: aeb87b41a91361e7c07f794ae29b7c7441b75fca
plan_head_after: f6b6ca497e54a6dad10a6225da8b5e0177272fab
commits: 2

tech-stack:
  added:
    - "puppetlabs_spec_helper 9.0.0 (was 6.0.3)"
    - "rspec-puppet 5.0.0 (transitive via helper 9, was 4.0.2)"
    - "voxpupuli-puppet-lint-plugins 7.0.0 (was 5.0.0)"
    - "puppetlabs-syntax 7.2.1 (transitive via helper 9; approved at the legitimacy gate)"
  patterns:
    - "Use PuppetlabsSyntax.exclude_paths.concat, never assignment, because helper 9 pre-seeds the paths"
    - "Secrets cannot be read in a job-level if:, so a small check_token job exports a true/false output"

key-files:
  created: []
  modified:
    - Gemfile
    - Rakefile
    - .sync.yml
    - .fixtures.yml
    - manifests/setup/node_manager.pp
    - .github/workflows/spec.yml
    - documentation/change-ledger.md

key-decisions:
  - "metadata.json Puppet range stays >= 8.0.0 < 9.0.0 (user decision); the widening is a recorded deferred follow-up, so the shared ci.yml gains no blocking Puppet 9 job"
  - "rspec-puppet-facts stays on 2.x (6.x pulls in openfact)"
  - "Gemfile.lock is gitignored, so the dependency bump is carried by the Gemfile constraints only"

patterns-established:
  - "Fixtures use the expanded repo/ref hash form"

requirements-completed: [TST-01, TST-02, TRC-01]

coverage:
  - id: D1
    description: "Full spec suite passes under rake parallel_spec on helper 9 / rspec-puppet 5 with all fixtures pinned"
    requirement: "TST-01"
    verification:
      - kind: integration
        ref: "bundle exec rake spec_clean spec_prep && bundle exec rake parallel_spec (534 examples, 0 failures, 6 pending)"
        status: pass
    human_judgment: false
  - id: D2
    description: "rake validate lint check rubocop exits 0 after the bump"
    requirement: "TST-01"
    verification:
      - kind: other
        ref: "bundle exec rake validate lint check rubocop (rc=0; 111 files, no offenses)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Puppet 9 job is continue-on-error; Bolt5Puppet9 is token-gated and continue-on-error; Puppet 8 Spec job is unchanged"
    requirement: "TST-02"
    verification:
      - kind: other
        ref: "Task 2 verify: spec.yml parsed with ruby -ryaml, job keys and needs checked; BOLT_GEM_VERSION='>= 4.0.0' bundle exec bolt --version returns 4.0.0"
        status: pass
    human_judgment: false
  - id: D4
    description: "The Bolt 5.2 / Puppet 9 lane actually resolves and passes in CI"
    requirement: "TST-02"
    verification: []
    human_judgment: true
    rationale: "Needs the Puppet Core token and a GitHub Actions run; result is recorded by plan 01-13"
  - id: D5
    description: "Ledger rows P1-02 and P1-03 and the deferred follow-ups"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "grep for '^| P1-02 |', '^| P1-03 |' and 'Deferred follow-ups' in documentation/change-ledger.md"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-11-10
---

# Phase 1 Plan 03: Test toolchain on helper 9 and CI lanes for Puppet 9 / Bolt 5 Summary

**Specs now run on puppetlabs_spec_helper 9 / rspec-puppet 5 with all 14 fixtures pinned to tags, and spec.yml gains a non-blocking Puppet 9 lane plus a token-gated Bolt 5.2 lane.**

## Performance

- **Duration:** about 25 min (after the legitimacy gate was approved)
- **Tasks:** 2 of 2 executed (plus the Task 0 gate, approved by the user)
- **Files modified:** 7

## Accomplishments

- Task 1 (tracer): bumped helper 6 to 9, lint plugins 5 to 7 (rspec-puppet 5 and puppetlabs-syntax 7.2.1 arrive transitively), pinned every fixture, switched the Rakefile and `.sync.yml` to `PuppetlabsSyntax.exclude_paths.concat`, added the trailing comma in `manifests/setup/node_manager.pp`. Proved end to end: `spec_clean spec_prep`, `validate lint check rubocop` (rc 0), `parallel_spec` 534 examples, 0 failures, 6 pending.
- Task 2: `continue-on-error: true` on `Ruby4Puppet9Experimental` with the comment rewritten per D-09; new `check_token` and `Bolt5Puppet9` jobs; Gemfile `BOLT_GEM_VERSION` switch, proved locally with the public 4.x line.
- Ledger rows P1-02 and P1-03 and the Deferred follow-ups list (GitLab CI Ruby 2.x lanes; metadata.json Puppet range widening).

## Task Commits

1. Task 0 (legitimacy gate for puppetlabs-syntax 7.2.1): approved by the user, no commit
2. Task 1: `b7a8214` (P1-02) Move specs to puppetlabs_spec_helper 9 and rspec-puppet 5 with fixtures pinned to tags
3. Task 2: `f6b6ca4` (P1-03) Add informational Puppet 9 and token-gated Bolt 5 CI lanes

## Deviations from Plan

None - plan executed exactly as written. Static lint, spec and fixture fallout was none beyond the Rakefile and the trailing comma the plan predicted.

## Issues Encountered

- `bundle list` prints "Your Gemfile lists the gem puppetlabs_spec_helper (~> 9.0) more than once" because the plan keeps the gem in both the development and release_prep groups, as the original Gemfile did with ~> 6.0. Harmless warning, left as planned.

## Known Stubs

None.

## Threat Flags

None. The new check_token and Bolt5Puppet9 jobs match threat register items T-01-01 and T-01-03: the token is only mapped into step env, the output is the literal true/false, the job also requires the puppetlabs repository owner, and it is continue-on-error.

## Next Phase Readiness

- Later plans write specs on the helper 9 toolchain.
- The Bolt 5.2 / Puppet 9 CI result still has to be observed; plan 01-13 records it.
- `Gemfile.lock` is gitignored, so CI resolves fresh from the Gemfile constraints.

## Self-Check: PASSED

- Files exist: Gemfile, Rakefile, .sync.yml, .fixtures.yml, manifests/setup/node_manager.pp, .github/workflows/spec.yml, documentation/change-ledger.md
- Commits b7a8214 and f6b6ca4 are ancestors of HEAD

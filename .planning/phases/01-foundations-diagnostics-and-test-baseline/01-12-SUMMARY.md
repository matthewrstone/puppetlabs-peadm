---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 12
subsystem: secrets-hygiene
tags: [puppet, bolt-plans, file-modes, rbac-token, signed-url, plan-output, planted-secret-spec, change-ledger]
status: complete

requires:
  - phase: 01-foundations-diagnostics-and-test-baseline
    provides: Ledger-ID trailer rule (plan 01-01), ShellTaskHarness and unit task spec patterns (plan 01-04), /tmp/pe.conf handling (plan 01-10), peadm::subplans::install readiness waits (plans 01-06, 01-10)
provides:
  - "peadm::util::copy_file with an optional mode; /secrets/ paths default to 0600, others 0644"
  - "RBAC token file written 0600 in a 0700 directory, existing file tightened"
  - "peadm::installer_tarball_name function; signed installer URLs no longer reach logs, upload paths or the installer directory"
  - "spec/plans/plan_output_secrets_spec.rb: planted-secret proof over peadm::install, peadm::subplans::install and peadm::upgrade output"
  - "Ledger rows P1-21 to P1-23, fix-log entries P1-21 to P1-23, regenerated REFERENCE.md"
affects: [01-13, 01-14]

actuals:
  tokens: 9000
  tasks: 3
  commits: 3
plan_head_before: ab7b0d6beb6d7eb34fe8cd9dd5d7bbcc31f49aa4
plan_head_after: a209968d8ef8bef55d96775218459afa2ed955b7
commits: 3

tech-stack:
  added: []
  patterns:
    - "Plan-output capture: allow_any_out_message and allow_any_out_verbose, then wrap executor.publish_event to collect message and verbose text while passing events on"
    - "Test seam as a keyword argument (token_path:) instead of a task parameter, because Bolt validates task parameters against the JSON metadata"
    - "Chmod the open file before writing a secret into it, so a pre-existing world-readable file never holds the new content"

key-files:
  created:
    - functions/installer_tarball_name.pp
    - spec/functions/installer_tarball_name_spec.rb
    - spec/plans/plan_output_secrets_spec.rb
    - spec/plans/util/copy_file_spec.rb
  modified:
    - plans/util/copy_file.pp
    - tasks/rbac_token.rb
    - spec/unit/task/rbac_token_spec.rb
    - plans/upgrade.pp
    - plans/subplans/install.pp
    - REFERENCE.md
    - documentation/change-ledger.md
    - documentation/fix-log.md

key-decisions:
  - "copy_file default mode is 0600 for any path containing /secrets/, else 0644; owner and group stay root:root; no caller changed"
  - "The replica read check in plan 01-13 gates the copy_file change; if it fails plan 01-14 stops at a user decision before any mode change"
  - "The RBAC token file is chmod'ed to 0600 on the open handle before the token is written (the plan said afterwards), so there is no readable window on an existing file"
  - "Installer file names are derived from a URL only through peadm::installer_tarball_name; the download source stays the full signed URL"
  - "Plan-output capture also collects out::verbose events, not just out::message"

requirements-completed: [FND-06, FND-05, TRC-01, TRC-02]

coverage:
  - id: D1
    description: "Secret key stores copied to replicas are written 0600, other copied files 0644, an explicit mode wins, invalid modes are rejected by the parameter type"
    requirement: "FND-06"
    verification:
      - kind: unit
        ref: "spec/plans/util/copy_file_spec.rb"
        status: pass
      - kind: unit
        ref: "spec/plans/add_replica_spec.rb and spec/plans/subplans/configure_spec.rb (callers unchanged)"
        status: pass
    human_judgment: true
    rationale: "That the replica's PE services can still read the 0600 key stores after add_replica is the replica read check in plan 01-13; the spec only pins the mode passed to mkdir_p_file"
  - id: D2
    description: "The RBAC token file is created 0600 in a 0700 directory and an existing 0644 token file is tightened to 0600"
    requirement: "FND-06"
    verification:
      - kind: unit
        ref: "spec/unit/task/rbac_token_spec.rb (real tmpdir examples)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A signed pe_installer_source URL does not leak its query string into the upgrade log, the upload path or the installer directory"
    requirement: "FND-05"
    verification:
      - kind: unit
        ref: "spec/functions/installer_tarball_name_spec.rb"
        status: pass
      - kind: unit
        ref: "spec/plans/plan_output_secrets_spec.rb#peadm::upgrade"
        status: pass
      - kind: unit
        ref: "spec/plans/plan_output_secrets_spec.rb#peadm::subplans::install"
        status: pass
    human_judgment: false
  - id: D4
    description: "Planted console password, license key, r10k private key and signed URL never appear in any message printed by peadm::install, peadm::subplans::install or peadm::upgrade, nor in a fail_plan message"
    requirement: "FND-05"
    verification:
      - kind: unit
        ref: "spec/plans/plan_output_secrets_spec.rb"
        status: pass
    human_judgment: false
  - id: D5
    description: "Ledger rows P1-21 to P1-23, fix-log entries P1-21 to P1-23, regenerated REFERENCE.md"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "grep '^| P1-2[123] |' documentation/change-ledger.md; grep '^### P1-2[123] ' documentation/fix-log.md; bundle exec rake strings:validate:reference exits 0"
        status: pass
    human_judgment: false
---

# Phase 1 Plan 12: Restrictive modes for secret files and a planted-secret proof for plan output Summary

**Secret key stores copied to replicas are now written 0600 (other copies stay 0644, an explicit `mode` wins), the RBAC token file is created 0600 in a 0700 directory and an existing world-readable one is tightened, and a planted-secret spec proves no secret reaches plan output, which also exposed and fixed a pre-signed installer URL leaking its signature into the upgrade log, upload path and installer directory.**

## Accomplishments

- `peadm::util::copy_file` takes `Optional[Pattern[/\A0?[0-7]{3}\z/]] $mode = undef`. The effective mode is the parameter, else `0600` when the path contains `/secrets/`, else `0644`; owner and group stay root:root. The three key stores copied to a replica (orchestration `keys.json`, `orchestrator-encryption-keys.json`, console `keys.json`) get 0600; `hiera.yaml` and `ad_ca_chain.pem` keep 0644. `tasks/mkdir_p_file.sh` already chmods the empty file before writing, so there is no world-readable window. No caller changed. The plan gained `@summary`/`@param` docs and its first spec (modes per path, a file merely named `secrets.yaml` stays 0644, explicit mode on a secrets path, no leading zero accepted, five invalid modes rejected, no-content skip message).
- `tasks/rbac_token.rb` writes the token through `write_token`: `FileUtils.mkdir_p(dir, mode: 0o700)` (an existing directory keeps its mode), the file opened `WRONLY|CREAT|TRUNC` with perm `0o600` and `chmod`ed to 0600 on the open handle before the token goes in. `DEFAULT_TOKEN_PATH` and a `token_path:` constructor keyword (a test seam, not a task parameter, so `rbac_token.json` is unchanged). The stubbed `File.open`/`FileUtils` examples became real tmpdir examples that check `File.stat` modes under a 000 umask, a pre-existing 0644 file, and an existing 0755 directory.
- New `peadm::installer_tarball_name(String[1] $url) >> String` cuts the URL at the first `?` or `#` then takes the last path segment. `peadm::upgrade` (logged `pe_installer_source` and `$pe_tarball_name`) and `peadm::subplans::install` (`$pe_tarball_name`, hence upload path and `$pe_installer_dir`) use it; raw `split('/')[-1]` sites went from 3 to 0. The download source is still the full signed URL.
- `spec/plans/plan_output_secrets_spec.rb` wraps the mock executor's `publish_event` to collect every `:message` and `:verbose` event plus the text of a failed plan result. With a planted console password, license key, r10k private key and signed URL, none of `FAKE-SECRET` appears for `peadm::install` (success, and a failing install subplan), `peadm::subplans::install` (simple and split-database topology, run for real), or `peadm::upgrade`; the upgrade log shows only the file name; upload path, local path, `pe_install` tarball and `pe_reinstall` installer dir carry no query string. The spec found no leak other than the signed URL.
- Ledger rows P1-21 to P1-23 and fix-log entries P1-21 to P1-23 written; Commit column left for plan 01-14. `REFERENCE.md` regenerated.
- Full suite: `bundle exec rake parallel_spec` 821 examples, 0 failures, 6 pending (the 6 were pending before this plan).

## Task Commits

1. Task 1 (tracer): `20a90e3` - `(P1-21) Copy secret key stores to replicas with mode 0600` (`Ledger-ID: P1-21`)
2. Task 2: `e5c0d63` - `(P1-22) Write the RBAC token file with mode 0600` (`Ledger-ID: P1-22`)
3. Task 3: `a209968` - `(P1-23) Keep signed installer URL query strings out of plan output, proven by a planted-secret spec` (`Ledger-ID: P1-23`)

Tracer gate: the tracer `<verify>` is automated-only; it passed on the committed content (copy_file, add_replica and configure specs, greps, puppet-lint, ledger and fix-log rows) before Task 2 started.

## Deviations from Plan

**1. [Rule 3 - Blocker] Fixture modules were missing**
- **Found during:** Task 1 first spec run (`Could not find a plan named 'peadm::util::copy_file'`; `spec/fixtures/modules` was empty).
- **Fix:** `bundle exec rake spec_prep` (untracked build output; nothing committed).
- **Commit:** none

**2. [Decision] Token chmod happens on the open handle before the write, not afterwards.** The plan says `File.chmod(0o600, path)` after the write. Doing it on the handle before writing gives the same end state for an existing 0644 file and removes the interval where it holds the new token readable. `0o600` appears in the task, as the plan's grep requires.

**3. [Rule 3 - Scope] REFERENCE.md diff includes `peadm::util::copy_file`'s new `@summary`.** Task 1 added the summary and did not regenerate REFERENCE.md (the plan only regenerates it in Task 3), so the Task 3 diff covers the new function and that one line. The ledger row P1-23 names it.

**4. [Decision] Plan-output capture also collects `out::verbose`.** The plan's technique collects `:message` only; the mock executor needs verbose events allowed too, and a secret in a verbose line is still a leak in CI logs run with `--verbose`.

**5. [Plan drift] Line numbers in the plan were stale.** The signed-URL sites were at `plans/upgrade.pp` lines 92 and 154 and `plans/subplans/install.pp` line 272, not 82/144/257. The change is the same three sites.

**6. [Process] Mutation checks were run by swapping files, not by RED commits.** For copy_file, the rbac_token and the plan changes I ran the new specs against the parent code (copy_file: 3 failures; rbac_token under umask 022: 2 failures; plan_output_secrets: 4 failures) and restored the work, rather than committing a failing test first.

**Total deviations:** 6 (1 Rule 3 blocker, 1 Rule 3 scope, 3 decisions, 1 process). **Impact:** none on the plan's behaviours.

## Known Stubs

None.

## Threat Flags

None. No new network endpoint, auth path or schema; the changes tighten file modes and remove a leak.

## Verification

- Task 1, 2 and 3 `<automated>` commands: pass (35, 34 and 98 examples, 0 failures).
- `bundle exec rake strings:validate:reference`: exit 0.
- `bundle exec rake validate lint check rubocop`: exit 0.
- `bundle exec rake parallel_spec`: 821 examples, 0 failures, 6 pending.
- `grep -nE "pe_installer_source\.split\('/'\)" plans/upgrade.pp plans/subplans/install.pp`: no output.

## Not verified here

- That the replica's pe-orchestration-services and pe-console-services can read the 0600 key stores after `peadm::add_replica` (threat T-01-28): the replica read check in plan 01-13. If it fails, plan 01-14 stops at a user decision before any mode change.
- The token file and directory modes on a real primary (`stat -c %a /root/.puppetlabs/token`): any install scenario in plan 01-13.
- A pre-signed URL upgrade against a real cluster (U-01).

## Next Phase Readiness

Ready for plan 01-13. It must add one replica to its acceptance run and check the three key stores are readable by the replica's service users and the services are active; plan 01-14 fills the Commit column for P1-21 to P1-23 from the `Ledger-ID` trailers.

## Self-Check: PASSED

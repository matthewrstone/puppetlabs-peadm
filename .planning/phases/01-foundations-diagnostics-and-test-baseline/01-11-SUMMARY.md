---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 11
subsystem: backup-restore
tags: [puppet, bolt-plans, pe-environment, puppet-backup, ca-storage-backend, shell-task, rspec, change-ledger]
status: complete

requires:
  - phase: 01-foundations-diagnostics-and-test-baseline
    provides: Peadm::Pe_environment type and peadm::get_node_group_environment taking a pe.conf Hash (plan 01-10), service_ready_timeout on peadm::install (plan 01-10), timeout argument of peadm::wait_until_service_ready (plan 01-06), ShellTaskHarness (plan 01-04), Ledger-ID trailer rule (plan 01-01)
provides:
  - "peadm::backup records the node group environment in peadm/node_group_environment.json"
  - "peadm::restore and peadm::restore_ca pass --pe-environment to puppet-backup restore for a non-production environment"
  - "peadm::migrate carries the old primary's environment into the new primary's install and restore"
  - "service_ready_timeout on peadm::restore and peadm::migrate"
  - "private task peadm::ca_storage_backend replacing the duplicated bootstrap.cfg grep in backup and restore"
  - "Ledger rows P1-18 to P1-20, fix-log entries P1-18 and P1-20"
affects: [01-13, 01-14]

actuals:
  tokens: 14500
  tasks: 3
  commits: 3
plan_head_before: f037b6c7667ed7980d8ce0f1b961e520f8a96bcc
plan_head_after: 62f7607a7670e5361a31c6da327788730bc8020d
commits: 3

tech-stack:
  added: []
  patterns:
    - "A flag that must be absent for the default case is built as a leading-space suffix variable (empty for production) and appended after an existing token, so default commands stay byte-identical"
    - "Shell task answers a three-valued question (database, filesystem, unknown) with the evidence (matched file, paths checked); callers warn on unknown instead of guessing"
    - "PEADM_ROOT-style path-prefix seam so a shell task runs against a temp tree in the harness"

key-files:
  created:
    - tasks/ca_storage_backend.sh
    - tasks/ca_storage_backend.json
    - spec/unit/shell_tasks/ca_storage_backend_spec.rb
  modified:
    - plans/backup.pp
    - plans/restore.pp
    - plans/restore_ca.pp
    - plans/migrate.pp
    - spec/plans/backup_spec.rb
    - spec/plans/restore_spec.rb
    - spec/plans/restore_ca_spec.rb
    - spec/plans/migrate_spec.rb
    - REFERENCE.md
    - documentation/change-ledger.md
    - documentation/fix-log.md

key-decisions:
  - "Restore environment precedence: node_group_environment parameter, then the backup's record, then the primary's pe.conf, then production; the flag is added only when not production"
  - "A backup record that is present but invalid (not JSON, wrong type, name outside Peadm::Pe_environment) fails the plan before any restore call rather than falling through"
  - "migrate reads the old primary's pe.conf once and passes the Hash to peadm::get_node_group_environment, instead of a second remote read"
  - "ca_storage_backend answers unknown only when none of the three locations has a file; restore runs the dump-directory test only when the backend is database"
  - "Hash parameters of the two migrate run_plan calls moved into named variables, which keeps the new key out of the strict_indent warnings"

requirements-completed: [FND-02, FND-07, TST-03, TRC-01, TRC-02]

coverage:
  - id: D1
    description: "A backup records the cluster's node group environment; restore passes it to every puppet-backup restore call as --pe-environment when it is not production, with the documented precedence; production commands unchanged"
    requirement: "FND-02"
    verification:
      - kind: unit
        ref: "spec/plans/backup_spec.rb#recording the node group environment"
        status: pass
      - kind: unit
        ref: "spec/plans/restore_spec.rb#with a non-production node group environment"
        status: pass
    human_judgment: true
    rationale: "Specs show the commands carry the flag; that puppet-backup restore --pe-environment restores into the right environment on a real non-production cluster is scenarios B-01 and M-02"
  - id: D2
    description: "restore_ca and migrate carry a non-production environment; migrate forwards service_ready_timeout to install and restore"
    requirement: "FND-02"
    verification:
      - kind: unit
        ref: "spec/plans/restore_ca_spec.rb"
        status: pass
      - kind: unit
        ref: "spec/plans/migrate_spec.rb#environment and readiness deadline"
        status: pass
    human_judgment: true
    rationale: "Forwarded parameters are asserted through allow_plan blocks; a migration of a non-production cluster is scenario M-02"
  - id: D3
    description: "service_ready_timeout on peadm::restore reaches its readiness wait (default 60); with plans 01-06 and 01-10 no two-argument wait_until_service_ready call is left in plans/"
    requirement: "FND-07"
    verification:
      - kind: unit
        ref: "spec/plans/restore_spec.rb#service_ready_timeout"
        status: pass
      - kind: other
        ref: "grep -n 'wait_until_service_ready(' plans/*.pp plans/*/*.pp | grep -v service_ready_timeout (no output)"
        status: pass
    human_judgment: false
  - id: D4
    description: "One shared task decides whether the CA is database-backed across bootstrap.cfg and both services.d locations, names the matched file, and backup and restore warn on unknown"
    requirement: "TST-03"
    verification:
      - kind: unit
        ref: "spec/unit/shell_tasks/ca_storage_backend_spec.rb"
        status: pass
      - kind: unit
        ref: "spec/plans/backup_spec.rb#with only the ca scope"
        status: pass
      - kind: unit
        ref: "spec/plans/restore_spec.rb#with a database-backed CA"
        status: pass
    human_judgment: true
    rationale: "The PE 2026.0.1 on-node layout is an assumption (RESEARCH A9) confirmed by plan 01-13, not by these specs"
  - id: D5
    description: "Ledger rows P1-18 to P1-20, fix-log entries P1-18 and P1-20, regenerated REFERENCE.md"
    requirement: "TRC-01"
    verification:
      - kind: other
        ref: "grep '^| P1-1[89] |\\|^| P1-20 |' documentation/change-ledger.md; bundle exec rake strings:validate:reference exits 0"
        status: pass
    human_judgment: false
---

# Phase 1 Plan 11: Backup, restore and migrate for non-production environments, and shared CA backend detection Summary

**Backups now record the PE node group environment and `peadm::restore`, `peadm::restore_ca` and `peadm::migrate` pass it to `puppet-backup restore --pe-environment` (production commands unchanged), `peadm::restore` and `peadm::migrate` take `service_ready_timeout`, and a new `peadm::ca_storage_backend` task replaces the duplicated single-file `bootstrap.cfg` grep in backup and restore, checking `services.d` too and warning on unknown.**

## Accomplishments

- `peadm::backup` resolves the environment from the primary's pe.conf and writes `peadm/node_group_environment.json` (root:root, 0600) beside `peadm_config.json`. `puppet-backup create` takes no flag; the value is recorded instead (PE documents `--pe-environment` for restore only).
- `peadm::restore` resolves the environment (parameter, backup record, primary pe.conf, production), prints one message naming it and its source, and appends ` --pe-environment=<env>` right after `--force` on all four restore calls only when it is not production. A record read from the backup is checked against `Peadm::Pe_environment` and shell-quoted (T-01-21, T-01-22). `service_ready_timeout` (default 60) reaches the final `all` wait.
- `peadm::restore_ca` takes `node_group_environment` (falls back to the target's pe.conf) and gains a `@summary`/`@param` header. `peadm::migrate` reads the old primary's pe.conf once, passes `pe_conf_data` with both environment keys to `peadm::install` and `node_group_environment` to `peadm::restore` for a non-production cluster (neither for production), and forwards `service_ready_timeout` to both.
- `tasks/ca_storage_backend.sh`: checks `/etc/puppetlabs/puppetserver/bootstrap.cfg`, `/etc/puppetlabs/puppetserver/services.d/*.cfg` and `/opt/puppetlabs/server/apps/puppetserver/config/services.d/*.cfg` for an uncommented database-storage-service line; returns `database` with the matched file, `filesystem`, or `unknown` with all three locations in `checked`. `PEADM_ROOT` seam for specs. Backup and restore use it; neither plan contains the service line any more. Restore still needs the `pe-ca.dump.d` directory (separate `test -d`, only when the backend is `database`). On `unknown` both plans warn, naming the paths, and keep skipping the pe-ca dump or restore (T-01-23).
- `REFERENCE.md` regenerated with `rake strings:generate:reference` in each task; diffs cover only the new restore parameters, the restore_ca docs and parameter, the migrate parameter, and the new task. Ledger rows P1-18 to P1-20 and fix-log entries P1-18 (extended for restore_ca and migrate) and P1-20 written; Commit column left for plan 01-14.
- Full suite: `bundle exec rake parallel_spec` 792 examples, 0 failures, 6 pending (the 6 were pending before this plan).

## Task Commits

1. Task 1 (tracer): `b4667e9` - `(PE-46598) Record the node group environment in backups and pass it to puppet-backup restore` (`Ledger-ID: P1-18`)
2. Task 2: `5243eda` - `(PE-46598) Carry a non-production environment through peadm::migrate and peadm::restore_ca` (`Ledger-ID: P1-19`)
3. Task 3: `62f7607` - `(P1-20) Detect the CA storage backend in one task that checks every Puppet Server bootstrap location` (`Ledger-ID: P1-20`)

Tracer gate: the tracer `<verify>` is automated-only; it was re-run after the commit content was final and passed (backup and restore specs, greps, puppet-lint, ledger row) before Task 2 started.

## Deviations from Plan

**1. [Rule 3 - Blocker] Fixture modules were missing**
- **Found during:** baseline run (every plan spec failed with `Could not find a plan named ...`).
- **Fix:** `bundle exec rake spec_prep` (untracked build output; nothing committed).
- **Commit:** none

**2. [Rule 1 - Defect in the plan's command] migrate reads pe.conf once.** The plan says to call `peadm::get_node_group_environment($old_primary_host)` next to the existing `get_pe_conf` call. That function accepts a Hash (plan 01-10), so migrate reads pe.conf once and passes the Hash; this saves a second remote read and keeps the existing migrate stubs valid. The plan's grep gate (`get_node_group_environment` in migrate.pp) still holds.

**3. [Rule 2 - Missing] restore fails on an invalid backup record.** The plan says missing content falls through; it does not say what an invalid record does. A present but unparseable or invalid record fails with a message naming the file before any restore call (T-01-22), rather than silently falling through to another environment.

**4. [Rule 3 - Scope] `plans/restore_ca.pp` gained `@summary`/`@param` docs and the missing `lint:endignore`**, and the two migrate `run_plan` calls take named parameter hashes. The first keeps REFERENCE.md meaningful for the new parameter; the second keeps the new key out of strict_indent warnings (migrate lint warnings: 25 at the parent, 16 now). No behaviour change.

**5. [Decision] Restore runs the dump-directory test only when the backend is `database`.** The plan keeps the test as a separate `run_command`; this avoids a command whose answer is not used.

**6. [Process] Specs were written after the plan edits in all three tasks, not RED first.** For the restore, restore_ca and migrate behaviours the "before" failure is evident from the missing parameter or flag; I did not run a mutation pass on the new specs. The shell-task spec for the old single-file behaviour was not run against a copy of the old inline command.

**Total deviations:** 6 (1 Rule 3 blocker, 1 Rule 1, 1 Rule 2, 1 Rule 3 scope, 1 decision, 1 process). **Impact:** none on the plan's behaviours; production commands are byte-identical to before.

## Known Stubs

None.

## Threat Flags

None. `peadm::ca_storage_backend` is read-only (greps three fixed locations) and adds no network or auth surface.

## Verification

- Task 1, 2 and 3 `<automated>` commands: pass.
- `bundle exec rake strings:validate:reference`: exit 0.
- `bundle exec rake validate lint check rubocop`: exit 0.
- `bundle exec rake parallel_spec`: 792 examples, 0 failures, 6 pending.
- `grep -n 'wait_until_service_ready(' plans/*.pp plans/*/*.pp | grep -v service_ready_timeout`: no output. `wait_until_available` calls: `max(120, $service_ready_timeout)` (upgrade, convert) and `$wait_time` (init_db_server) only.

## Not verified here

- `puppet-backup restore --pe-environment` against a real non-production cluster (B-01, M-02): specs assert the command line only.
- The PE 2026.0.1 bootstrap layout (RESEARCH A9): plan 01-13.

## Next Phase Readiness

Ready for plan 01-12. Plan 01-13 should confirm the `ca_storage_backend` locations on a PE 2026.0.1 node and run B-01 and M-02 on a non-production cluster if one is available; plan 01-14 fills the Commit column for P1-18 to P1-20 from the `Ledger-ID` trailers.

## Self-Check: PASSED

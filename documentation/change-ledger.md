# Change ledger

Every change made under the install/upgrade/rollback/failover improvement work, with the
tickets it addresses. Source of the tickets: the peadm feedback file (support cases and Jira).

**How to read it**

- **Fixes** means the change resolves what the ticket describes.
- **Mitigates** means it reduces the impact or makes the problem diagnosable, without removing the cause.
- **Related** means the ticket describes the same area but the change was not made for it.
- **None filed** means the defect was found while reviewing the code and has no ticket yet.
- `CASE-nnn` are support cases (Salesforce), which are not Jira tickets. A change that only
  cites a case has no Jira reference and needs a ticket before it ships.

**Keeping it current.** Add a row in the same commit as the change. Start the commit subject
with the ticket, as in `(PE-47850) Read supported PE range from data file`. Fill in the commit
column when the change is committed.

## Phase 0: bug fixes and quick wins

| ID | Change | Files | Jira | Cases | Relation | Tests | Commit |
|---|---|---|---|---|---|---|---|
| P0-1 | `peadm::convert` step is named `modify-primary-certs`, matching `Peadm::ConvertSteps`. Before, `begin_at_step=modify-primary-certs` matched no step and skipped them all, including the A/B pin sanity check. | `plans/convert.pp`, `REFERENCE.md` | None filed. Related: PE-44017, PE-41637 (convert failures) | | None filed | Existing convert specs pass; no new spec yet | `da4c13a` |
| P0-2 | `preparation` is an allowed `begin_at_step` for `peadm::upgrade`. A run resumed at a later step stops Puppet on all infrastructure nodes, since the skipped `preparation` step was the only place that happened. | `plans/upgrade.pp`, `types/upgradesteps.pp`, `REFERENCE.md` | None filed. Related: PE-37220 (upgrade reports complete after failed step) | CASE-002, CASE-011 | None filed | Upgrade specs pass; no new spec for the resume path yet | `56a345c` |
| P0-3 | `peadm::upgrade` fails right after reading the installed version when the target version is older, before anything is stopped. The message points to restoring from a backup. It does not catch the installer's release-date rule when the version number is higher. | `plans/upgrade.pp` | None filed | CASE-009 | None filed | `spec/plans/upgrade_spec.rb` (downgrade is refused) | `3d16bb3` |
| P0-4 | New private task `peadm::verify_tarball` runs in `preparation` on the nodes that receive the installer, before Puppet or any PE service is stopped. It checks the file exists, is not empty, passes `gzip -t`, lists fully with `tar -tf`, and contains `puppet-enterprise-installer`. | `tasks/verify_tarball.sh`, `tasks/verify_tarball.json`, `plans/upgrade.pp` | PE-42686. Related: PE-43373 | CASE-049 | Mitigates PE-42686 (the extraction step already exited non-zero; this moves detection ahead of any service change) | `spec/plans/upgrade_spec.rb` (verified before stopping Puppet; corrupt tarball stops the plan). The shell script was run by hand against good, truncated, empty, wrong-layout and missing archives. | `d1fc01c` |
| P0-5 | The legacy compiler OID check (`check_nodes_with_legacy_compiler_oid`) no longer counts nodes whose extension is `false`, because `peadm::convert` treats `false` as a modern compiler. Those nodes are listed as `ignored_nodes`. The failure message names the nodes and says to run `peadm::convert`. `peadm::upgrade` now includes that message instead of a bare "run the Convert plan". | `tasks/check_pe_master_rules.rb`, `plans/upgrade.pp` | GJira-17 | CASE-050 | Fixes GJira-17 | `spec/unit/task/check_pe_master_rules_spec.rb` (false is ignored, true blocks, message names the nodes), `spec/plans/upgrade_spec.rb` | `5bd02ea` |
| P0-6 | `pe_install` prints the last 40 lines of the newest installer log and the status of failed `pe-*` units when the installer fails, so the Bolt failure explains itself. | `tasks/pe_install.sh` | GJira-1 | CASE-002, CASE-011 | Mitigates GJira-1 (diagnosability only; the reload failure itself is not fixed) | The log and unit report was run by hand with a fake log directory and a stub `systemctl`. No spec: the task needs a real installer. | `547e469` |
| P0-7 | Supported PE range moved to `data/pe_versions.yaml` and read by new function `peadm::supported_pe_versions`. The unsupported-version error now names the installed peadm version, the supported range, and `permit_unsafe_versions=true`. The range is unchanged (2019.7 to 2026.0). An unknown newer PE line still fails by default. | `data/pe_versions.yaml`, `lib/puppet/functions/peadm/supported_pe_versions.rb`, `functions/assert_supported_pe_version.pp`, `REFERENCE.md` | PE-47850 | CASE-003 | Mitigates PE-47850 (clearer error and one place to bump; a release is still needed for each new PE line) | `spec/functions/supported_pe_versions_spec.rb`, `spec/functions/assert_supported_pe_version_spec.rb` | `7f4e82a` |

Not done in Phase 0: nothing outstanding. Items deferred by decision are in the plan file.

## Test scenario catalog

| ID | Change | Files | Jira | Cases | Relation | Tests | Commit |
|---|---|---|---|---|---|---|---|
| T-1 | Catalog of 29 install, upgrade, downgrade, rollback, failover, migration and node-replacement scenarios with versions from the reports, repro steps and expected behaviour. `scenarios.rb` filters it and emits a table, JSON, a CI matrix, or `test-scenarios.md`. | `spec/acceptance/scenarios.yaml`, `spec/acceptance/scenarios.rb`, `documentation/test-scenarios.md` | Related: each scenario lists its own tickets, for example PE-46598, PE-45758, PE-39789 and PE-42686 | see catalog | Related (supports testing; fixes nothing itself) | `spec/unit/peadm_scenarios_spec.rb` (catalog is valid, doc matches the catalog, matrix only has runnable entries) | `e40d0ac` |

Each scenario in `documentation/test-scenarios.md` lists its own source tickets and cases.

## Documentation

| ID | Change | Files | Jira | Cases | Relation | Tests | Commit |
|---|---|---|---|---|---|---|---|
| D-1 | This ledger. | `documentation/change-ledger.md` | | | | | `ebecdec` |
| D-2 | Fix log: each Phase 0 fix mapped to its complaint, with how to reproduce and demonstrate the difference. The before/after recipe was run on P0-5. | `documentation/fix-log.md` | | | | Recipe run on P0-5 (5 failures before, 26 passing after) | |

## Phase 1: foundations, diagnostics and test baseline

Ticket keys: a change with a ticket in the feedback file starts its commit subject with that ticket (for example `(PE-46598)`). A change with none starts with its ledger ID as a placeholder (for example `(P1-01)`), and work that extends P0-1 to P0-3 uses those IDs. These are the same placeholders TRC-03 replaces once the tickets are filed; placeholder rows need a ticket before release. Every commit also carries a `Ledger-ID: P1-nn` trailer, and the Commit column is filled by matching it.

| ID | Change | Files | Jira | Cases | Relation | Tests | Commit |
|---|---|---|---|---|---|---|---|
| P1-01 | Ruby floor raised from 3.1 to 3.3 in `.ruby-version`, CLAUDE.md and all 23 workflow files, 25 of 25 `ruby-version` pins (sweep complete in plans 01-01 and 01-02). D-08's "existing Ruby 3.1 lane" wording is superseded: puppetlabs_spec_helper 9 needs Ruby >= 3.2 and the floor was set to 3.3 by decision. The `spec.yml` Puppet 8 Spec matrix now runs Ruby 3.3 (the `get-matrix` step rewrites puppet_litmus' Ruby 3.2 entry), while the shared `ci.yml` Puppet 8 job (module_ci) still runs Ruby 3.2, so code must stay Ruby 3.2 compatible. A pdk template sync can revert `spec.yml`. | `.ruby-version`, `.claude/CLAUDE.md`, `.github/workflows/spec.yml`, `.github/workflows/test-add-compiler-matrix.yml`, `.github/workflows/test-add-compiler.yaml`, `.github/workflows/test-add-replica.yaml`, `.github/workflows/test-add-replica-matrix.yaml`, `.github/workflows/test-backup-restore.yaml`, `.github/workflows/test-backup-restore-migration.yaml`, `.github/workflows/test-failover.yaml`, `.github/workflows/test-fips-install-matrix.yaml`, `.github/workflows/test-install.yaml`, `.github/workflows/test-install-latest-dev.yaml`, `.github/workflows/test-install-latest-xlarge-dev-nightly.yaml`, `.github/workflows/test-install-matrix.yaml`, `.github/workflows/test-install-rhel-9.yaml`, `.github/workflows/test-legacy-compilers.yaml`, `.github/workflows/test-legacy-upgrade.yaml`, `.github/workflows/test-migration.yaml`, `.github/workflows/test-replace-failed-postgresql.yaml`, `.github/workflows/test-upgrade.yaml`, `.github/workflows/test-upgrade-latest-dev.yaml`, `.github/workflows/test-upgrade-latest-xlarge-dev-nightly.yaml`, `.github/workflows/test-upgrade-matrix.yaml`, `.github/workflows/test-upgrade-pg-major-ha-nightly.yaml` | None filed | | Related (supports testing) | The real `get-matrix` step was run locally and emits the Puppet 8 entry with Ruby 3.3; static checks pass | |

## Tickets that need filing

These changes fixed real defects that have no ticket. File one for each so the commit subject can carry its ID.

- P0-1: `peadm::convert` step name mismatch skips all steps on resume.
- P0-2: `peadm::upgrade` cannot resume at `preparation`, and resumed runs leave Puppet running.
- P0-3: `peadm::upgrade` has no early downgrade check (CASE-009 has no Jira ticket).

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
| P0-1 | `peadm::convert` step is named `modify-primary-certs`, matching `Peadm::ConvertSteps`. Before, `begin_at_step=modify-primary-certs` matched no step and skipped them all, including the A/B pin sanity check. | `plans/convert.pp`, `REFERENCE.md` | None filed. Related: PE-44017, PE-41637 (convert failures) | | None filed | Existing convert specs pass; no new spec yet | uncommitted |
| P0-2 | `preparation` is an allowed `begin_at_step` for `peadm::upgrade`. A run resumed at a later step stops Puppet on all infrastructure nodes, since the skipped `preparation` step was the only place that happened. | `plans/upgrade.pp`, `types/upgradesteps.pp`, `REFERENCE.md` | None filed. Related: PE-37220 (upgrade reports complete after failed step) | CASE-002, CASE-011 | None filed | Upgrade specs pass; no new spec for the resume path yet | uncommitted |
| P0-3 | `peadm::upgrade` fails right after reading the installed version when the target version is older, before anything is stopped. The message points to restoring from a backup. It does not catch the installer's release-date rule when the version number is higher. | `plans/upgrade.pp` | None filed | CASE-009 | None filed | `spec/plans/upgrade_spec.rb` (downgrade is refused) | uncommitted |
| P0-4 | New private task `peadm::verify_tarball` runs in `preparation` on the nodes that receive the installer, before Puppet or any PE service is stopped. It checks the file exists, is not empty, passes `gzip -t`, lists fully with `tar -tf`, and contains `puppet-enterprise-installer`. | `tasks/verify_tarball.sh`, `tasks/verify_tarball.json`, `plans/upgrade.pp` | PE-42686. Related: PE-43373 | CASE-049 | Mitigates PE-42686 (the extraction step already exited non-zero; this moves detection ahead of any service change) | `spec/plans/upgrade_spec.rb` (verified before stopping Puppet; corrupt tarball stops the plan). The shell script was run by hand against good, truncated, empty, wrong-layout and missing archives. | uncommitted |
| P0-5 | The legacy compiler OID check (`check_nodes_with_legacy_compiler_oid`) no longer counts nodes whose extension is `false`, because `peadm::convert` treats `false` as a modern compiler. Those nodes are listed as `ignored_nodes`. The failure message names the nodes and says to run `peadm::convert`. `peadm::upgrade` now includes that message instead of a bare "run the Convert plan". | `tasks/check_pe_master_rules.rb`, `plans/upgrade.pp` | GJira-17 | CASE-050 | Fixes GJira-17 | `spec/unit/task/check_pe_master_rules_spec.rb` (false is ignored, true blocks, message names the nodes), `spec/plans/upgrade_spec.rb` | uncommitted |
| P0-6 | `pe_install` prints the last 40 lines of the newest installer log and the status of failed `pe-*` units when the installer fails, so the Bolt failure explains itself. | `tasks/pe_install.sh` | GJira-1 | CASE-002, CASE-011 | Mitigates GJira-1 (diagnosability only; the reload failure itself is not fixed) | The log and unit report was run by hand with a fake log directory and a stub `systemctl`. No spec: the task needs a real installer. | uncommitted |

Not done in Phase 0: nothing outstanding. Items deferred by decision are in the plan file.

## Test scenario catalog

| ID | Change | Files | Jira | Cases | Relation | Tests | Commit |
|---|---|---|---|---|---|---|---|

Each scenario in `documentation/test-scenarios.md` lists its own source tickets and cases.

## Documentation

| ID | Change | Files | Jira | Cases | Relation | Tests | Commit |
|---|---|---|---|---|---|---|---|
| D-1 | This ledger. | `documentation/change-ledger.md` | | | | | uncommitted |

## Tickets that need filing

These changes fixed real defects that have no ticket. File one for each so the commit subject can carry its ID.

- P0-1: `peadm::convert` step name mismatch skips all steps on resume.
- P0-2: `peadm::upgrade` cannot resume at `preparation`, and resumed runs leave Puppet running.
- P0-3: `peadm::upgrade` has no early downgrade check (CASE-009 has no Jira ticket).

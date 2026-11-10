# Requirements: PEADM Modernization

**Defined:** 2026-11-10
**Core Value:** Installing, upgrading and operating a Puppet Enterprise installation of any size with PEADM must succeed predictably, and when it can't, it must fail early, explain itself, and be recoverable.

## v1 Requirements

Requirements for this release. Each maps to a roadmap phase. Evidence for each is in `.planning/research/` and `~/Code/peadm.csv`.

### Foundations and Diagnostics

- [ ] **FND-01**: Operator sees the underlying cause (log tail, failed units, exit code, sanitized) in the Bolt output whenever an installer or service-wrapping task fails
- [ ] **FND-02**: Operator can run peadm plans against non-`production` PE environments for install, backup, restore and migrate (clears PE-39789, PE-46598)
- [ ] **FND-03**: Operator gets one shared certificate, CRL and key validation (PEM and DER, RSA and EC, chains, expiry, empty subject) used by peadm tasks and by the CD4PE/SCM plans
- [ ] **FND-04**: Operator is told immediately when `begin_at_step` is not a valid step name for the plan, instead of every step being skipped
- [ ] **FND-05**: Operator's secrets never appear in plan output or diagnostics, checked by a spec that plants fake secrets
- [ ] **FND-06**: Maintainer has secret-file copies and temporary PE config written with restrictive permissions, replacing today's world-readable defects: `copy_file` writing every file 0644, `/tmp/pe.conf` left behind, and the RBAC token file following the umask
- [ ] **FND-07**: Maintainer has readiness waits with overridable deadlines instead of fixed timeouts, including the CA timeout

### Safe Upgrade

- [ ] **UPG-01**: Operator can run a read-only `peadm::preflight` for an upgrade and get BLOCK and WARN results before any service is touched
- [ ] **UPG-02**: Operator is warned by preflight about the known failure causes: installer release-date and upgrade-path refusal, eyaml empty-DN certificate, Code Manager SSH host keys, compiler version skew, duplicate A/B pins, legacy compiler OID, `node_manager` version, certificate and CRL expiry
- [ ] **UPG-03**: Operator gets preflight inside `peadm::upgrade` in warn-first mode for one release, then enforced for BLOCK results
- [ ] **UPG-04**: Operator can resume an upgrade at any step: the installer tarball is kept until the installer exits 0 and each step re-establishes its own preconditions
- [ ] **UPG-05**: Operator can tell that an upgrade truly succeeded: the plan fails unless every node reports the target version, infrastructure status is healthy and a zero-change Puppet run is clean
- [ ] **UPG-06**: Operator can see, after a failed or aborted upgrade, a documented list of leftovers (stopped services, stopped Puppet, symlinks, drop-ins) and have them cleaned up on failure
- [ ] **UPG-07**: Maintainer has a nightly job that runs the install and upgrade scenarios against the newest PE release and a process for adding a new PE line

### Recovery and Rollback

- [ ] **RCV-01**: Operator gets a recovery point (backup plus `recovery_point.json` manifest) created during upgrade preparation, before Puppet is stopped
- [ ] **RCV-02**: Operator can plug in a VM or storage snapshot through an operator-supplied hook plan, with no hypervisor code in the module
- [ ] **RCV-03**: Operator can run `peadm::rollback` that restores from the recovery point by rebuilding, never by installing an older PE version over the new one
- [ ] **RCV-04**: Operator is stopped by a backup gate from an upgrade that has no verified backup from the same run
- [ ] **RCV-05**: Operator has a documented rollback procedure that was run on real clusters for the backup-based and snapshot-based paths (scenarios R-01, R-02)
- [ ] **RCV-06**: Operator can back up and restore clusters that use database-backed CA, with CA backup and restore documented as such

### Failover and Node Operations

- [ ] **DR-01**: Operator can run `peadm::failover` for a planned role swap, staged as preflight, promote, reclassify, verify, then a separate rebuild plan
- [ ] **DR-02**: Operator can promote the replica when the primary is down, using explicit host parameters and certificate identity without querying the failed primary
- [ ] **DR-03**: Operator can repair duplicate or stale A/B availability-group pins after a role swap
- [ ] **DR-04**: Operator is told by failover readiness checks about CA and CRL mismatch, missing secret keys, SAN gaps, replication lag and RBAC token lifetime before promotion
- [ ] **DR-05**: Operator can replace a compiler, and `add_replica` and `add_compilers` fail unless the node is classified and reports healthy
- [ ] **DR-06**: Operator can replace a failed PostgreSQL node even when it is the primary's database host (PE-41341)
- [ ] **DR-07**: Operator can run the failover scenarios (F-01 to F-05) on a real DR cluster on at least two PE lines

### CD4PE and SCM

- [ ] **CDP-01**: Operator can run `peadm::cd4pe::prepare_pe` to create the PE-side prerequisites (RBAC account and token, CA trust and mTLS certificate, ports, classification)
- [ ] **CDP-02**: Operator can run a read-only `peadm::cd4pe::verify` that reports CD4PE health against the PE it is attached to
- [ ] **CDP-03**: Operator can supply CD4PE TLS inputs as file paths, with any key type and DER or PEM CRL, and is told when an input is unusable
- [ ] **CDP-04**: Operator can install CD4PE air-gapped with image integrity checked before upload, and with the database container confirmed before database configuration
- [ ] **CDP-05**: Operator can recover CD4PE after patching or a reboot with a documented plan that handles start order and waits
- [ ] **CDP-06**: Operator can export CD4PE project state and reattach a lost Bolt project
- [ ] **CDP-07**: Operator gets CD4PE preflights for host sizing, container runtime, `/tmp` mounted `noexec`, external PostgreSQL and the module versions with known regressions
- [ ] **SCM-01**: Operator can run `peadm::scm::prepare_pe` and a read-only `peadm::scm::verify` against a PE and an SCM host
- [ ] **SCM-02**: Maintainer has SCM scope, upgrade, backup and restore procedures agreed with the SCM owners and written down before any further SCM requirement is added
- [ ] **CDP-08**: Operator can have `peadm::upgrade` and `peadm::failover` call the CD4PE and SCM verify plans when a CD4PE or SCM host is given

### Toolchain and Compatibility

- [x] **TST-01**: Maintainer runs specs on current test gems (`puppetlabs_spec_helper` 9, `rspec-puppet` 5) with fixtures pinned to tags
- [x] **TST-02**: Maintainer knows whether peadm runs unchanged on Bolt 5.2 and Puppet Core 9, with a CI lane for Puppet 9 and a credentialed lane for Bolt 5
- [ ] **TST-03**: Operator can run peadm on PE 2026.0 and Puppet 9: `bootstrap.cfg` handling and RSA-only key parsing (`PKey.read`) are fixed. Per D-07 the `PKey.read` fix in Phase 1 is limited to `tasks/code_sync_status.rb`; the other RSA-only sites are recorded follow-ups. Widening the Puppet version range in `metadata.json` is deferred until the Puppet 9 lane is green (user decision during Phase 1 planning)
- [ ] **TST-04**: Maintainer has a first acceptance slice (install, upgrade n to n+1, injected failure and resume) before upgrade and failover code changes
- [x] **TST-05**: Maintainer has a stub-PATH harness so shell tasks can be tested without a real installer
- [ ] **TST-06**: Maintainer has the default PE version in `plans/install.pp` derived from `data/pe_versions.yaml` so they cannot drift

### Traceability

- [x] **TRC-01**: Maintainer has every change recorded in `documentation/change-ledger.md` with its ticket
- [ ] **TRC-02**: Maintainer has every fix recorded in `documentation/fix-log.md` with the complaint it addresses and how to reproduce and demonstrate the difference
- [ ] **TRC-03**: Maintainer has Jira tickets filed for the Phase 0 defects that have none (P0-1, P0-2, P0-3)

## v2 Requirements

Deferred to a future release. Tracked but not in the current roadmap.

### Upgrade and Operations

- **UPG-08**: Operator can run an unattended upgrade wrapper (check, backup, upgrade, verify, print rollback steps)
- **UPG-09**: Operator can run an upgrade dry run that lists steps, nodes and downtime estimate
- **UPG-10**: Operator can collect a support bundle on failure with secrets excluded
- **UPG-11**: Operator gets known-issue advisories bundled with version data
- **UPG-12**: Operator gets a bounded, signature-gated retry for the pe-puppetdb reload flake, only after GJira-1 is reproduced
- **DR-08**: Operator can run a role-swap exercise mode
- **FND-08**: Operator gets inventory generation and a run journal
- **INS-01**: Operator can bootstrap against an existing shared PE CA (CASE-044)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| In-place PE downgrade | The installer refuses it by release date (CASE-009); rollback is restore-based |
| Built-in VM or cloud snapshots | Handled through an operator hook plan; no hypervisor code in the module |
| Load-balancer repointing | Site-specific; belongs to the operator's hook plans |
| New work for PE older than 2023.8, and multi-hop upgrades from it | Out of scope per PROJECT.md; the existing `oldest: '2019.7'` is not tightened without an explicit decision |
| Non-Linux infrastructure nodes | Windows is only for agent helpers |
| Replacing Bolt, custom transports or a GUI | PEADM stays a Bolt plan and task module |
| Changing the internals of the CD4PE and SCM products | Only install, maintenance and PE-side integration are automated |
| Automatic fixes to customer repositories | Preflight reports; it does not edit customer code |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FND-01 | Phase 1 | Pending |
| FND-02 | Phase 1 | Pending |
| FND-03 | Phase 1 | Pending |
| FND-04 | Phase 1 | Pending |
| FND-05 | Phase 1 | Pending |
| FND-06 | Phase 1 | Pending |
| FND-07 | Phase 1 | Pending |
| TST-01 | Phase 1 | Complete |
| TST-02 | Phase 1 | Complete |
| TST-03 | Phase 1 | Pending |
| TST-04 | Phase 1 | Pending |
| TST-05 | Phase 1 | Complete |
| TST-06 | Phase 1 | Pending |
| TRC-01 | Phase 1 | Complete |
| TRC-02 | Phase 1 | Pending |
| TRC-03 | Phase 1 | Pending |
| UPG-01 | Phase 2 | Pending |
| UPG-02 | Phase 2 | Pending |
| UPG-03 | Phase 2 | Pending |
| UPG-04 | Phase 2 | Pending |
| UPG-05 | Phase 2 | Pending |
| UPG-06 | Phase 2 | Pending |
| UPG-07 | Phase 2 | Pending |
| RCV-01 | Phase 3 | Pending |
| RCV-02 | Phase 3 | Pending |
| RCV-03 | Phase 3 | Pending |
| RCV-04 | Phase 3 | Pending |
| RCV-05 | Phase 3 | Pending |
| RCV-06 | Phase 3 | Pending |
| DR-01 | Phase 4 | Pending |
| DR-02 | Phase 4 | Pending |
| DR-03 | Phase 4 | Pending |
| DR-04 | Phase 4 | Pending |
| DR-05 | Phase 4 | Pending |
| DR-06 | Phase 4 | Pending |
| DR-07 | Phase 4 | Pending |
| CDP-01 | Phase 5 | Pending |
| CDP-02 | Phase 5 | Pending |
| CDP-03 | Phase 5 | Pending |
| CDP-04 | Phase 5 | Pending |
| CDP-05 | Phase 5 | Pending |
| CDP-06 | Phase 5 | Pending |
| CDP-07 | Phase 5 | Pending |
| CDP-08 | Phase 5 | Pending |
| SCM-01 | Phase 5 | Pending |
| SCM-02 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 46 total
- Mapped to phases: 46
- Unmapped: 0 ✓

---
*Requirements defined: 2026-11-10*
*Last updated: 2026-11-10 after roadmap creation*

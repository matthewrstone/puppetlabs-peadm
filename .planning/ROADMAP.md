# Roadmap: PEADM Modernization

## Overview

PEADM already installs, upgrades and operates Puppet Enterprise at every size. This roadmap makes that work predictable, and recoverable when it is not. It starts with the shared pieces every later plan needs: failure diagnostics, one certificate helper, a modern test toolchain and a first acceptance slice. On top of that it builds, in dependency order, a safe upgrade (pre-flight, resume, verification), a recovery point with restore-based rollback, and failover with node replacement. It ends with CD4PE and SCM coordination, which adds PE-side prerequisites and verify hooks without forking the sibling modules. Phase 0 quick wins (branch `phase0-quick-wins`) are complete and logged in `documentation/change-ledger.md`; they are not repeated here, so numbering starts at 1.

Traceability requirements (TRC-01 to TRC-03) are mapped to Phase 1 where the practice is established, but they apply to every later phase: each change gets a ledger row and each fix a fix-log entry.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundations, Diagnostics and Test Baseline** - Shared failure reporting, certificate and environment helpers, current toolchain, first acceptance slice
- [ ] **Phase 2: Safe Upgrade** - Read-only preflight, resumable steps, verified success, cleanup on failure
- [ ] **Phase 3: Recovery Point and Rollback** - Backup gate, snapshot hook, restore-based rollback proven on real clusters
- [ ] **Phase 4: Failover and Node Operations** - Planned and unplanned failover, A/B pin repair, compiler and PostgreSQL replacement
- [ ] **Phase 5: CD4PE and SCM Coordination** - PE-side prerequisites, verify plans, air-gap and recovery hardening, upgrade and failover hooks

## Phase Details

### Phase 1: Foundations, Diagnostics and Test Baseline
**Goal**: Operators see why a plan failed, and maintainers have the shared helpers, current toolchain and a first acceptance slice that every later phase builds on
**Depends on**: Nothing (first phase)
**Requirements**: FND-01, FND-02, FND-03, FND-04, FND-05, FND-06, FND-07, TST-01, TST-02, TST-03, TST-04, TST-05, TST-06, TRC-01, TRC-02, TRC-03
**Success Criteria** (what must be TRUE):
  1. When an installer or service-wrapping task fails, the Bolt output shows the log tail, failed units and exit code, and a spec that plants fake secrets proves none of them appear in plan output or diagnostics
  2. Operator can run install, backup, restore and migrate against a PE whose environment is not `production`, and a `begin_at_step` value that is not a valid step name fails immediately with the valid names instead of skipping every step
  3. One shared certificate, CRL and key check accepts PEM and DER, RSA and EC and chains, and rejects expired certificates and empty subjects with a clear message; secret-file copies, `/tmp/pe.conf` and token files are written with restrictive modes; readiness waits, including the CA timeout, accept an overridable deadline
  4. Maintainer can run `rake spec` on current test gems with fixtures pinned to tags, test shell tasks through a stub-PATH harness without a real installer, and see a Puppet 9 CI lane and a credentialed Bolt 5 lane report whether peadm runs unchanged; PE 2026.0 and Puppet 9 fixes (`bootstrap.cfg`, `PKey.read`, `metadata.json` range) are in, and the default PE version in `plans/install.pp` is derived from `data/pe_versions.yaml`
  5. An acceptance run on a real cluster completes install, an n to n+1 upgrade, and an injected failure followed by resume; Jira tickets exist for P0-1 to P0-3; every change has a ledger entry and every fix a fix-log entry
**Plans**: 9 plans

Plans:
- [ ] 01-01-PLAN.md — Toolchain: puppetlabs_spec_helper 9 / rspec-puppet 5, tag-pinned fixtures, Ruby 3.3 floor, Puppet 9 and token-gated Bolt 5 lanes, metadata Puppet 9 range
- [ ] 01-02-PLAN.md — Stub-PATH shell-task harness and shared redacting failure report (pe_install, code_manager); P0-4/P0-6 checks as specs
- [ ] 01-03-PLAN.md — Overridable readiness deadlines (task, function, add_replica incl. CA wait, upgrade, convert) with timeout report
- [ ] 01-04-PLAN.md — Shared certificate/key/CRL checker with structured findings, validate_cert task, EC-safe code_sync_status
- [ ] 01-05-PLAN.md — Default PE version from data/pe_versions.yaml; begin_at_step validated before any remote call, step-name drift spec
- [ ] 01-06-PLAN.md — Install path: non-production environment, readiness deadline through install, /tmp/pe.conf 0600 and removed
- [ ] 01-07-PLAN.md — Backup/restore/restore_ca/migrate in non-production environments; restore deadline; shared CA backend detection
- [ ] 01-08-PLAN.md — Secret file copies 0600, token file 0600, planted-secret plan-output spec and signed-URL fix
- [ ] 01-09-PLAN.md — Acceptance slice (U-13) and node checks, real-cluster and CI runs, Jira P0-1..P0-3, ledger and fix-log close-out

### Phase 2: Safe Upgrade
**Goal**: An upgrade of any supported size is checked before anything is touched, can resume at any step, and reports success only when the cluster is verified healthy on the target version
**Depends on**: Phase 1
**Requirements**: UPG-01, UPG-02, UPG-03, UPG-04, UPG-05, UPG-06, UPG-07
**Success Criteria** (what must be TRUE):
  1. Operator can run `peadm::preflight` read-only for an upgrade and get BLOCK and WARN results before any service is touched, covering installer release-date and upgrade-path refusal, eyaml empty-DN certificate, Code Manager SSH host keys, compiler version skew, duplicate A/B pins, legacy compiler OID, `node_manager` version, and certificate and CRL expiry
  2. `peadm::upgrade` runs preflight itself: in its first release it warns on BLOCK results and continues, and in the following release it stops on them
  3. Operator can resume a failed upgrade at any step: the installer tarball is kept until the installer exits 0 and each step re-establishes its own preconditions, shown by injecting a failure at each step in acceptance
  4. The upgrade plan fails unless every node reports the target version, infrastructure status is healthy and a zero-change Puppet run is clean
  5. After a failed or aborted upgrade, the documented list of leftovers (stopped services, stopped Puppet, symlinks, drop-ins) is cleaned up automatically, and a nightly job runs the install and upgrade scenarios against the newest PE release with a written process for adding a new PE line
**Plans**: TBD

### Phase 3: Recovery Point and Rollback
**Goal**: An operator who cannot complete an upgrade has a verified recovery point and a tested way back, and no upgrade starts without one
**Depends on**: Phase 2
**Requirements**: RCV-01, RCV-02, RCV-03, RCV-04, RCV-05, RCV-06
**Success Criteria** (what must be TRUE):
  1. Upgrade preparation creates a recovery point (a backup plus a `recovery_point.json` manifest) before Puppet is stopped, and an upgrade with no verified backup from the same run is stopped by the backup gate
  2. Operator can plug a VM or storage snapshot into the recovery point through an operator-supplied hook plan, and the module contains no hypervisor code
  3. Operator can run `peadm::rollback` and it restores from the recovery point by rebuilding, and never installs an older PE version over the new one
  4. Operator can back up and restore a cluster that uses database-backed CA, and the documentation states how CA backup and restore work
  5. A documented rollback procedure has been run on real clusters for both the backup-based path (R-01) and the snapshot-based path (R-02)
**Plans**: TBD

### Phase 4: Failover and Node Operations
**Goal**: Operators can swap roles or promote the replica, and replace failed compilers and PostgreSQL nodes, with checks beforehand and verification afterwards
**Depends on**: Phase 2 (check infrastructure); independent of Phase 3, so the two can run in parallel
**Requirements**: DR-01, DR-02, DR-03, DR-04, DR-05, DR-06, DR-07
**Success Criteria** (what must be TRUE):
  1. Operator can run `peadm::failover` for a planned role swap, staged as preflight, promote, reclassify and verify, with rebuilding the old primary as a separate plan
  2. Operator can promote the replica while the primary is down, using explicit host parameters and certificate identity, and the plan never queries the failed primary
  3. Before promotion, readiness checks report CA and CRL mismatch, missing secret keys, SAN gaps, replication lag and RBAC token lifetime, and operator can repair duplicate or stale A/B availability-group pins after a role swap
  4. Operator can replace a compiler, `add_replica` and `add_compilers` fail unless the node is classified and reports healthy, and a failed PostgreSQL node can be replaced even when it is the primary's database host (PE-41341)
  5. The failover scenarios F-01 to F-05 have been run on a real DR cluster on at least two PE lines
**Plans**: TBD

### Phase 5: CD4PE and SCM Coordination
**Goal**: Operators can prepare PE for CD4PE and SCM, verify them against PE, and recover CD4PE from the failures that support cases report, without peadm forking the sibling modules
**Depends on**: Phase 1 (certificate helper); Phase 2 and Phase 4 for the upgrade and failover hooks (CDP-08)
**Requirements**: CDP-01, CDP-02, CDP-03, CDP-04, CDP-05, CDP-06, CDP-07, CDP-08, SCM-01, SCM-02
**Success Criteria** (what must be TRUE):
  1. Operator can run `peadm::cd4pe::prepare_pe` to create the PE-side prerequisites (RBAC account and token, CA trust and mTLS certificate, ports, classification) and a read-only `peadm::cd4pe::verify` that reports CD4PE health against the PE it is attached to
  2. Operator can supply CD4PE TLS inputs as file paths with any key type and a DER or PEM CRL, is told when an input is unusable, and gets preflight warnings for host sizing, container runtime, `/tmp` mounted `noexec`, external PostgreSQL and module versions with known regressions
  3. Operator can install CD4PE air-gapped with image integrity checked before upload and the database container confirmed before database configuration
  4. Operator can recover CD4PE after patching or a reboot using a documented plan that handles start order and waits, and can export CD4PE project state and reattach a lost Bolt project
  5. Operator can run `peadm::scm::prepare_pe` and a read-only `peadm::scm::verify`, SCM scope, upgrade, backup and restore procedures are written down with the SCM owners, and `peadm::upgrade` and `peadm::failover` call the CD4PE and SCM verify plans when a CD4PE or SCM host is given
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5. Phase 4 does not need Phase 3 and can run alongside it. Phase 5 is largely independent of PE core work; only its upgrade and failover hooks (CDP-08) need Phases 2 and 4.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundations, Diagnostics and Test Baseline | 0/9 | Planned | - |
| 2. Safe Upgrade | 0/TBD | Not started | - |
| 3. Recovery Point and Rollback | 0/TBD | Not started | - |
| 4. Failover and Node Operations | 0/TBD | Not started | - |
| 5. CD4PE and SCM Coordination | 0/TBD | Not started | - |

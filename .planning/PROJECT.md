# PEADM Modernization

## What This Is

PEADM (`puppetlabs-peadm`) is a Bolt-based automation module that installs, upgrades and maintains Puppet Enterprise at every size (standard, large, extra-large, with or without DR replica and external PostgreSQL). This effort continues modernizing it into a painless automation kit for the full lifecycle of a Puppet installation, and extends it to cover Continuous Delivery for PE (CD4PE) and Secure Compliance Management (SCM).

## Core Value

Installing, upgrading and operating a Puppet Enterprise installation of any size with PEADM must succeed predictably, and when it can't, it must fail early, explain itself, and be recoverable.

## Requirements

### Validated

<!-- Inferred from the existing codebase map (.planning/codebase/) and Phase 0 work on this branch. -->

- ✓ Greenfield install for standard, large and extra-large architectures with optional DR, cloud database, Code Manager and LDAP (`peadm::install`) — existing
- ✓ Step-resumable upgrade via `peadm::plan_step` and `begin_at_step` (`peadm::upgrade`) — existing
- ✓ Adopt an existing PE cluster (`peadm::convert`) — existing
- ✓ Topology operations: add compilers, replica and database nodes, replace failed PostgreSQL, migrate, uninstall — existing
- ✓ Backup and restore of PE and CA, certificate and extension management, `peadm::status` health report — existing
- ✓ Supported PE range is data-driven (`data/pe_versions.yaml`) with a clear unsupported-version error — Phase 0 (PE-47850)
- ✓ Upgrade fails early on downgrade, verifies the installer tarball before stopping services, resumes safely at `preparation`, and reports installer log and failed services on failure — Phase 0
- ✓ Catalog of 29 install/upgrade/rollback/failover test scenarios (`spec/acceptance/scenarios.yaml`) — Phase 0

### Active

- [ ] Safe upgrades: pre-flight and health checks run before any service is touched, every long plan is resumable, and a failed upgrade has a documented, tested rollback path
- [ ] Clear diagnostics: failures surface the underlying cause (installer log, failed units, cert/CRL state) in the Bolt output instead of a bare exit code
- [ ] Safe failover and day-2 operations: role swap and DR promotion, replica rebuild and compiler replacement are automated, checked beforehand, and tested
- [ ] Install and upgrade work reliably across sizes and the supported OS set, including air-gapped installs
- [ ] CD4PE: automated install (including air-gapped), upgrade, patching/restart recovery and Bolt project reattach
- [ ] SCM: automated install and maintenance of Secure Compliance Management
- [ ] Each change is traceable to its support case or Jira ticket in `documentation/change-ledger.md`
- [ ] Acceptance coverage per topology, driven by the scenario catalog, on top of unit specs

### Out of Scope

- New work or test coverage for PE older than 2023.8 — the effort targets current lines; the existing `oldest: '2019.7'` in `data/pe_versions.yaml` is not tightened without an explicit decision
- Non-Linux infrastructure nodes — Windows is only for agent helpers, not primary/replica/compiler/database nodes
- Replacing Bolt — PEADM stays a Bolt plan and task module with no new orchestrator or UI
- Changing the internals of CD4PE or SCM — PEADM automates their install and maintenance only

## Context

- Brownfield: version 3.40.0 of `puppetlabs-peadm`, supported PE 2019.7 to 2026.0, Bolt >= 4, Puppet 8. See `.planning/codebase/` for the full map.
- Pain evidence: `~/Code/peadm.csv` holds 50 anonymized support cases and 52 Jira tickets. Clusters are upgrade failures (pe-puppetdb reload, CRL/SSL, failure partway, missing tarball), no rollback path, weak pre-flight/health checks, replica/compiler/DR operations, and CD4PE (airgap install, patching, stuck pipelines, webhooks over http).
- Phase 0 quick wins (branch `phase0-quick-wins`) are done and logged in `documentation/change-ledger.md`; later work builds on them.
- Known tech debt from the map: hardcoded default PE version in `plans/install.pp`, duplicated subplan parameter lists, deprecated `add_compiler` wrapper, legacy GitLab CI Ruby entries.
- Some Phase 0 defects have no Jira ticket yet (P0-1 to P0-3); the ledger lists them as needing filing.

## Constraints

- **Tech stack**: Puppet DSL plans, Ruby/Bash tasks, Bolt-driven — keeps PEADM installable from the Forge and usable by existing operators
- **Compatibility**: Existing public plan names and parameters keep working; deprecations go through a warning period — customers run PEADM in production
- **Validation**: rspec unit tests plus acceptance runs against real provisioned clusters per topology — failures here hit production Puppet infrastructure
- **Traceability**: Every change logged in the change ledger with its ticket, and commit subjects start with the ticket ID

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Phase the work: safe upgrades and failover first, then CD4PE/SCM and the rest of the lifecycle | Upgrade and failover failures are the largest source of cases | — Pending |
| Stay a Bolt module | Bolt is the established operator interface | — Pending |
| Validate with unit plus acceptance tests | Unit specs can't prove installer, service and cluster behavior | — Pending |
| Read the supported PE range from data, not code | One place to bump per new PE line | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-11-10 after initialization*

# Project Research Summary

**Project:** PEADM Modernization (safe upgrades, failover/day-2, CD4PE and SCM automation)
**Domain:** Bolt-module lifecycle automation for Puppet Enterprise (install, upgrade, rollback, failover, day-2), plus CD4PE and Secure Compliance Management (SCM)
**Researched:** 2026-11-10
**Confidence:** MEDIUM-HIGH

## Executive Summary

peadm is a production Bolt module (3.40.0) that orchestrates PE across all topologies. Comparable lifecycle tools (Satellite `satellite-maintain`, `kubeadm`) share one shape: a read-only check, a verified backup, a resumable upgrade, then a post-condition gate. peadm has resumable steps (`plan_step`) and some fixes from Phase 0, but no check mode, no verification gate, no rollback and no failover plan. The support evidence (50 cases, 52 Jira tickets) points at the same three gaps. Customers use support as their pre-flight, find no rollback when they need one, and stop trusting "success" because plans exit 0 while the system is unhealthy.

Recommended approach: build shared contracts first (a `CheckResult` type, a failure-report shape, a sanitizer, one TLS/cert helper, one non-`production` environment helper, `plan_step` validation). Then layer a single `peadm::preflight` check catalog, a post-upgrade verification gate, a recovery point with restore-based rollback, and a separate `peadm::failover` plan on top. Rollback is never an in-place downgrade, because the PE installer refuses downgrades. Snapshots and load balancers plug in through operator hook plans. CD4PE and SCM stay in the premium sibling modules (`cd4peadm`, `complyadm`). peadm adds only PE-side prerequisites, version-compat verification and pre/post checks, with no `metadata.json` dependency on either.

Key risks: (1) success without a post-condition check, (2) resume that does not rebuild the preconditions a failed run destroyed (the tarball is deleted before the installer exits 0), (3) pre-flight that tests connectivity but not the conditions that actually fail, (4) failover built as "promote then add the old primary back", and (5) mock-heavy unit tests giving false confidence for a stateful, destructive domain. The stack also has drift that must be handled early. Bolt 5.x is licence-gated and the public gem stops at 4.0.0. Puppet 9 and PE 2026.0 change CA storage, `bootstrap.cfg` and key parsing. The test gems are one major version behind. SCM has almost no field evidence, so scope it as a narrow wrapper and treat it as P3 until the product team scopes it.

## Key Findings

### Recommended Stack

The existing Bolt/Puppet DSL/task architecture stays (a PROJECT.md decision). What changes is the toolchain around it and how peadm relates to CD4PE and SCM. Full detail: `.planning/research/STACK.md`.

**Core technologies:**
- Bolt 5.2.x (OS package, operators) and Bolt 4.0.0 gem (unit specs and Litmus CI): 5.x is credential-gated, so keep the last public gem for CI and add a credentialed lane for the real jumphost path.
- Puppet language requirement `>= 8.0.0 < 10.0.0`: PE 2026.0 supports Puppet 9. Bolt range `>= 3.17.0 < 6.0.0` already admits 5.x.
- `peadm::plan_step` and `data/pe_versions.yaml` (kept): resumability and version ranges stay data-driven. No external state store.
- `puppetlabs/cd4peadm` 5.19.0 and `puppetlabs/complyadm` 3.9.1: wrap with `run_plan` from a separate Bolt project, never fork. They are premium, token-gated and container-based.
- `puppet_status_check` 0.10.0 (or bundled `pe_status_check`): reuse its health indicators. Which one ships on each supported PE line is unverified.
- Test stack: `puppetlabs_spec_helper ~> 9.0`, `rspec-puppet ~> 5.0`, `rspec-puppet-facts ~> 6.3`, `puppet_litmus ~> 2.8`, `BoltSpec::Plans`. Pin `.fixtures.yml` to tags and add a Puppet 9 / Ruby 4 lane.
- Target PE test lines: 2023.8.x (overlap support ends 2027-02-27), 2025.12.1, 2026.0.1. Update stale `metadata.json` OS entries (needs an explicit decision).

**Puppet 9 / PE 2026 items to fix in peadm itself:** `OpenSSL::PKey::RSA.new` in `tasks/code_sync_status.rb` (use `PKey.read`), `bootstrap.cfg` reads in `plans/backup.pp` and `plans/restore.pp`, database-backed CA in backup/restore, and `metadata.json` `puppet < 9.0.0`. Also align `plans/install.pp` default version with `data/pe_versions.yaml`.

### Expected Features

Full detail: `.planning/research/FEATURES.md`.

**Must have (table stakes):**
- Shared foundations (non-`production` environment helper, TLS helper, parameter summary, `plan_step` step-name validation, cleanup-on-failure). Clears two Blocker tickets (PE-39789, PE-46598) and is a prerequisite for everything else.
- `peadm::preflight` / check mode (upgrade first, then promote and add_replica), with incident-derived checks (eyaml empty DN, r10k host keys, A/B pins, legacy OID, `node_manager` version, release-date rule).
- Post-upgrade verification gate and whole-cluster version assertion that changes the plan's exit status.
- Failure diagnostics on every installer/service-wrapping task (log tail, failed units, exit code), sanitized.
- Backup gate and a tested, documented rollback procedure (R-01 backup-based, R-02 snapshot via hook).
- Planned role swap with readiness checks, then unplanned promotion; compiler replace and A/B pin repair.
- CD4PE hardening: TLS inputs (any key type, DER/PEM CRL, file paths), air-gap image integrity, DB-container check, recovery after patching.
- New-PE-release readiness as a recurring process (nightly job against newest PE).

**Should have (competitive):**
- Unattended CI-driven upgrade wrapper (check, backup, upgrade, verify, print rollback steps). Falls out of the table stakes.
- Upgrade dry-run (step list, nodes, downtime estimate).
- Support bundle on failure, secrets excluded.
- Known-issues advisories bundled with version data.
- Known-flake bounded retry (needs research; GJira-1).

**Defer (v2+):**
- Role swap exercise mode, shared-CA bootstrap, inventory generation, run journal.
- SCM beyond "optional install at end of CD4PE install" until scoped with the SCM owners.
- Anti-features: real downgrade, built-in VM/cloud snapshot, load-balancer repointing, custom Bolt transports, automatic fixes to customer repos, pre-2023.8 multi-hop upgrades, a GUI.

### Architecture Approach

New capability attaches to the existing layering (public plans, private subplans, util plans, tasks, PE as the sole state store) through additive components. Nothing is renamed and no public parameter is removed. Full detail: `.planning/research/ARCHITECTURE.md`.

**Major components:**
1. `peadm::preflight` plus `subplans::run_preflight`: one check catalog with a `CheckResult` contract (BLOCK/WARN severity), grouped tasks per domain (`preflight_host/pe/certs/cluster`), data in `known_issues.yaml` and `check_thresholds.yaml`.
2. `subplans::recovery_point` plus `peadm::rollback`: backup plus an on-disk manifest (`recovery_point.json`) beside `peadm_config.json`. Rollback is a restore-based rebuild, resumable, with a hook plan (`util::hook_dispatch`) for snapshots.
3. `peadm::failover` (planned and unplanned): explicit host params, identity read from cert OIDs, never calls `get_peadm_config` against the failed primary. It re-asserts classifier pins while A/B letters stay with the hosts.
4. `util::collect_diagnostics` plus `peadm::failure_report`: cross-cutting failure evidence at the plan boundary, sanitized with `sanitize_log_text`.
5. `peadm::cd4pe::*` and `peadm::scm::*`: thin plans for PE-side prerequisites (RBAC account, CA trust, mTLS cert, ports) and `verify` hooks called from upgrade and failover. Soft dependency on sibling modules, no `metadata.json` entry.

**Key patterns:** always-run guards stay outside `plan_step`, while health checks live in a skippable `preflight` step (resume-safe). Step results persist to the manifest or are re-derived, never carried in plan variables. Add new parameters only where needed and add a forwarding spec for each. Do not vendor cd4peadm/complyadm logic.

### Critical Pitfalls

Top five of 21. Full detail: `.planning/research/PITFALLS.md`.

1. **Success without a post-condition (Pitfall 1)**: build one shared verification library first (P-DIAG): infra status, all node versions equal, canary compile, zero-change Puppet run, classifier membership after add/replace. Wrapper tasks must exit non-zero on inner failure. Validate `begin_at_step`.
2. **Resume without re-establishing preconditions (Pitfall 2)**: `pe_install.sh` deletes the tarball before the installer exits 0, and cleanup only happens on the happy path. Each step re-asserts its own preconditions, with `trap`/ensure-style cleanup. Acceptance must resume from every step. This precedes any rollback work.
3. **Shallow pre-flight (Pitfall 3)**: run pre-flight before anything is stopped, as a data-driven table of named checks tied to cases. Include the release-date rule (CASE-009), eyaml DN, topology sanity and cert/CRL expiry. Separate BLOCK from WARN to avoid false-positive blockers on production.
4. **Rollback as "upgrade with an older version" (Pitfall 4)**: the installer refuses it. Implement tiers: abort-and-recover, roll-forward (primary path), then restore-based rollback gated on a verified same-run backup. Never ship it without an acceptance run on a real cluster.
5. **Failover as "promote, then add old primary back" (Pitfall 9)**: stage it (preflight, promote, reclassify, verify, rebuild as separate invocations). Update A/B pins in the same plan, and check replication lag, SANs and secret keys. Fix the 0644 `copy_file` mode defect first.

Also carry forward: reproduce the pe-puppetdb reload failure (GJira-1) before any fix (Pitfall 7). Mock-heavy specs give false confidence (Pitfall 21). CD4PE restart/patching and Bolt-project loss (Pitfalls 16-18) are the best-evidenced CD4PE failure classes. Secrets in logs (Pitfall 14) get worse as diagnostics expand.

## Implications for Roadmap

Phase 0 quick wins (branch `phase0-quick-wins`) are already done or in progress. The suggested phases follow the architecture build order and the pitfall-to-phase mapping.

### Phase 1: Foundations, Diagnostics and First Acceptance Slice
**Rationale:** Everything else consumes these. Pitfalls 1, 5, 6, 11 and 14 are all shared-library problems, and building them once avoids per-plan copies. The cheapest visible win (named failure causes) lands here. The acceptance slice must exist before upgrade/DR code changes (Pitfall 21).
**Delivers:** `CheckResult`, `preflight_report`, `failure_report`, `collect_diagnostics`, sanitizer with a fake-secret spec, shared cert/CRL/key helper, non-`production` environment helper (clears PE-39789, PE-46598), `plan_step` validation, parameter summary, readiness-wait helper with overridable deadlines, fixes for the three known permission defects (`copy_file` mode, `/tmp/pe.conf`, token mode), stub-PATH harness for shell tasks. Acceptance: standard install, upgrade n to n+1, injected-failure and resume scenario.
**Addresses:** shared foundations, diagnostics, failure evidence.
**Avoids:** Pitfalls 1, 5, 6, 11, 14, 21.
**Stack:** `puppetlabs_spec_helper` 9 and spec gem bumps, fixtures pinned to tags, `BoltSpec::Plans`, Puppet 9 compatibility fixes (`PKey.read`, `bootstrap.cfg`).

### Phase 2: Safe Upgrade (Pre-flight, Resume, Verification)
**Rationale:** The core value is "succeed predictably, otherwise fail early and be recoverable". Resume correctness must precede rollback because rollback depends on knowing what state a failure leaves.
**Delivers:** `peadm::preflight` plus `run_preflight` wired into `upgrade` (warn-first for one release, then enforce BLOCK), incident-derived checks and `known_issues.yaml`, idempotent re-entrant steps (keep tarball until exit 0, cleanup traps), post-upgrade verification gate and version table, version-support tiers and nightly newest-PE job, `metadata.json` / Puppet 9 / OS list update, offline artifact check for PE.
**Addresses:** check mode, known-risk checks, verification gate, whole-cluster assertion, new-release process, PE air-gap.
**Avoids:** Pitfalls 2, 3, 12, 13, 15 (PE side).
**Implements:** `preflight`, `run_preflight`, `Peadm::UpgradeSteps` `preflight` step.

### Phase 3: Recovery Point and Rollback
**Rationale:** Needs resumable steps and diagnostics (Phases 1-2), and cannot be tested without a manifest to consume.
**Delivers:** `recovery_point` (opt-in parameter, default flip after one deprecation cycle), `hook_dispatch` with an example snapshot plan, `peadm::rollback` (tiers 1 and 2 first, tier 3 restore-based), backup gate, `peadm::backup`/`restore` fixes for non-production environments, DB-backed CA detection, restore version check, documented rollback procedure. Acceptance R-01 and R-02 run for real.
**Addresses:** backup gate, rollback procedure, restore for realistic shapes, unattended upgrade wrapper (differentiator, falls out here).
**Avoids:** Pitfall 4, and the Pitfall 7 mitigation only after reproduction.

### Phase 4: Failover, Role Swap and Node Replacement
**Rationale:** Independent of Phase 3, so it can run in parallel if staffed. Depends on the Phase 1-2 check infrastructure and the permission fixes. It needs a real DR cluster, not just specs.
**Delivers:** `peadm::failover` (planned, unplanned, staged), `promote_replica` task, A/B pin repair (`repair_ab_pins`), compiler replace, replica post-conditions (classification, `infra status`, streaming), `replace_failed_postgresql` fix for failed equals primary host, failover readiness checks (CA/CRL match, secret keys, SANs, lag, RBAC TTL), drift fixtures (duplicate A pin, legacy compilers, non-production env, post role swap), configurable `ca_timeout`. Acceptance F-01 to F-05, run on two PE lines.
**Addresses:** role swap, unplanned promotion, compiler/replica/DB operations.
**Avoids:** Pitfalls 8, 9, 10.

### Phase 5: CD4PE and SCM Coordination
**Rationale:** Largely independent of PE core work and can start earlier in parallel, but the hooks into upgrade/failover need Phases 2 and 4. Scope is gated on the decision whether the team can change `cd4peadm`/`complyadm`.
**Delivers:** `peadm::cd4pe::prepare_pe` / `verify`, `peadm::scm::prepare_pe` / `verify`, optional `cd4pe_host` / `scm_host` hooks in `upgrade` and `failover`, CD4PE preflights (host sizing, runtime, `/tmp` noexec, external PG, `cd4pe_jobs` >= 1.7.4), air-gap image checksum pattern, offline bundle manifest, post-patching recovery and status plan, project-state export and reattach research, webhook scheme and trust-store checks. If the sibling modules are not changeable: pre/post checks and documented workarounds only, with the limit stated in the roadmap.
**Addresses:** CD4PE hardening, SCM wrapper (narrow).
**Avoids:** Pitfalls 15 (CD4PE), 16, 17, 18, 19, 20.

### Phase Ordering Rationale

- Contracts and shared libraries come first because the same failure classes (success lies, cert strings, raw logs, fixed timeouts) recur in every later phase.
- Resume comes before rollback, and pre-flight before enforcement. Pre-flight runs before anything is stopped.
- Failover is independent of rollback but needs the same check registry, so it can run in parallel with Phase 3.
- CD4PE/SCM comes last in dependency order but is a parallel track in practice. Its cheapest, best-evidenced items (TLS inputs, air-gap integrity, DB-container check) can ship earlier if access to `cd4peadm` exists.
- Convert, migrate and install pre-flight should wait until after Phase 2 to avoid widening the test surface now.

### Research Flags

Phases likely needing deeper research (`/gsd-plan-phase --research-phase <N>`):
- **Phase 2:** the pe-puppetdb reload flake (GJira-1, open Blocker, reproduce before fixing), the installer release-date rule and upgrade-path rules (CASE-009, 039), and `puppet_status_check` vs `pe_status_check` availability per PE line.
- **Phase 3:** PE restore compatibility and schema-migration reversibility, XL backup size and duration, and `peadm::restore` behaviour across mixed-version nodes.
- **Phase 4:** A/B state after promote on 2023.8 vs 2025.x, `promote` with the primary cleanly stopped versus failed, and whether PE-39742's DR work shipped elsewhere. Needs a real DR cluster.
- **Phase 5:** what runtime state of a CD4PE instance can seed a reattach, vendor SCM upgrade/backup procedures, whether CD4PE/SCM backup already exists in the sibling modules, and a Bolt "plan exists" check for the soft dependency.

Phases with standard patterns (skip research-phase):
- **Phase 1:** well-understood shared-library and spec-harness work, plus known Puppet 9 fixes. Only the Bolt 5 CI-credential question needs a spike.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Versions and lifecycle dates verified against RubyGems, Forge API and vendor docs. Bolt 5 availability in CI, Puppet 9 behaviour of the unchanged module, and `node_manager`/`format` compatibility are untested. |
| Features | MEDIUM-HIGH | User need is HIGH (50 cases and 52 tickets read in full). Comparison with other lifecycle tools is MEDIUM. SCM need is LOW (one reference). No outcome data in the CSV. |
| Architecture | MEDIUM-HIGH | Attachment to existing code is HIGH (read from the repo). The cd4peadm/complyadm boundary is MEDIUM (source not readable). A few Bolt mechanics are LOW. |
| Pitfalls | MEDIUM-HIGH | Failure classes are HIGH (cases verified against code). Root causes inside PE core, CD4PE containers and SCM are marked as inference. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Can the team change `cd4peadm` / `complyadm`?** Gates Phase 5 scope. Ask the project owner before requirements are written. If no, do not mark CD4PE automated install, patching recovery or reattach as deliverable from peadm alone.
- **Where do CI and Litmus get a Bolt 5 binary?** Spike with a Puppet Core token against `rubygems-puppetcore.puppet.com`. Plan on the Bolt 4.0.0 gem until proven otherwise.
- **Does peadm run unchanged on Bolt 5.2 and Puppet Core 9?** Run `rake spec` plus one `status` and one `upgrade` acceptance on PE 2026.0.1 early in Phase 1.
- **`puppet_status_check` / `pe_status_check` availability** on 2023.8.13, 2025.12.1 and 2026.0.1, and the fact name to read. Fall back to the `infrastatus.sh` that `peadm::status` already uses.
- **Promote/failover code history:** PE-39742 is Closed but `plans/` has no promote or swap plan. Check before designing Phase 4.
- **GJira-1 root cause:** unknown. A retry is only justified after reproduction, and it must be signature-gated and logged.
- **Support-floor decision:** keep `oldest: '2019.7'` and the stale `metadata.json` OS entries, or tighten them. Out of scope without an explicit decision, but they conflict with the vendor lifecycle.
- **SCM scope:** almost no evidence. Talk to the SCM team before any requirement beyond "wrap, pre-flight, verify".
- **CD4PE host OS gap:** cd4peadm docs do not list EL 10 or Ubuntu 26.04. Do not promise them in preflights.
- **No outcome data:** priorities are by frequency and severity of complaints, not measured impact.

## Sources

### Primary (HIGH confidence)
- Bolt release notes, install and plan-language docs (help.puppet.com/bolt): Bolt 5.x licence gating, no native resume.
- RubyGems API and Forge API (queried 2026-11-10): gem and module versions and `puppet` requirements.
- puppetlabs_spec_helper and puppet_litmus changelogs; PDK 4.0 release notes; Puppet 8 to 9 upgrade guide; PE 2026.0 release notes; PE support lifecycle.
- CD and SCM install, air-gapped, system-requirements and upgrade docs (help.puppet.com/cdpe, /scm).
- Local repo: `plans/`, `tasks/`, `lib/puppet/functions/peadm/plan_step.rb`, `Gemfile`, `metadata.json`, `.planning/codebase/*`, `documentation/change-ledger.md`, `fix-log.md`, `test-scenarios.md`, `spec/acceptance/scenarios.yaml`.
- `~/Code/peadm.csv`: 50 support cases and 52 Jira tickets, HIGH for symptoms.

### Secondary (MEDIUM confidence)
- `pe_status_check` docs (PE 2023.8) and PE operational-status pages; Red Hat Satellite and `foreman_maintain` docs.
- PE what's new page (security release summary); puppetlabs modules roundup, August 2026.
- SCM 3.x install page (summarized fetch); Forge listings for cd4peadm.

### Tertiary (LOW confidence)
- kubeadm, GitLab, Elastic and OpenShift upgrade behaviour from background knowledge, not re-verified.
- Root causes for CD4PE container, SCM and PE-core failures (marked `[INFER]` in PITFALLS.md), needing reproduction.
- Whether `rubygems-puppetcore.puppet.com` hosts a `bolt` gem (401 without a token).

---
*Research completed: 2026-11-10*
*Ready for roadmap: yes*

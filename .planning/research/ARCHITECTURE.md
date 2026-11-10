# Architecture Research

**Domain:** Bolt-module automation for Puppet Enterprise lifecycle (install, upgrade, rollback, failover), plus CD4PE and Secure Compliance Management (SCM)
**Researched:** 2026-11-10
**Confidence:** MEDIUM-HIGH. HIGH for how new capabilities attach to the existing peadm code (read from the repo). MEDIUM for the CD4PE/SCM boundary (the `cd4peadm` source is a premium Forge module and was not readable; `complyadm` and CD4PE behavior come from vendor docs and support-case logs). LOW on a few Bolt mechanics flagged under "Open Questions".

## Decisions at a Glance

| # | Decision | Why |
|---|----------|-----|
| D1 | Pre-flight is one **check catalog** (a result contract plus grouped node tasks and controller-side functions), exposed as a public read-only plan `peadm::preflight` and called by `upgrade`, `failover` and `rollback`. It is not scattered `fail()` calls. | The same checks are needed standalone (before a maintenance window) and inline. One contract means one place to add a check when a release breaks something. |
| D2 | Pre-flight in `upgrade` runs **outside `plan_step`** for the always-valid guards, and as a skippable first step for cluster-health checks. | A resumed run has services stopped, so health checks would fail on purpose. Phase 0 (P0-2) already hit the "state lived only in a skipped step" bug class. |
| D3 | Rollback = **recovery point + restore-based rebuild**, never an in-place downgrade. A `peadm::recovery_point` subplan creates it during `preparation`; `peadm::rollback` consumes it. Hypervisor snapshots plug in through a **hook plan**, not module code. | PE does not support downgrade. The module already has backup, restore, uninstall and add_replica to build on. VM snapshots are infrastructure-specific and stay out of the module. |
| D4 | Failover is a new public plan `peadm::failover` (planned and unplanned modes) that **must not depend on `get_peadm_config` against the failed primary**, and must leave node-group pins and cert OIDs consistent so discovery works afterward. | `get_peadm_config` reads the classifier and PuppetDB on the primary, which is the node that is down in the unplanned case. |
| D5 | **CD4PE and SCM install engines stay in the sibling modules `cd4peadm` and `complyadm`.** peadm gets only (a) PE-side prerequisites and (b) lifecycle coordination plans under `peadm::cd4pe::*` and `peadm::scm::*`, with **no entry in `metadata.json` dependencies**. | Those modules are premium, versioned to the application, keep state in a Bolt project (not in PE), and install on hosts that are not PE nodes. Hard-coupling would break Forge installability and PEADM's "PE is the state store" model. |
| D6 | Diagnostics are a **cross-cutting wrapper**, not per-plan code: a `peadm::diagnose` util plus a shared failure-report shape. | Failures surface as bare exit codes today. Every other component (preflight, rollback, failover) needs the same evidence collection. |

## Standard Architecture

### System Overview

New components are marked `[NEW]`; changed ones `[CHG]`. Everything else exists today.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Bolt CLI / Bolt project (operator)                      │
└──────┬─────────────────────────────────────────────────────────┬────────────┘
       │ public plans                                             │ direct tasks
       ▼                                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PUBLIC PLANS  plans/*.pp                                                      │
│  install  upgrade[CHG]  convert  add_*  backup  restore  status  uninstall    │
│  preflight[NEW]  rollback[NEW]  failover[NEW]  diagnose[NEW, read-only]        │
│  cd4pe/*[NEW, thin]  scm/*[NEW, thin]                                          │
└──────┬─────────────────────────────┬──────────────────────────┬──────────────┘
       │ run_plan                    │ run_plan                 │ run_plan (soft dep)
       ▼                             ▼                          ▼
┌───────────────────────┐  ┌──────────────────────────┐  ┌───────────────────────────┐
│ SUBPLANS (private)     │  │ UTIL PLANS                │  │ SIBLING MODULES            │
│ install, configure,    │  │ update_classification     │  │ puppetlabs-cd4peadm        │
│ component_install...   │  │ copy_file, db_*,          │  │ puppetlabs-complyadm       │
│ recovery_point[NEW]    │  │ code_sync_status          │  │ (premium Forge, own Bolt   │
│ run_preflight[NEW]     │  │ collect_diagnostics[NEW]  │  │  project + Hiera state)    │
│ promote_replica[NEW]   │  │ hook_dispatch[NEW]        │  └───────────────────────────┘
└──────┬────────────────┘  └────────────┬─────────────┘
       │                                │
       ▼                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ SHARED LOGIC                                                                  │
│  functions/: assert_* (existing)  preflight_report[NEW]  failure_report[NEW]   │
│  types/: CheckResult[NEW] RollbackSteps[NEW] FailoverSteps[NEW] UpgradeSteps[CHG]│
│  lib/puppet/functions/peadm/plan_step.rb (unchanged contract)                  │
│  data/: pe_versions.yaml  known_issues.yaml[NEW]  check_thresholds.yaml[NEW]    │
└──────┬──────────────────────────────────────────────────────────────────────┘
       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ TASKS tasks/  (node side, JSON on stdout)                                      │
│  existing: get_peadm_config cert_data read_file pe_install puppet_runonce ...   │
│  [NEW] preflight_host  preflight_pe  preflight_certs  preflight_cluster         │
│  [NEW] collect_diagnostics  promote_replica  recovery_manifest                  │
└──────┬──────────────────────────────────────────────────────────────────────┘
       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PE ITSELF = the state store (no PEADM state of its own)                        │
│  classifier groups (pins)  cert OID extensions  pe.conf  PuppetDB  PostgreSQL   │
│  backup tarballs (recovery points)  installer logs  systemd units               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| `peadm::preflight` (public) | Run the check catalog for a named operation (`upgrade`, `failover`, `rollback`, `install`) against the discovered or supplied topology and return a structured report. Read-only: never stops a service. | Plan. Resolves topology like `status` does, fans tasks out per node role, folds results with `peadm::preflight_report`. |
| `peadm::subplans::run_preflight` (private) | The call site used by other plans: runs `peadm::preflight`, applies severity policy (`blocker` fails, `warning` prints), honors the skip list. | Subplan so `upgrade`, `failover`, `rollback` share policy. |
| Check tasks (`preflight_host/pe/certs/cluster`) | Gather facts and return `Array[CheckResult]` JSON per node. Grouped by domain, not one task per check, to limit Bolt round trips on XL clusters. | Ruby tasks on PE's Ruby where Puppet or PE APIs are needed; Bash for host basics. |
| `data/known_issues.yaml` | Version-pair known-issue registry (for example 2023.8.x to 2025.12 with the `pe-puppetdb` reload flake, empty-DN PKCS7 cert vs eyaml). Entries carry a check id, affected range and remediation text. | Data, same pattern as `pe_versions.yaml`: bumped per release without touching plan code. |
| `peadm::subplans::recovery_point` | Create a rollback anchor before the first destructive step: peadm backup plus a manifest (PE version, topology, pins, OID map, pe.conf copy, tarball path and checksum, timestamp) plus an optional snapshot hook call. | Subplan wrapping `peadm::backup` and `peadm::util::hook_dispatch`. |
| `peadm::rollback` (public) | Verify the recovery point, then rebuild: reinstall the recorded PE version on the primary, restore, rebuild replica and compilers, verify. Resumable. | Plan using `plan_step` with `Peadm::RollbackSteps`; reuses `uninstall`, `pe_reinstall`, `restore`, `add_replica`, `add_compilers`. |
| `peadm::util::hook_dispatch` | Invoke an operator-supplied plan (for example a VMware or cloud snapshot) at named points (`pre-upgrade`, `rollback`) and capture its return value as an opaque handle in the manifest. | Util plan taking a plan name string and a fixed parameter contract. |
| `peadm::failover` (public) | Planned role swap and unplanned promotion; re-assert classification and OID-based topology; optionally rebuild the old primary as replica. Resumable. | Plan with `Peadm::FailoverSteps`; calls `subplans::promote_replica`, `util::update_classification`, `add_replica`. |
| `peadm::util::collect_diagnostics` | On failure, gather installer log tail, failed systemd units, `puppet infrastructure status`, CRL and cert expiry, disk and memory, and attach it to the Bolt error. | Util plan plus a task; invoked by wrapper (see Pattern 5). |
| `peadm::cd4pe::*`, `peadm::scm::*` | PE-side prerequisites and cross-product coordination only (see "CD4PE and SCM Boundary"). | Thin plans with soft dependency on the sibling modules. |

## Recommended Project Structure

Additions only. Follows the conventions in STRUCTURE.md (public plans at top level, `peadm::subplans::*` private, `peadm::util::*` narrow).

```
plans/
├── preflight.pp                    # public, read-only
├── rollback.pp                     # public, resumable
├── failover.pp                     # public, resumable
├── diagnose.pp                     # public, read-only (operator-run evidence bundle)
├── subplans/
│   ├── run_preflight.pp            # severity policy shared by upgrade/failover/rollback
│   ├── recovery_point.pp           # backup + manifest + snapshot hook
│   └── promote_replica.pp          # planned vs unplanned promotion mechanics
├── util/
│   ├── hook_dispatch.pp
│   └── collect_diagnostics.pp
├── cd4pe/                          # thin; no install engine
│   ├── prepare_pe.pp               # RBAC service account/token, firewall/port facts, CA trust
│   ├── verify.pp                   # reachability + version-compat check against PE
│   └── (coordination plans, see below)
└── scm/
    ├── prepare_pe.pp               # mTLS cert from PE CA, 8143/8081/4433 reachability, node classification
    └── verify.pp
tasks/
├── preflight_host.{json,sh}        # disk, memory, time sync, OS vs target PE, tarball present
├── preflight_pe.{json,rb}          # services, pg version, puppetdb, orchestrator, code manager, license
├── preflight_certs.{json,rb}       # CA/CRL expiry and format, cert OID sanity, eyaml cert subject
├── preflight_cluster.{json,rb}     # replication lag, code sync, A/B pin duplicates, replica health
├── collect_diagnostics.{json,sh}
├── promote_replica.{json,sh}       # runs on the replica, works when the primary is down
└── recovery_manifest.{json,rb}     # write/read/verify manifest next to the backup tarball
functions/
├── preflight_report.pp             # fold Array[CheckResult] -> {blockers, warnings, passed}
└── failure_report.pp               # normalise task failure into the shared diagnostic shape
types/
├── checkresult.pp                  # Struct: id, status (pass|warn|fail), severity, message, remediation, ref
├── rollbacksteps.pp
├── failoversteps.pp
└── upgradesteps.pp                 # CHG: add 'preflight' (widening an Enum is backward compatible)
data/
├── pe_versions.yaml                # existing
├── known_issues.yaml               # version-pair issues -> check ids
└── check_thresholds.yaml           # disk, time-skew, cert-expiry-days; one place to tune
documentation/
├── preflight.md  rollback.md  failover.md  cd4pe.md  scm.md
└── fix-log.md / change-ledger.md   # existing; every item below adds rows
spec/
├── plans/{preflight,rollback,failover}_spec.rb
├── plans/subplans/{run_preflight,recovery_point}_spec.rb
├── unit/task/preflight_*_spec.rb
└── acceptance/scenarios.yaml       # existing catalog already names R-01, R-02, F-01..F-05, D-01
```

### Structure Rationale

- **Checks as grouped tasks plus a result type:** every Bolt task call costs a connection per node. On XL with many compilers, 30 single-check tasks multiply that. Four domain tasks returning arrays keep the cost bounded and keep each script testable with the existing `spec/unit/task/` pattern.
- **Thresholds and known issues in `data/`:** the supported PE range already moved to data in Phase 0 (PE-47850). Release-note-driven checks go stale every release, so the thing that changes per release must not be plan code.
- **`cd4pe/` and `scm/` subdirectories under `plans/`:** Puppet namespacing gives `peadm::cd4pe::verify` for free and keeps the product-specific surface visibly separate from the PE core, so it can be split out later without renaming core plans.

## Architectural Patterns

### Pattern 1: Check contract with severity (pre-flight)

**What:** Every check returns `{id, status, severity, message, remediation, ref}`. `blocker` severity is reserved for conditions that are objectively fatal (downgrade, tarball corrupt, disk below installer minimum, replica not in sync for a planned failover). Heuristic conditions are `warning`.
**When to use:** All pre-flight and post-flight verification, including `peadm::status` extensions.
**Trade-offs:** More ceremony than an inline `fail()`. Required here because the compatibility constraint says existing operators keep working: a false-positive blocker stops a production upgrade that would have succeeded. Mitigate with the severity split plus an explicit `skip_preflight_checks` list that is logged in the output.

```puppet
# plans/subplans/run_preflight.pp (sketch)
$report = run_plan('peadm::preflight', $targets, operation => 'upgrade', version => $version)
unless $report['blockers'].empty {
  $skipped = $report['blockers'].filter |$c| { $c['id'] in $skip_preflight_checks }
  $fatal   = $report['blockers'] - $skipped
  out::message(peadm::format_report($report))
  unless $fatal.empty { fail_plan("Pre-flight failed: ${fatal.map |$c| { $c['id'] }}", 'peadm/preflight-failed', $report) }
}
```

### Pattern 2: Always-run guards vs step-gated actions (resume safety)

**What:** `plan_step` skips whole blocks before `begin_at_step`. Anything that must hold on every run (Puppet stopped, no downgrade, transport not `pcp`) lives outside any `plan_step` block, as the P0-2 fix did for `systemctl stop puppet`. Anything that needs a healthy cluster (replication health, PuppetDB responding) lives in a `preflight` step that is skipped on resume.
**When to use:** Every new resumable plan (`rollback`, `failover`) and the `upgrade` change.
**Trade-offs:** Two places to put a check, so a rule is needed: "if it is true only before the first destructive step, it belongs in the `preflight` step; if it is an invariant, it is a guard."

**Constraint from `plan_step.rb`:** it reads `begin_at_step` from the plan scope by name. A new resumable plan must name its parameter exactly `begin_at_step` and define its own steps type. A step block's local variables do not exist on a resumed run. Any value needed after a step boundary must be re-derivable (from disk, from PE, or from the manifest), never carried in a plan variable.

### Pattern 3: Recovery point as an on-disk manifest

**What:** `recovery_point` writes `peadm/recovery_point.json` inside the backup directory, next to the existing `peadm/peadm_config.json` that `peadm::restore` already reads as a fallback. The manifest records PE version, full topology (hosts, A/B letters, pins), the tarball checksum, the snapshot hook handle (if any) and the timestamp. Rollback needs only the manifest path.
**When to use:** Before the first destructive step of `upgrade`, and optionally before `failover`, `convert` and `migrate`.
**Trade-offs:** The backup can be large and slow on big PuppetDB. Make it an explicit `recovery_point` parameter on `upgrade` (`enum[backup, snapshot_hook, both, none]`) with a default that does not change existing behavior in the first release, then flip the default after one deprecation cycle. Where the tarball lives (primary vs controller vs remote) is a parameter; a backup on the node being rebuilt is not a recovery point, so pre-flight warns when `output_directory` is on the upgraded host's only disk.

### Pattern 4: Hook plans for infrastructure the module cannot know

**What:** `hook_dispatch` runs a plan named by the operator (`snapshot_plan => 'mycorp::vm_snapshot'`) with a fixed contract: parameters `targets`, `action` (`create` or `revert`), `label`; return value is any JSON-able handle. The handle is stored in the manifest, and `rollback` passes it back with `action => revert`.
**When to use:** Snapshots (R-02), load balancer drain, agent redirection during failover (F-04 notes agents pointing at a DNS name).
**Trade-offs:** Operators write one small plan; peadm stays free of VMware/AWS/Azure code. Document the contract and ship an example plan under `examples/`.

### Pattern 5: Failure evidence at the plan boundary

**What:** Wrap destructive task calls (installer, `puppet infrastructure` commands, service restarts) so that on error `collect_diagnostics` runs against the failing target and its output is attached to the `fail_plan` details with `peadm::failure_report`. Phase 0 already added "installer log and failed services" for upgrade; this generalizes it and removes the copy-paste.
**When to use:** All steps that change the cluster.
**Trade-offs:** Adds a node round trip on failure only. Redact with the existing `sanitize_log_text` before returning, since installer logs can contain credentials.

### Pattern 6: Soft dependency on sibling modules

**What:** Thin plans call `run_plan('cd4peadm::...')` or `run_plan('complyadm::...')` only after an explicit presence check that fails with an actionable message ("add puppetlabs-cd4peadm to bolt-project.yaml modules") instead of Bolt's generic "could not find plan".
**Trade-offs:** The presence check is not a built-in plan-language function (see Open Questions). Fallback is a small Ruby function that asks the loader, or a documented `try`/catch on `run_plan` with the error rewritten.

## CD4PE and SCM Boundary

### Recommendation

**Keep the install and upgrade engines in `cd4peadm` (CD4PE) and `complyadm` (SCM). Put in peadm only what touches PE or coordinates across products.** Do not add either module to `metadata.json` dependencies.

| Concern | Owner | Reason |
|---------|-------|--------|
| Container runtime, image upload (including air-gapped), database containers, `ctl` restart, uninstall, `upgrade`, Bolt project and Hiera state | `cd4peadm` / `complyadm` | These modules' version equals the application version. Their state is the Bolt project (`data/common.yaml`, eyaml, `cd4peadm::config`), which is the opposite of peadm's rule that PE is the only state store. Support cases show the failures are inside them: `update_database_configuration` cannot find the postgres container, `resolve_ssl_config.pp` rejects the CRL, `upload_images` hits "unexpected EOF", `verify_browser_cert_chain.rb` hardcodes RSA, `ctl restart` fails after patching because no project name is set. |
| PE-side prerequisites: RBAC service account and token, CA trust distribution, mTLS cert from the PE CA for SCM, ports 8143/8081/4433 reachable from the product host, node classification for SCM scanning | peadm (`peadm::cd4pe::prepare_pe`, `peadm::scm::prepare_pe`) | PEADM already owns RBAC tokens (`rbac_token.rb`), the CA (`sign_csr.rb`), classification and cluster discovery. These steps run against PE nodes. |
| Cross-product coordination: before a PE upgrade, verify installed CD4PE/SCM versions are compatible with the target PE; after PE upgrade or failover, re-verify and re-point (new primary FQDN, replaced CA/CRL) | peadm (`peadm::cd4pe::verify`, `peadm::scm::verify`, hooks called from `upgrade` and `failover`) | The coupling point is PE changes breaking CD4PE/SCM (CRL and cert changes, primary swap). Only a PE-aware module sees both sides. |
| Air-gapped artifact verification (checksum of image tarballs before upload) | `cd4peadm` first. peadm can only offer the pattern (`verify_tarball`, `retrieve_and_upload`). | peadm must not become a dependency of those modules. Cross-reuse would invert the dependency. |
| Bolt project recreate/reattach | `cd4peadm` | The project is the state. Reconstructing it needs product internals (container env, config keys). Out of scope for peadm by the project's own constraint. |

### Why not inside peadm proper

- **Different host class.** Both products must not be installed on a PE host. peadm's targets are infrastructure nodes found through cert OIDs; these hosts carry no peadm OID role.
- **Different state model.** Bolt-project-as-state would make peadm plans depend on a project directory layout peadm does not control.
- **Different release clock.** `pe_versions.yaml` tracks PE lines; CD4PE and SCM release independently. Module metadata coupling would force a peadm release per CD4PE release.
- **Premium Forge.** `cd4peadm` needs a Forge token to download. A hard dependency would break `bolt module install` for every peadm user without it.

### Why not a wholly separate effort either

Two cross-product failure modes need a PE-aware component: a PE upgrade changing CRL and cert behavior that CD4PE then rejects (the 5.18.0 `ssl_crl` class), and a failover moving the primary under CD4PE and SCM. If nobody owns the coordination, the customer finds out after the fact.

### Decision that gates the roadmap

Whether this team can change `cd4peadm` and `complyadm` determines scope:

- **If yes:** the root-cause fixes for the CD4PE complaints (air-gap image upload, `ssl_crl`, missing postgres container, patching restart, reattach) land in `cd4peadm`; peadm gets only `prepare_pe`, `verify` and the upgrade/failover hooks. This is the recommended path.
- **If no:** peadm can only add pre-checks and post-checks around the existing plans (`peadm::cd4pe::verify`, an air-gap artifact check before invoking `cd4peadm::install`) and document workarounds. Do not fork or vendor the premium module's logic into peadm. State this limit in the roadmap so the CD4PE "automated install, patching recovery, reattach" requirements are not marked deliverable from peadm alone.

SCM note: SCM 3.x is installed with `complyadm::install` and `complyadm::configure` from a Bolt project, requires its own host separate from PE, and can auto-generate the mTLS cert only if the PE host is in the inventory. That "PE host in inventory" requirement is the natural seam for `peadm::scm::prepare_pe`. The CD4PE install flow also offers to install SCM at the end, so the two should share one prepare step and one verify plan.

## Data Flow

### Pre-flight (standalone and inline)

```
operator
   │ bolt plan run peadm::preflight primary_host=… operation=upgrade version=…
   ▼
preflight plan ──▶ get_peadm_config (discover topology; or use supplied hosts)
   │                       │ topology: primary, replica, pg, compilers, letters
   ▼                       ▼
fan-out by role ──▶ preflight_host / _pe / _certs / _cluster (parallel per target)
   │                       │ Array[CheckResult] per node
   ▼                       ▼
controller: controller-side checks (downgrade, version gate, known_issues.yaml, bolt/transport)
   │
   ▼
peadm::preflight_report ──▶ {blockers, warnings, passed} ──▶ out::message table + returned JSON
```

Direction: nodes to controller only. No state is written to PE.

### Upgrade with recovery point and resume

```
upgrade:
  always-run guards (downgrade, transport, Puppet stopped if resuming)   <- outside plan_step
  step 'preflight'      -> run_preflight (blockers fail)                  <- skipped on resume
  step 'preparation'    -> tarball verify -> recovery_point -> stop puppet -> pe.conf fixes
  steps 'upgrade-*'     -> existing; destructive-step failures call collect_diagnostics
  step 'finalize'       -> post-checks (preflight 'post-upgrade' set) -> cd4pe/scm verify hook

on failure after a destructive step:
  operator choice A: fix cause, re-run with begin_at_step=<failed step>   (existing path)
  operator choice B: bolt plan run peadm::rollback recovery_point=<manifest path>
```

Note on ordering: the existing code creates the tarball in `preparation` and Puppet stop happens there too, so `recovery_point` goes after tarball verification and before `systemctl stop puppet`, so a corrupt tarball still fails before any cost is incurred.

### Rollback

```
rollback(recovery_point manifest)
  step 'verify-recovery-point' -> manifest present, tarball checksum matches, target hosts reachable
  step 'revert-snapshot'       -> hook_dispatch(action=revert)  [if snapshot handle in manifest; then skip rebuild]
  step 'reinstall-primary'     -> pe_reinstall / uninstall + pe_install at the manifest's PE version
  step 'restore'               -> peadm::restore from the tarball (classification, certs, db)
  step 'rebuild-topology'      -> replica, PG, compilers via existing plans, driven by manifest topology
  step 'verify'                -> preflight(operation=post-rollback) + status
```

Snapshot reverts are all-or-nothing and skip the rebuild steps. Backup-based rollback is the slow path and the only one the module can test itself; the scenario catalog already marks R-01 (backup) and R-02 (snapshot) as `new`.

### Failover (planned and unplanned)

```
failover(primary_host, replica_host, mode=planned|unplanned)
  explicit host params; identity of each host is read from its own cert OIDs (cert_data),
  which works with PE services down. Never calls get_peadm_config against the old primary.

  step 'preflight'   -> replica sync, code sync (util::code_sync_status), pglogical lag, cert validity
  step 'quiesce'     -> planned only: stop services/agents on old primary; optional hook (LB drain)
  step 'promote'     -> promote_replica task on the replica (works when the primary is dead)
  step 'reclassify'  -> util::update_classification: move CA and HA-replica pins, keep A/B letters on hosts
  step 'forget'      -> puppet infrastructure forget <old primary> (tolerate error if unreachable)
  step 'rebuild'     -> optional: uninstall PE on old primary, reinstall agent, add_replica
  step 'verify'      -> get_peadm_config now succeeds against the new primary + status
```

Why `reclassify` is explicit: `get_peadm_config` derives `primary_host` from the `PE Certificate Authority` pin and `replica_host` from the `PE HA Replica` pin, while the A/B letter comes from the `peadm_availability_group` OID on the host. Topology discovery therefore stays correct after failover only if the pins move and the letters do not. The scenario catalog (F-01) states the same expectation: availability groups follow the hosts.

### CD4PE / SCM coordination

```
operator ──▶ peadm::cd4pe::prepare_pe (RBAC account, CA trust, mTLS for SCM)
                  │ writes values the operator feeds into cd4peadm::generate_config / complyadm inventory
                  ▼
operator ──▶ cd4peadm::install / complyadm::install   (sibling modules, own Bolt project)
                  ▼
operator ──▶ peadm::cd4pe::verify, peadm::scm::verify (read-only; PE-side reachability, versions)

hook: peadm::upgrade finalize and peadm::failover verify call the verify plans when a
      `cd4pe_host` / `scm_host` parameter is supplied (optional, default undef).
```

### State Management

```
PE (classifier pins, OIDs, pe.conf, PuppetDB)  --- source of truth for topology
Backup dir: peadm/peadm_config.json + peadm/recovery_point.json --- source of truth for rollback
Bolt scope: begin_at_step flag only --- never relied on for data across steps
CD4PE/SCM: their own Bolt project (outside peadm)
```

## Anti-Patterns

### Anti-Pattern 1: Health checks inside a resumable step that will fail on resume

**What people do:** Put "PuppetDB is healthy" in `preparation` or at the top of `upgrade` unconditionally.
**Why it's wrong:** After a failed upgrade, services are stopped by design; the check fails on every resume and blocks recovery.
**Do this instead:** Pattern 2. Invariants as guards, health in a skippable `preflight` step.

### Anti-Pattern 2: Passing step results through plan variables

**What people do:** Compute the backup path or snapshot id in `preparation` and use it in a later step.
**Why it's wrong:** A resumed run skips the block, so the variable is undefined. This is the same bug class as P0-2.
**Do this instead:** Persist to the manifest and read it back, or re-derive from PE.

### Anti-Pattern 3: Discovering topology from the node that is down

**What people do:** Call `get_peadm_config` on the primary to find the replica in the failover plan.
**Why it's wrong:** It queries the classifier and PuppetDB on the failed node.
**Do this instead:** Require explicit hosts, validate identity from certs, run discovery only after promotion.

### Anti-Pattern 4: Vendoring or forking cd4peadm/complyadm logic into peadm

**What people do:** Copy the install plans so that peadm can fix them in place.
**Why it's wrong:** Instant drift against a module whose version tracks the product; two sources of truth for air-gap handling and Hiera schema.
**Do this instead:** Fix upstream, or wrap with pre/post checks.

### Anti-Pattern 5: Adding parameters to every layer by hand

**What people do:** Add `recovery_point`, `skip_preflight_checks` or `cd4pe_host` to `install`, `subplans::install`, `configure` and `upgrade` separately.
**Why it's wrong:** Already flagged in ARCHITECTURE.md (duplicated subplan parameter lists): missed forwards fail silently with defaults.
**Do this instead:** Introduce the new parameters only on the plans that need them (`upgrade`, `failover`, `rollback`), pass a single `Hash $options` into new subplans, and add a spec that asserts forwarding for each new parameter.

### Anti-Pattern 6: Hypervisor or cloud code in the module

**What people do:** Add VMware/AWS snapshot tasks to peadm.
**Why it's wrong:** Unbounded support surface and credentials handling; the supported estate spans many platforms.
**Do this instead:** Pattern 4.

## Scaling Considerations

The relevant scale axis is cluster size and node count, not users.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Standard (1 primary, few compilers) | Everything runs serially without trouble. Backup-based recovery point is quick. |
| Large (many compilers) and XL (separate PostgreSQL) | Check tasks fan out in parallel per `run_task` call, so group checks by role and avoid per-compiler loops. Recovery-point backup of PuppetDB/RBAC/activity can take long; offer `recovery_point` choices that skip large tables (existing `Peadm::Recovery_opts` already lets `custom` exclude `puppetdb`, `activity`). |
| 10k+ agent estates (the reported 11k-node upgrade) | Pre-flight must not query per-agent state. Use aggregate PuppetDB queries only. Rollback must not claim agent state is restored; agents re-check in after restore, and the plan's verify step should say so. |

### Scaling Priorities

1. **First bottleneck:** Bolt round trips from many small tasks over SSH. Grouped check tasks and a controller-side fold keep the count at about four per node role.
2. **Second bottleneck:** backup duration and size for recovery points on large PuppetDB/PostgreSQL. Make the scope configurable and surface estimated size in pre-flight (disk check on the backup destination).

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| PE bundled `pe_status_check` (ships with PE, includes infra summary plans and facts) | Reuse its facts/output in `preflight_pe` instead of re-implementing service-health logic | MEDIUM: confirm it is present on every supported line (2023.8 to 2026.0) and its fact schema is stable. Fall back to `infrastatus.sh`, which `peadm::status` already uses. |
| PE installer (`puppet-enterprise-installer`) | Existing `pe_install` task | Keep failure evidence capture here (Pattern 5). |
| PE RBAC / classifier / PuppetDB APIs | Existing Ruby tasks over 4433/8081 with host cert | Same mechanism for new check tasks. |
| Forge (premium `cd4peadm`, `complyadm`) | Operator-managed Bolt project with a Forge token | peadm never needs the token. Documented as prerequisite only. |
| Container registry (air-gapped mirror) | Out of peadm; `cd4peadm` / `complyadm` handle it | peadm offers only the checksum-before-upload pattern. |
| Hypervisor or cloud snapshot API | Operator hook plan (Pattern 4) | Example plan only. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `upgrade` / `failover` / `rollback` to `run_preflight` | `run_plan`, returns report hash | One severity policy. |
| `upgrade` to `recovery_point` | `run_plan`, returns manifest path | Also persisted on disk, so a resumed run can find it. |
| `rollback` to `restore`, `uninstall`, `add_replica`, `add_compilers` | `run_plan` with parameters taken from the manifest | Existing public plans are reused unchanged. Any parameter gaps found here are fixed in those plans, additively. |
| peadm to `cd4peadm` / `complyadm` | Soft `run_plan` behind a presence check, or no call at all (operator runs both) | No `metadata.json` dependency. |
| Plans to `data/*.yaml` | Ruby function reads data on each call (same as `supported_pe_versions`) | New data files follow the `pe_versions.yaml` pattern. |
| Tests to scenario catalog | Each new plan maps to IDs in `spec/acceptance/scenarios.yaml` | Fix-log entry per fix; no "demonstrated" without a run. |

## Suggested Build Order

Dependencies drive the order. Each item lists what it needs first.

1. **Shared contracts (no behavior change).** `Peadm::CheckResult`, `peadm::preflight_report`, `peadm::failure_report`, `data/check_thresholds.yaml`, grouped check task skeletons. Needs nothing. Unblocks everything below.
2. **Diagnostics wrapper (D6).** `collect_diagnostics` task and util plan, wired into `pe_install` call sites in `upgrade` first. Needs (1) for the report shape. Early because it improves every later failure and is the cheapest visible win (the "bare exit code" complaints).
3. **`peadm::preflight` plus `run_preflight`, wired into `upgrade` in warn-first mode.** Needs (1). Add the `preflight` step to `Peadm::UpgradeSteps`. Standalone use first, enforcement for blockers after one release. Seeds `known_issues.yaml` from the support-case themes (pe-puppetdb reload, CRL/SSL, eyaml cert).
4. **`recovery_point` and `hook_dispatch`.** Needs (2) for failure reporting and (3) for the disk checks. Opt-in parameter on `upgrade`, with default flip later.
5. **`peadm::rollback`.** Needs (4): it cannot be built or tested without a manifest to consume. Acceptance scenarios R-01, R-02.
6. **`peadm::failover`.** Needs (1), (3) for the failover check set, and the existing `add_replica` and `update_classification`. Independent of (4) and (5), so it can run in parallel with them if staffing allows. Acceptance F-01 to F-05; promote mechanics need a real DR cluster, not just unit specs.
7. **`peadm::cd4pe::prepare_pe` / `verify` and `peadm::scm::prepare_pe` / `verify`, plus optional hooks in `upgrade` and `failover`.** Needs (3) and (6) for the hooks, and a decision on sibling-module ownership (see gate above). Fixes inside `cd4peadm`/`complyadm` do not depend on any of the above and can start earlier in their own repos if the team has access.
8. **Cleanup that reduces risk for the rest.** Parameter-forwarding spec for new options, REFERENCE.md regeneration, `documentation/*.md`, and scenario-to-workflow wiring. Do it per item, not at the end, to satisfy the ledger and fix-log constraints.

Not recommended before (3): converting `convert`, `migrate` or `install` to the new preflight. They benefit later and widen the test surface now.

## Open Questions and Spikes

| Question | Why it matters | Confidence now |
|----------|----------------|----------------|
| Can this team commit to `cd4peadm` and `complyadm`? | Gates the CD4PE/SCM requirements (see boundary section). | Unknown. Ask the project owner. |
| Does Bolt plan language have a way to test whether a plan exists (soft dependency check)? | Pattern 6 error quality. | LOW: not verified. Spike with a Ruby function over the Puppet loader; else rewrite the `run_plan` error. |
| Does a promote on the replica work through a task when the orchestrator is down, on 2023.8 through 2026.0? | Unplanned failover (F-03, F-05) depends on it. The repo's CI workflow runs `puppet infra promote replica` directly. | MEDIUM: current docs and the workflow use that command; behavior across all supported lines is untested here. Needs a real DR cluster. |
| Is `pe_status_check` bundled and stable on every supported line? | Decides whether `preflight_pe` reuses it. | MEDIUM: vendor docs say bundled from 2023.8; confirm per line. |
| Is backup-based rollback acceptable for XL as the only module-tested path? | R-01 duration and size, and whether `recovery_opts` defaults capture enough to rebuild. | MEDIUM. Needs measurement on an XL fixture. |
| Does an in-repo stale spec need cleanup? `spec/plans/verify_replica_spec.rb` has no matching `plans/verify_replica.pp` (it is a plan in `spec/acceptance/peadm_spec/plans/`). | Avoids confusing new specs placed by naming convention. | HIGH that it is a mismatch; low priority. |

## Sources

- `/home/matthew/Code/puppetlabs-peadm/.planning/codebase/ARCHITECTURE.md` and `STRUCTURE.md` (HIGH, project's own map)
- `/home/matthew/Code/puppetlabs-peadm/lib/puppet/functions/peadm/plan_step.rb`, `plans/upgrade.pp`, `plans/backup.pp`, `plans/restore.pp`, `tasks/get_peadm_config.rb`, `types/upgradesteps.pp` (HIGH, read directly)
- `/home/matthew/Code/puppetlabs-peadm/documentation/test-scenarios.md`, `spec/acceptance/scenarios.yaml`, `documentation/recovery/automated_recovery.md`, `documentation/fix-log.md` (HIGH; already commit to planned `peadm::rollback`, `peadm::failover`, snapshot hook)
- `/home/matthew/Code/peadm.csv`: support cases and Jira (MEDIUM; anonymized, used for the CD4PE failure classes)
- [Install Continuous Delivery (CD)](https://help.puppet.com/cdpe/current/Content/UserGuide/CDPE/Installation/cd_install.htm): `cd4peadm::install`, `generate_config`, `install_from_config`, separate host, Forge token, license file (MEDIUM, vendor docs)
- [Upgrade Continuous Delivery (CD)](https://help.puppet.com/cdpe/current/Content/UserGuide/CDPE/Upgrade/upgrade-application.htm): `cd4peadm::upgrade`, no backup/rollback guidance (MEDIUM)
- [Install Security Compliance Management](https://help.puppet.com/scm/current/Content/UserGuide/SCM/Installation/scm_bolt_install.htm): `complyadm::install`/`configure`, own host, PE host in inventory for mTLS (MEDIUM)
- [Forge: puppetlabs/cd4peadm](https://forge.puppet.com/puppetlabs/cd4peadm) (LOW: listing only; page content not retrievable, source not inspected)
- [About the pe_status_check module](https://help.puppet.com/pe/2023.8/topics/about-pe-status-check.htm) and [Forge: pe_status_check](https://forge.puppet.com/puppetlabs/pe_status_check) (MEDIUM)

---
*Architecture research for: PEADM lifecycle automation plus CD4PE and SCM*
*Researched: 2026-11-10*

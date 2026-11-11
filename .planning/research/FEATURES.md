# Feature Research

**Domain:** Install, upgrade and maintenance automation for Puppet Enterprise (all sizes, with DR replica) plus CD4PE and Secure Compliance Management (SCM), delivered as a Bolt module (peadm)
**Researched:** 2026-11-10
**Confidence:** MEDIUM-HIGH. User need is HIGH (50 support cases and 52 Jira tickets read in full, plus the repo as it stands). The comparison with other lifecycle tools is MEDIUM (PE and Red Hat docs found by search; kubeadm, GitLab and similar from background knowledge, not re-verified this session). SCM need is LOW (almost no evidence).

## How to read this

- **Evidence** cites `CASE-nnn` (support case) and Jira IDs from `~/Code/peadm.csv`. Where a feature maps to a Phase 0 item or an acceptance scenario, the ID from `documentation/change-ledger.md` / `documentation/test-scenarios.md` is given (P0-n, U-nn, F-nn ...).
- **Status** is what the repo has today, from `plans/`, `tasks/` and `.planning/codebase/`: **Exists**, **Partial**, **Missing**.
- **Complexity** is LOW (days, spec-testable), MEDIUM (a plan plus tasks, needs a real cluster to prove), HIGH (new subsystem, or heavy cluster testing across topologies).

## What the evidence says users need

The 50 cases fall into these clusters. Counts are by primary topic, so they add up to 50.

| Cluster | Cases | What users keep asking for |
|---|---|---|
| PE upgrade (peadm) | 19 | Check my parameters before I start (001, 034, 035), explain failures (002, 011, 047, 049), work with new PE versions (003), recover from a failed run (002, 009), confirm everything is consistent afterwards (008, 012, 017, 045), automate it end to end (043) |
| CD4PE install, upgrade, recovery | 16 | Docs and a guided install (004), air-gapped image handling (005, 019, 031), certificate and CRL handling (006, 013, 018, 032), recovery after patching or reboot (026, 030, 033), reattach a lost Bolt project (028) |
| DR, failover, role swap | 5 | Health check before the swap (010, 029), a reviewed procedure (015, 023, 024) |
| Replica, compiler, database operations | 5 | Replace a compiler (016), re-add an auto-replaced replica (022), rebuild a PostgreSQL node (020), correct classification (041, 042) |
| Migration and OS change | 3 | Move to a new OS or domain (038, 048), build on an existing shared CA (044) |
| Other | 2 | Odd task output (007), Bolt over non-standard SSH (037) |

Jira adds: 11 CD4PE tickets (CDPE-6936, 6941, 7433, PF-3086, GJira-2, 4, 5, 8, 10, 12, 14), plus peadm tickets on legacy compilers (PE-36212, 36355, 40239), "production environment assumed" (PE-39465, 39789, 46598, 45758), availability groups for role swap (PE-43987, 43572), parameter summary logging (PE-36229, 40350), dependency breakage (PE-36915, 39099), a plan that "reports complete after a failed step" (PE-37220), and "plans for automating DR activities" (PE-39742, Closed, but the repo has no promote or failover plan; check what shipped).

Three patterns matter for the roadmap:

1. **Customers use support as their pre-flight.** CASE-001, 010, 015, 029, 034 and 035 are "please look at my parameters / health before I run this." That is the tool's job, and a missing `check` mode is why these tickets exist.
2. **Customers who attempt rollback find there is none.** CASE-009, 012, 036 and the scenarios R-01 and R-02: they either re-run the upgrade with an older version (refused by the installer) or fall back to VM snapshots that peadm does not know about.
3. **"Success" is not trusted.** CASE-008 (code deploy broken), 012 (eyaml compile broken), 017 (corrective changes, compiler status red), 045 (compilers left at old version), 022 (replica "added" but not classified), PE-37220 (complete after a failed step). Each is a plan that exited 0 or an installer that finished while the system was not healthy.

## Feature Landscape

### Table Stakes (Users Expect These)

Missing these means peadm cannot meet its stated Core Value (succeed predictably; otherwise fail early, explain itself, be recoverable).

#### A. Pre-flight and health checking

| Feature | Why Expected | Complexity | Status | Evidence | Notes |
|---|---|---|---|---|---|
| **Read-only `check` mode for every long plan** (upgrade, convert, add_replica, promote, restore): validates parameters, targets and cluster state, changes nothing, prints pass/fail per check | `satellite-maintain upgrade check` and `kubeadm upgrade plan` set the expectation that a dry run exists and runs while the system is still at its current version. Peadm users currently email support to review `upgrade.json` | MEDIUM | Missing | CASE-001, 034, 035, 043; PE-40350 | Build as one `peadm::preflight` plan with a check registry that each plan calls, not per-plan copies. Output must be structured (JSON) so CI can gate on it |
| **Supported-version and upgrade-path check** (target supported by this peadm release, not a downgrade, not earlier than the installed release date, skip-line allowed) | Customers hit this at the worst moment, after services stop | LOW | Partial: version range data-driven (P0-7), downgrade refused (P0-3). Release-date rule not caught | CASE-003, 009, 039; PE-47850; U-12, D-01 | The installer's own rule (release date, not version number) can be read from the tarball or approximated from release data. Multi-hop (2021.7 to 2023.0 to 2023.8) is below the 2023.8 support floor, so refuse with guidance and do not automate |
| **Inventory and connectivity check** (SSH/WinRM reach, sudo, Bolt version, every infrastructure node resolvable and matches `peadm_config`) | Cheapest failure to find early; customers already test it by hand with `puppet agent --version` | LOW | Partial (Bolt version only) | CASE-034, 035, 037 | Include "parameters match the cluster" (host in params = host in classifier). Non-standard transports (Azure `az ssh`) are documented via Bolt config, not built (see Anti-Features) |
| **Cluster health gate** (`puppet infrastructure status` / `pe_status_check` summary, replica in sync and streaming, A/B pin sanity, no stale agent lock, disk space for installer and backup) | PE ships `pe_status_check` (infra summary plan, per-role indicators); users want it enforced, not advisory | MEDIUM | Partial (`peadm::status`, `check_pe_master_rules`, `validate_rbac_token`) | CASE-010, 015, 029, 035, 016; PE-43572, 43987 | Wrap `pe_status_check::infra_summary` instead of reinventing indicators (MEDIUM confidence it is available on every supported PE; confirm per version). Add peadm-specific checks it lacks |
| **Upgrade-specific known-risk checks**, each one tied to a past incident | Each of these caused a real failure: unknown r10k SSH host key (CASE-008), eyaml cert with empty DN (CASE-012, GJira-7), legacy compiler OID (CASE-050, P0-5), `node_manager` module version (PE-36915, 39099), cloud-database installer file (CASE-046), duplicated A/B pins (CASE-016) | LOW each, MEDIUM total | Partial (legacy OID done) | as listed; U-02, U-04, U-09, U-11, C-01 | Keep a catalog: check ID, ticket, what it detects, how to fix. New check = new row. Each check must say how to fix, not only what is wrong |
| **Replica and failover readiness checks** (CA cert/key/CRL match, secret key files present on replica, cert SANs include the VIP or alias, cert TTL not about to expire, RBAC token lifetime, NTP, ports, Code Manager deploy key) | PE docs warn that missing secret key files cause a promoted replica to generate new ones and lose LDAP and encrypted data; CASE-015 drew up exactly this checklist by hand | MEDIUM | Missing | CASE-010, 015, 024, 029; F-01, F-02 | The same registry as above, selected by `check_for=promote` |

#### B. Upgrade safety and resumability

| Feature | Why Expected | Complexity | Status | Evidence | Notes |
|---|---|---|---|---|---|
| **Fail before touching services**: installer tarball verified (exists, not truncated, correct layout) before Puppet or any service is stopped | A broken download should never cost an outage | LOW | Done (P0-4) | CASE-049; PE-42686, 43373; U-03 | Keep the tarball until the installer exits 0 (concern in the map: it is deleted before the install, forcing a multi-GB re-download) |
| **Every long plan is resumable with validated steps**: unknown `begin_at_step` is an error, resuming mid-way re-establishes the state earlier steps would have set (Puppet stopped, drop-ins in place), steps are idempotent | `satellite-maintain` resumes from the failed step; peadm already has `plan_step`. Today a typo skips every step and reports success | MEDIUM | Partial (`plan_step` exists; P0-1, P0-2 fixed two cases) | CASE-002, 011; PE-37220 | Validate in `plan_step`, not in each plan. Add a resume test per plan from every step. Install, add_replica, restore and migrate need the same treatment as upgrade |
| **Upgrade brings the whole cluster to one version** (primary, replica, every compiler, postgres nodes) and checks that the versions match before it says "done" | Customers expect one command to finish the job; CASE-045 found compilers left behind and the compile error that follows | MEDIUM | Partial (compilers are upgraded in steps; no final version assertion) | CASE-045; U-08 | A final assertion covers legacy compilers, external postgres and patch-level upgrades, the paths where it slips |
| **Post-upgrade verification gate**: infra status green, every infra node versions agree, a Puppet run on each infra node is clean and a second one has no corrective changes, code deploy succeeds, a catalog compiles from each compiler (including a Hiera/eyaml lookup), orchestrator and PuppetDB respond | The upgrade that "went smoothly" and then broke deployments, eyaml or compiler status is the most common complaint | MEDIUM | Missing | CASE-008, 012, 017, 045; U-02, U-04, U-05 | The result must change the plan's exit status. A failed verify says what to run to look closer. Keep checks cheap enough to run every time |
| **Known-flake handling for the installer**: bounded retry (repair mode) when the failure matches a recognised signature, such as the pe-puppetdb reload during skip-line upgrade | Customers are told "run it again", and it works on the second try | MEDIUM | Missing | CASE-002; GJira-1 (Blocker, open); U-01 | Retry only on a signature allow-list, once, and print that it did so. Root cause is a PE problem; needs phase-level research before building |
| **Failure leaves the node in a documented, restorable state**: Puppet re-enabled where safe, temporary workarounds reverted (`delete-reports` symlink, 10-shortcircuit drop-in), tarball kept | An aborted run should not need hand-cleanup | MEDIUM | Partial (known leftovers listed in `CONCERNS.md`) | CASE-002, 011; concerns map | Do it with a cleanup step that always runs (ensure-style), not by hoping the success path is reached |

#### C. Rollback and recovery

PE has no supported downgrade (the installer refuses it, CASE-009). Rollback in this domain means restore the pre-upgrade state, so the feature set is about making that restore dependable.

| Feature | Why Expected | Complexity | Status | Evidence | Notes |
|---|---|---|---|---|---|
| **Backup gate before upgrade**: upgrade requires (or creates) a verified backup and records where it is and what it contains | `kubeadm` etcd backup and `satellite-maintain` snapshot/backup steps are standard; customers already run `peadm::backup` plus `puppet-backup` by hand | MEDIUM | Partial (`peadm::backup`, `backup_ca` exist; nothing links them to upgrade) | CASE-036, 009; R-01 | Verify, don't just create: archive readable, size plausible, classification included. `peadm::backup` needs the non-`production` environment fix first (PE-46598, 39789) |
| **A tested, documented rollback procedure**: what to do at each upgrade step if it fails (before installer, mid-installer, after), including "rebuild old version then `peadm::restore`" and "revert VM snapshot" | CASE-009, 036 ask exactly this and get no answer from the tool | HIGH | Missing | CASE-009, 012, 015, 036; R-01, R-02 | Mostly acceptance-test and documentation work, plus a `peadm::restore` that works across the same steps. Snapshot tooling stays outside peadm (see Anti-Features) but the plan must say when to take one |
| **Restore that handles the realistic shapes**: non-default environment, classifier default groups, DR architectures, migration to a new host | Restore and migrate failures are Blockers | MEDIUM | Partial | PE-46598 (Blocker), 45758, 39789 (Blocker), 39465; M-02 | Remove the hard-coded `production` assumption everywhere (one helper, used by backup, restore, migrate, install, upgrade) |

#### D. Diagnostics

| Feature | Why Expected | Complexity | Status | Evidence | Notes |
|---|---|---|---|---|---|
| **Failures name the cause**: installer log tail, failed `pe-*` units, certificate and CRL state, the exact command that failed and its exit code | Bare `exit 1` is in a large share of the cases: CASE-002, 011, 047, 049, 014, 030 | LOW-MEDIUM | Partial (P0-6 for `pe_install`) | CASE-002, 011, 014, 019, 030, 047; PE-39571 | Apply to every task that wraps an installer or a service start (pe_install, provision_replica, enable_replica, puppet_infra_upgrade, wait_for_services in CD4PE) |
| **Print the effective parameters and plan steps at the start** | Support starts every case by asking for them; the tickets were cancelled or went stale twice, so they are not done | LOW | Partial (upgrade prints parameters) | PE-36229 (Cancelled), PE-40350 (Closed); CASE-050 output shows it exists for upgrade only | Redact secrets. Do it once in a shared function |
| **Plan results that say what happened** (per-node outcome, what was skipped, what to do next) | add_replica reports success while the replica is not classified | MEDIUM | Missing | PE-43490; CASE-022; P-01 | Pair with a post-condition assertion at the end of each day-2 plan |
| **Timeouts and waits that are readiness checks, with the failing target named** | CA queries timing out (CASE-047, GJira-11), 15-second blind sleeps | MEDIUM | Partial | CASE-029, 047; GJira-11; F-05 | `enable_ha_failover` CA timeout must be a parameter |

#### E. Failover, role swap and DR promotion

| Feature | Why Expected | Complexity | Status | Evidence | Notes |
|---|---|---|---|---|---|
| **Planned role swap as one plan**: pre-flight, final sync check, stop old primary, promote replica, update availability-group pins, re-provision old primary as the new replica, post-verify | Five cases ask for a reviewed procedure; CASE-015 wrote one from scratch. PE's own docs treat promote and repurpose as separate manual steps | HIGH | Missing (`add_replica` and `replace_failed_postgresql` exist; no promote or swap plan found in `plans/`) | CASE-010, 015, 023, 024, 029; PE-43987, 39742; F-01, F-02 | Must be availability-group aware (A/B pins swap with the roles). Resume-safe, since CASE-029 failed with a cert-loading timeout in the repurpose step and was finished by hand (F-05) |
| **Unplanned promotion** when the primary is lost | The documented manual recovery is a two-step guide today | MEDIUM | Missing | `documentation/recovery/*`; F-03 | Share steps with planned swap. Skip the steps that need the old primary |
| **Works across version and OS differences** (2023.8 vs 2025.x, mixed OS pair during an OS upgrade) | Customers use role swap to upgrade the OS (CASE-024) and test across PE lines (CASE-023) | MEDIUM | Missing | CASE-023, 024; F-02, F-04 | A matrix of acceptance runs, little new code |
| **Rebuild the failed or retired node as replica** (forget, clean cert, reinstall agent, provision, enable) | Step 9 of CASE-015, and the usual follow-on | MEDIUM | Partial (`add_replica` forgets existing replicas and rebuilds) | CASE-015, 022, 023; P-01 | Reuse of the same certname after `ca clean` is the sticking point |

#### F. Replica, compiler and database operations

| Feature | Why Expected | Complexity | Status | Evidence | Notes |
|---|---|---|---|---|---|
| **Replace a compiler** (forget, purge cert, re-add with the same or a new name) that survives bad A/B pins, and re-balances A/B | An external automation calls `add_compilers` and fails on duplicate pins | MEDIUM | Partial (`add_compilers` exists; no replace; no pin repair) | CASE-016, 041, 042; PE-43572, 44017; C-01 | A `peadm::repair_ab_pins` (or fix inside `get_peadm_config`) removes the cause for several cases at once |
| **Add or re-add a replica that ends correctly classified** and says so | CASE-022: success message, wrong result | MEDIUM | Partial | CASE-022; PE-43490, 36451; P-01 | Post-condition: in classifier group, listed in `puppet infrastructure status`, replication streaming |
| **Replace a failed PostgreSQL node on either side**, including the primary-side | Already a plan; fails when the failed host is the primary's | MEDIUM | Partial (PE-41341 open path) | CASE-020; PE-41341; DB-01 | Includes trusted extension / classification for the new node |
| **New compilers and replicas come up talking to each other** (agent communication with compilers configured at install) | Setup gap reported at install | LOW-MEDIUM | Missing | PE-39531 | Accepted, not done |

#### G. Install, air-gap, migration

| Feature | Why Expected | Complexity | Status | Evidence | Notes |
|---|---|---|---|---|---|
| **Air-gapped install and upgrade for PE**: tarball staged, `download_mode` that never reaches out, signature and integrity checks, no installer step that fetches anything | Regulated customers; `download_mode` and the verify step exist | MEDIUM | Partial | PROJECT.md; CASE-005, 019, 031 (CD4PE side) | Needs an acceptance run with outbound traffic blocked |
| **Install and migrate without assuming `production`** | Blocker tickets | MEDIUM | Missing | PE-39789 (Blocker), 39465, 46598 (Blocker); I-02, M-02 | One shared helper, as in C |
| **Migrate to a new OS, host or domain** with certs, classification and pe_repo handled | Rocky 8 to 9, domain change affecting `pe.repo` | MEDIUM | Partial (`peadm::migrate` exists) | CASE-038, 048; PE-45758; M-01 | Classifier default groups are not restored today (PE-45758) |
| **Keeps up with new PE releases** (new version supported within days; new license format) | A new PE release blocked a customer until peadm shipped (CASE-003); new license epic open | LOW per release; MEDIUM for license | Partial (P0-7 moved the range to data) | CASE-003; PE-47850, PE-43468 | A nightly or per-release CI job against the newest PE, a release checklist, and the escape hatch `permit_unsafe_versions` documented. The "latest / latest-1" lifecycle (CASE-043) makes this recurring |

#### H. CD4PE (cd4peadm)

`cd4peadm` is a separate Forge module (premium, PF-3086), not in this repo. Where the work lands (this repo vs. that one) is an open architecture question for the roadmap.

| Feature | Why Expected | Complexity | Status | Evidence | Notes |
|---|---|---|---|---|---|
| **Documented, guided install** with a pre-flight (CPU, memory, OS, runtime, DNS, certs, ports) | A customer asked for install documentation (CASE-004). The install already has a pre-flight (shown in CASE-019) | LOW-MEDIUM | Exists in cd4peadm (not verified here) | CASE-004, 019; GJira-4 (more examples) | Documentation and worked examples |
| **Air-gapped install and upgrade with image integrity checks** | Truncated image archive gave an unhelpful podman error (unexpected EOF); an upgrade failed because the postgres container was absent | MEDIUM | Partial | CASE-005, 019, 031; GJira-2, GJira-14 | Check size and hash of each archive after upload, and that images for the target version are present before anything is stopped. Check the DB container exists and is running before `update_database_configuration`. Make upgrade re-runnable |
| **TLS inputs that accept what real CAs issue**: any key type (not only RSA), CRL as bundle, DER or PEM, file path instead of pasted PEM, verified before use | Three separate cases and two tickets | LOW-MEDIUM | Partial (path support added in 5.18; CRL check broke DigiCert chains) | CASE-006, 013, 018, 032; CDPE-7433, GJira-5, GJira-10 | Validate with `openssl` and give the actual reason when rejected. Cover with spec tests using real-shaped fixtures |
| **Recovery after patching or reboot**: containers and services come back in order, `ctl restart` waits and then says why not | Reboots after patching leave CD4PE down or fragile | MEDIUM | Partial (`ctl` exists; times out with no cause) | CASE-026, 030, 033; GJira-12 | Check container restart policy and systemd units for podman, collect container logs on failure |
| **Reattach or recreate the Bolt project for an existing instance** | The project directory is the only place that holds the generated config and secrets | MEDIUM | Missing | CASE-018, 028 | Needs the pkcs7 keys; be honest when they are gone |
| **Backup and restore of CD4PE** (database, config, keys) | Implied by every "unstable state" report (CASE-033); no evidence of a current tool | MEDIUM | Unknown | CASE-033, 026 | LOW confidence that this is in cd4peadm already; confirm in phase research |

#### I. SCM

| Feature | Why Expected | Complexity | Status | Evidence | Notes |
|---|---|---|---|---|---|
| **Optional install of SCM at the end of CD4PE install, upgrade, health check** | The CD4PE install prompt already offers SCM (CASE-019) | MEDIUM | Unknown | CASE-019 only | LOW confidence. No SCM-specific case or ticket exists. Phase research must define scope with the SCM owners |

### Differentiators (Competitive Advantage)

Not required to function, but these are what would make peadm the standard way to run PE.

| Feature | Value Proposition | Complexity | Notes |
|---|---|---|---|
| **Unattended, CI-driven upgrade**: one plan that runs `check`, backup, upgrade, verify and (on failure) prints the rollback steps, with machine-readable output and a clean exit code | CASE-043 asks for exactly this as PE moves to a faster "latest / latest-1" cadence. No PE-native tool does it across primary, replica, compilers and external databases | MEDIUM once A, B and C exist | Falls out of the table stakes. Name it `peadm::upgrade` with `--noop`/`check_only` or a thin wrapper plan |
| **Persistent run journal and resume without re-supplying parameters** | CASE-002 restarted the plan from a params file after a partial run. A journal on the primary records step results so `resume` is safe | MEDIUM | Store under `/opt/puppetlabs/peadm/`; tolerate loss of the Bolt host |
| **Dry-run of the whole upgrade plan**: list the steps and the nodes each will touch, and estimated downtime | Customers write change tickets (CASE-009, 034); `kubeadm upgrade plan` does similar | LOW-MEDIUM | Reuse the step list; no extra cluster access |
| **Support bundle collected automatically on failure**, with secrets excluded | Cases routinely end with "will upload the support bundle later" (CASE-010, 012, 029) | MEDIUM | Wrap `puppet enterprise support`; list what was excluded (CASE-012 excludes the eyaml key) |
| **Rehearsal workflow**: the same plan run against a lab or snapshot clone with a `rehearsal` flag that relaxes only the prod-specific checks | Customers rehearse in DEV before every production change (CASE-001, 034, 036) | LOW-MEDIUM | Mostly documentation plus consistent parameter files across environments |
| **Known-issues advisories bundled with the version data**: when the target version has a documented problem (eyaml DN, pe-puppetdb reload), pre-flight says so and what to do | Turns support knowledge into checks. `data/pe_versions.yaml` is already the per-version data source | MEDIUM | Same registry as the check catalog; needs a maintenance process |
| **Role swap exercise mode**: planned swap, verify, swap back | DR exercises are recurring (CASE-010, 029 name them) | HIGH | Only after planned swap is proven |
| **Shared-CA / existing-CA bootstrap** | CASE-044 builds regional stacks on one CA | HIGH | Single case; PE-side constraints (console-cert, saml-cert) must be understood first. Treat as research |
| **Inventory generation from the cluster** (build a Bolt inventory from `peadm_config` and PuppetDB) | Removes the parameters-don't-match-cluster failure | LOW-MEDIUM | Nice to have after check mode exists |
| **Structured JSON output from every plan** | Lets pipelines and ticketing consume results | LOW-MEDIUM | Pairs with plan results in D |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---|---|---|---|
| **A real downgrade** (`upgrade` to an older version) | CASE-009: the customer edited the version and re-ran | The PE installer refuses it by design; any workaround would damage databases | Refuse early (done, P0-3) and point to backup restore or snapshot revert; build the rollback procedure in C |
| **Built-in VM snapshot or cloud API integration** | Customers rely on snapshots (CASE-015, 036, R-02) | Dozens of hypervisors and clouds, credentials, and a risk of snapshotting while services run (the case itself asks whether it is supported) | Provide `pre_upgrade_hook` / `post_upgrade_hook` parameters (a Bolt plan or command the operator supplies) and document the safe order |
| **Load balancer / VIP / DNS repointing** | CASE-015, 024 front PE with an F5 or Route53 aliases | Vendor-specific and outside Bolt's scope; wrong automation causes outages | Hooks as above, plus checks that the VIP name is in the certificate SANs and that ports answer |
| **Custom Bolt transports for cloud shells** (Azure `az ssh`) | CASE-037 | Maintaining transports is not peadm's job; Bolt already supports SSH config and `ProxyCommand` | Document the working inventory for `az ssh` / bastions; the connectivity check reports the cause |
| **Automatic fix of data in the customer's repos** (re-encrypt eyaml, repair r10k config) | CASE-012 asks for a multi-repository recrypt | Touches customer code and secret keys; wrong move breaks catalogs | Detect and warn in pre-flight; document the remediation |
| **Changing PE, CD4PE or SCM product behavior** (CD4PE last-login, webhook scheme, pipeline OOM tuning beyond a documented knob) | GJira-8, CASE-021, 025, 027 | Out of scope per PROJECT.md; the fix belongs in the product | Expose the knob if one exists in `common.yaml`; otherwise route to the product team |
| **Automating upgrades below PE 2023.8 (multi-hop)** | CASE-039, U-07 | Out of scope per PROJECT.md; adds test cost for lines going out of support | Refuse with a message naming the manual path |
| **A GUI or new orchestrator** | The PIM front end (CASE-040) shows customers use one | Out of scope per PROJECT.md. Replacing Bolt is excluded | Keep plan interfaces stable and JSON-friendly so any front end can call them |
| **Silent auto-retry of every failure** | Makes flaky runs look green | Hides real faults and makes outages longer | Bounded retry on recognised signatures only, always printed |
| **Auto-updating peadm itself or the PE version from a remote feed during a run** | Convenience | Unreviewed code in a production change; breaks air-gap | Version data ships in the module; operators update the module on their schedule |

## Feature Dependencies

```
Shared helpers (non-production environment, TLS client, parameter summary)
    └──required by──> Check registry (peadm::preflight)
                          ├──required by──> Check mode for upgrade / convert / add_replica / promote
                          ├──required by──> Backup gate ──required by──> Unattended upgrade
                          └──required by──> Failover readiness checks ──required by──> Planned role swap

Validated resumable steps (plan_step validation, idempotent steps, cleanup on failure)
    ├──required by──> Upgrade safety gates
    ├──required by──> Planned role swap (F-05 failed mid-way)
    └──required by──> Run journal (differentiator)

Post-upgrade verification gate ──required by──> Unattended upgrade
Backup that works for non-production environments ──required by──> Backup gate ──required by──> Rollback procedure
Rollback procedure ──enhances──> Unattended upgrade (failure path)

Planned role swap ──requires──> Availability-group awareness (A/B pins)
Planned role swap ──requires──> Replica add/rebuild (add_replica post-conditions)
Unplanned promotion ──shares steps with──> Planned role swap
Role swap exercise mode ──requires──> Planned role swap (proven)

Support bundle on failure ──enhances──> Diagnostics (D)

CD4PE air-gap integrity checks ──required by──> CD4PE upgrade resumability
CD4PE TLS input validation ──independent of──> CD4PE recovery after reboot
SCM install ──requires──> CD4PE install (shares the prompt flow and runtime)

Shared-CA bootstrap ──conflicts with──> default install flow (needs its own path)
```

### Dependency Notes

- **Check mode requires the shared helpers first.** The `production` assumption and the duplicated TLS clients would otherwise be copied into every check. Fixing them early also clears the two Blocker tickets (PE-39789, PE-46598).
- **Planned role swap requires resumability.** F-05 shows a swap that failed in the last step and was finished by hand. A swap that cannot resume is worse than the manual procedure.
- **Backup gate requires non-production-environment support.** `peadm::backup` and `restore` break on non-default environments, so a gate built on them would block those customers.
- **Rollback is mostly procedure and tests.** It needs the backup gate and a restore that is tested per scenario (R-01, R-02), not new plans.
- **CD4PE and SCM are largely independent of the PE work** and can run in parallel, but the common idea of check mode, resumability and diagnostics applies to them too.

## MVP Recommendation

Core Value is "succeed predictably, otherwise fail early, explain itself, recoverable". The first build should make the next upgrade or role swap safe to attempt.

Prioritize (in order):

1. **Shared foundations** (LOW-MEDIUM): one non-production-environment helper, one TLS client helper, step-name validation in `plan_step`, parameter summary, cleanup-on-failure for the known leftovers. These clear two Blockers and are prerequisites for the rest.
2. **`peadm::preflight` / check mode** for upgrade first, then promote and add_replica (MEDIUM): connectivity, version and path, cluster health, the incident-derived checks (eyaml DN, r10k host keys, A/B pins, legacy OID, node_manager version).
3. **Post-upgrade verification gate and whole-cluster version assertion** (MEDIUM): turns "reported success" into evidence.
4. **Backup gate and documented, tested rollback** (MEDIUM plus acceptance work): R-01 and R-02.
5. **Planned role swap** (HIGH) with readiness checks, then unplanned promotion.
6. **CD4PE hardening** (parallel track): TLS input validation, air-gap image integrity, DB-container check, recovery after patching. Cheapest and best evidenced.

Differentiators to take once 1 to 4 are in: unattended upgrade wrapper, upgrade plan dry-run, support bundle on failure.

Defer:

- **Role swap exercise mode, shared-CA bootstrap, inventory generation:** one or two cases each, depend on the above, or need PE-side research.
- **SCM beyond "optional install at the end of CD4PE install":** no evidence of what users need. Do a scoping spike first.
- **Run journal:** valuable but the `plan_step` fixes cover most of the need first.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---|---|---|---|
| Shared helpers (environment, TLS, parameter summary, step validation) | HIGH | LOW-MEDIUM | P1 |
| Check mode / preflight registry (upgrade) | HIGH | MEDIUM | P1 |
| Incident-derived upgrade checks | HIGH | LOW each | P1 |
| Post-upgrade verification gate | HIGH | MEDIUM | P1 |
| Failure diagnostics across tasks | HIGH | LOW-MEDIUM | P1 |
| Backup gate and rollback procedure | HIGH | MEDIUM-HIGH | P1 |
| Planned role swap and readiness checks | HIGH | HIGH | P1 |
| Compiler replace and A/B repair | HIGH | MEDIUM | P1 |
| CD4PE TLS inputs, air-gap integrity, DB check | HIGH | LOW-MEDIUM | P1 |
| CD4PE recovery after patching or reboot | MEDIUM-HIGH | MEDIUM | P2 |
| Unplanned promotion | MEDIUM-HIGH | MEDIUM | P2 |
| Known-flake bounded retry | MEDIUM | MEDIUM | P2 (needs research) |
| Unattended upgrade wrapper | MEDIUM-HIGH | LOW once P1 is done | P2 |
| Support bundle on failure | MEDIUM | MEDIUM | P2 |
| New PE release readiness process | HIGH | LOW per release | P1 (process) |
| Reattach / recreate CD4PE Bolt project | MEDIUM | MEDIUM | P2 |
| SCM install and maintenance | UNKNOWN | MEDIUM | P3 until scoped |
| Role swap exercise mode, shared-CA bootstrap | LOW-MEDIUM | HIGH | P3 |

## Comparable tooling

What other lifecycle tools offer, for calibration. This is the "what is expected" baseline.

| Tool | Relevant behavior | Confidence | Takeaway for peadm |
|---|---|---|---|
| PE built-ins (`puppet infrastructure status`, `pe_status_check`, `puppet-backup`, `puppet infrastructure upgrade compiler`, `provision/promote/forget replica`, `enable_ha_failover`) | Primitives, not workflows. `pe_status_check` gives role-scoped indicators and an infra summary plan. Promote, forget, and re-provision are separate manual commands. Docs warn promote without copied secret keys regenerates them | MEDIUM (docs fetched; indicator list not shown) | peadm's value is the orchestration around these: order, checks, resume. Use them, don't replace them |
| Red Hat Satellite `satellite-maintain` / `foreman-maintain` | `health check`, `upgrade check` (runs while the system is still at the old version), then `upgrade run`; backup and snapshot steps before upgrade; resumable steps | MEDIUM (docs found by search) | Closest analogue. Check, backup, upgrade, resume is the model to copy |
| `kubeadm` | `upgrade plan` lists what would change and what to upgrade first; preflight checks with a clear skip flag; documented etcd backup | MEDIUM (background knowledge) | Dry-run plan and preflight with an explicit override |
| GitLab Omnibus and similar | Documented required upgrade stops, version-path rules, background-migration checks before the next hop | MEDIUM (background knowledge) | Upgrade-path validation from data, which `data/pe_versions.yaml` could carry |
| Elastic / OpenShift upgrade assistants | Pre-upgrade deprecation and "upgradeable" conditions reported before change | MEDIUM (background knowledge) | Advisory catalog tied to target version |

## Gaps and open questions

- **Promote/failover code:** PE-39742 ("implement new peadm plans for automating DR activities") is Closed, but `plans/` has no promote or swap plan. Check whether the work shipped under another name, in another repo or was dropped, before designing.
- **cd4peadm location and current feature set:** it is a separate premium module. The research could not see its code. Decide whether this repo extends it, wraps it or absorbs it, and inventory what it already does (backup, preflight, SCM install).
- **SCM:** one reference only (the install prompt). Needs a conversation with the SCM product team.
- **`pe_status_check` availability** per supported PE version, and whether it can run from Bolt on all topologies.
- **pe-puppetdb reload failure (GJira-1, open Blocker):** root cause not known; a safe retry depends on it.
- **The CSV has no outcome data** (how many cases the tool prevented, time to resolve), so priority is by frequency and severity of the complaint, not measured impact.
- **PIM (CASE-040)** appears to be a separate front end that drives Bolt plans. Its relationship to peadm is not documented in the files read here.

## Sources

- `/home/matthew/Code/peadm.csv` (50 support cases, 52 Jira tickets), read in full. HIGH confidence for user need.
- `/home/matthew/Code/puppetlabs-peadm/.planning/PROJECT.md`, `.planning/codebase/CONCERNS.md`, `documentation/change-ledger.md`, `documentation/fix-log.md`, `documentation/test-scenarios.md`, `documentation/recovery/automated_recovery.md`, and `plans/`, `tasks/` listings. HIGH confidence for current status.
- [About the pe_status_check module (PE 2023.8)](https://help.puppet.com/pe/2023.8/topics/about-pe-status-check.htm). MEDIUM.
- [Identify operational issues affecting infrastructure nodes (PE 2025.9)](https://help.puppet.com/pe/2025.9/topics/operational-status-infra-nodes.htm), [Provision and enable a replica](https://help.puppet.com/pe/current/topics/dr_provision_replica.htm), [Configuring disaster recovery (PE 2023.8)](https://help.puppet.com/pe/2023.8/topics/dr_configuring.htm), [pe_status_check on the Forge](https://forge.puppet.com/puppetlabs/pe_status_check) (search results only; not opened). MEDIUM.
- [Upgrading Red Hat Satellite](https://docs.redhat.com/en/documentation/red_hat_satellite/6.16/html/upgrading_connected_red_hat_satellite_to_6.16/upgrading_satellite_upgrading-connected) and [foreman_maintain](https://www.rubydoc.info/gems/foreman_maintain/0.2.4) (search results). MEDIUM.
- kubeadm, GitLab, Elastic and OpenShift upgrade behavior from background knowledge, not verified this session. MEDIUM.

# Pitfalls Research

**Domain:** Bolt-based lifecycle automation for Puppet Enterprise (install, upgrade, failover/DR, day-2) plus CD4PE and Security Compliance Management (SCM), added to an existing production module (peadm 3.40.0)
**Researched:** 2026-11-10
**Confidence:** MEDIUM-HIGH. Failure classes are HIGH confidence (taken from `~/Code/peadm.csv` cases and tickets and verified against the code in this repo). Root causes inside PE core, CD4PE containers and SCM are MEDIUM or LOW where marked, because the CSV shows symptoms, not diagnoses. SCM has almost no field evidence (see Pitfall 17).

**Evidence tags used below:** `[CSV]` = case or ticket in peadm.csv. `[CODE]` = verified in this repo. `[INFER]` = my inference from the two, not confirmed by anyone. `[DOCS]` = vendor docs.

**Phase labels.** The roadmap does not exist yet, so these are proposed names for mapping. Re-map once it does.

| Label | Scope |
|-------|-------|
| **P-UPG** | Safe upgrades: pre-flight, resume, rollback |
| **P-DIAG** | Diagnostics and post-condition verification |
| **P-DR** | Failover, role swap, replica/compiler/DB node operations |
| **P-CD4PE** | CD4PE install, upgrade, patching, Bolt project reattach |
| **P-SCM** | SCM install and maintenance |
| **P-TEST** | Acceptance coverage (cross-cutting; first slice must land before P-UPG/P-DR changes) |

---

## Critical Pitfalls

### Pitfall 1: Reporting success without checking the post-condition ("success lies")

**What goes wrong:**
A plan or task finishes green while the thing it was meant to produce is absent. Examples in the evidence:
- `add_replica` prints success, but the replica is not classified and is missing from `puppet infra status` (CASE-022; PE-43490 asks for better result surfacing).
- `peadm::upgrade` reported success, then the master had repeating pe-puppetdb corrective changes and compiler "Puppet Server" error states in the console (CASE-017). PE-37220 (reports complete after a failed step) is the same class.
- `cd4peadm::upgrade` finished with "0 failures" while the `update_database_configuration` task returned `"status":"success"` with `"successful":false` and "no container named postgres" (CASE-005). The DB role passwords were never changed.
- `begin_at_step` with an unknown name makes every step print SKIPPING and the plan returns success `[CODE]` (CONCERNS.md, Known Bugs).
- Replica removal on PE 2021.x silently leaves both replicas registered `[CODE]`.

**Why it happens:**
Bolt marks a task green on exit code 0. Wrapper tasks swallow inner command failures and report them in JSON fields. Plans treat "the commands ran" as "the system is in the target state". Retry-heavy code (`_catch_errors`, retry loops) makes this worse because it converts failures to log lines.

**How to avoid:**
- Define a post-condition check per operation and make it a required final step, not an optional extra: after upgrade, `puppet infrastructure status` on primary and replica, every `pe-*` unit active, all nodes report the expected PE and agent version, a catalog compile for a canary node, and one Puppet run on the primary that reports zero corrective changes (catches CASE-017).
- After add/replace operations, assert the classifier group membership and trusted-extension values and the `puppet infra status` row, then fail the plan if absent (CASE-020, CASE-022).
- Wrapper tasks must exit non-zero when the wrapped command failed. Add a spec per task that feeds a failing inner command and asserts the exit code. Do the same for cd4peadm-style tasks that return `successful: false`.
- Validate `begin_at_step` against the known step list and fail on no match (already in CONCERNS as a known bug).

**Warning signs:**
- Plan summary says "completed" but no verification task appears in the output.
- Support cases that open with "it said success, but..." (CASE-017, CASE-022, CASE-005).
- Any `_catch_errors => true` without a following check of the result set.

**Phase to address:** P-DIAG (shared verification library), then consumed by P-UPG, P-DR, P-CD4PE. Build the library first; do not scatter per-plan ad hoc checks.

---

### Pitfall 2: Resuming a failed upgrade does not restore the preconditions the failed run destroyed

**What goes wrong:**
The upgrade is step-resumable via `begin_at_step`, but every step assumes the earlier steps left a clean state. When `upgrade-primary` fails and the operator re-runs from that step (CASE-002 re-ran the whole plan; CASE-049 reports the tarball not found), the preconditions are gone:
- `tasks/pe_install.sh` runs `rm -f "$PT_tarball"` right after extraction, before the installer runs `[CODE]`. A resume at `upgrade-primary` skips `preparation` (which downloads and verifies the tarball), so `tar -tf "$PT_tarball"` fails on a missing file. This is a probable cause of CASE-049 `[INFER]`, and it is certainly a defect on the resume path `[CODE]`.
- `systemctl stop pe-puppetdb` was already run on non-legacy compilers and nothing restarts it on failure `[CODE]`.
- `puppet` is stopped on all infra nodes, and the agent service is only restored in `finalize` `[CODE]` (Phase 0 P0-2 re-stops it on resume, but does not restore it on failure).
- The `delete-reports` symlink workaround is not restored on failure `[CODE]`.
- The extra-large `10-shortcircuit.conf` drop-in survives early `exit 1` paths `[CODE]`.
- The primary's pe.conf was rewritten in `preparation` (not restored).

**Why it happens:**
Steps were written as a forward-only script with cleanup on the happy path. "Resumable" was achieved by skipping steps, not by making each step idempotent and re-entrant. The fix for one resume hazard (P0-2) created the expectation that resume works generally.

**How to avoid:**
- Each step declares its own preconditions and re-establishes them (stage and verify tarball in any step that needs it; stop Puppet; re-assert drop-ins). Do not rely on earlier steps having run.
- Do not delete the tarball until the installer exits 0 (CONCERNS: "Installer tarball deleted before install").
- Use cleanup on all exits (`trap` in shell tasks; `ensure`-style cleanup in plans) for drop-ins, symlinks, and stopped services.
- Persist a small state record on the primary (for example `/opt/puppetlabs/server/data/peadm/upgrade-state.json`: target version, last completed step, installer log path). `begin_at_step` then defaults to the first incomplete step and the plan refuses a resume whose target version differs from the recorded one.
- Add a "resume at each step" acceptance scenario for every step, not only for step 1 (P-TEST).

**Warning signs:**
- A step uses a path or service state that only an earlier step produces.
- Re-running the same params file produces a different error than the first run.
- `systemctl list-units 'pe-*'` shows inactive units after a failed run.

**Phase to address:** P-UPG. This is the core of "recoverable". It must precede any rollback automation because rollback depends on knowing what state the failure left.

---

### Pitfall 3: Pre-flight checks that only test what is cheap, not what actually fails

**What goes wrong:**
Pre-flight is built around reachability and parameters (Bolt can reach the hosts, `puppet agent --version` works: CASE-034, CASE-035). But the real upgrade failures in the CSV come from conditions that those checks do not touch:

| Failure in CSV | Pre-flight that would catch it |
|---|---|
| Installer refuses a target released before the installed build even though the version number is higher (CASE-009) | Compare release dates, not just version numbers. P0-3 only catches `target < installed` by number `[CODE]` |
| pe-puppetdb reload fails during upgrade, orchestration refresh triggers it (CASE-002, GJira-1 Blocker) | PuppetDB and PostgreSQL health, free disk, pending restart state; capture service logs on failure |
| eyaml keys with an empty issuer DN break catalog compilation after 2025.11.2 (CASE-012, GJira-7) | `openssl x509 -noout -issuer` on the eyaml public key, warn when empty. This exact check does not exist anywhere yet |
| Code Manager SSH `invalid or unknown remote ssh hostkey` after upgrade (CASE-008) | If Code Manager uses SSH sources, confirm known hosts are set (`r10k_known_hosts`); module has `check_version_and_known_hosts` but only for the 2023.4 gate `[CODE]` |
| Compiler version skew errors `This compiler has a PE version of X... primary has Y` (CASE-045) | Expect it; verify all compilers are in the upgrade list and that the plan upgrades them. Pre-flight lists compilers found in PuppetDB and the ones given in params and fails on a mismatch |
| Duplicate A/B pins make `get_peadm_config` fail (CASE-016) | Run the same classifier sanity check as the first step of every plan |
| Legacy compiler OID gate (CASE-050, GJira-17) | Done in P0-5 |
| Unsupported PE version (CASE-003, PE-47850) | Done in P0-7, but the supported range still needs a release for each new PE line (see Pitfall 12) |
| Replica reports red toward compilers from `puppet infra status` (CASE-035) | Run `puppet infrastructure status` from both primary and replica and report differences; do not treat a green primary as proof |
| Direct upgrade jumps the installer will not allow, for example 2021.7 to 2023.0 (CASE-039) `[INFER]` | Encode supported upgrade paths in data and check them in pre-flight. Needs research: the exact rules live in PE docs |
| Cloud-DB check script missing from the installer dir (`is_cloud_database.rb: No such file`, CASE-046) | `[INFER]` a stale or partial extract directory; verify extract directory freshness |

**Why it happens:**
Pre-flight gets written from the happy path and from the tooling the author trusts (Bolt connectivity). Each failure is only seen once a customer hits it, so the list grows reactively and stays incomplete.

**How to avoid:**
- Keep pre-flight as a data-driven table of named checks (`id`, severity BLOCK/WARN, what it protects against, linked case/ticket). Every new support case adds a row. This is also the traceability the ledger requires.
- Distinguish BLOCK (installer will refuse or data will be lost) from WARN (known regression for this target version, e.g. the eyaml empty-DN case when target >= 2025.11.2).
- Run pre-flight as its own plan (`peadm::preflight`) that can be run days before the change window (CASE-010, CASE-029, CASE-034, CASE-035 are customers asking support for exactly this). `peadm::upgrade` calls the same checks and refuses to start on BLOCK.
- Make known-bad-release knowledge data, like `data/pe_versions.yaml`, so adding "2025.11.2 + empty-DN eyaml = warn" needs no plan code change.
- Pre-flight must run before `systemctl stop puppet`. Currently `preparation` stops Puppet immediately after tarball verification, and `upgrade-primary` stops PuppetDB on compilers before the installer can refuse `[CODE]`; any BLOCK condition that only appears at installer start is already too late. Where the installer's own pre-check is the only source of truth, run it before stopping anything if it can be (needs research, see Gaps).

**Warning signs:**
- A new case describes a failure that no check in the table could have predicted.
- Pre-flight output contains only OK lines about connectivity.
- Customers ask support for a "health check before roleswap/upgrade" (CASE-010, CASE-029, CASE-034).

**Phase to address:** P-UPG (framework and upgrade checks), P-DR (failover checks, Pitfall 9).

---

### Pitfall 4: Treating rollback as "run the upgrade with the old version number"

**What goes wrong:**
Customers try exactly that and are refused: the installer rejects an older target chronologically, even from a newer release line (CASE-009). Others ask whether peadm backup or `puppet-backup` restores directly, or whether they must clean-install the old version (CASE-036). One customer rolled back PE 2025.11.2 to a snapshot after the eyaml regression and it worked only because they had a VM snapshot (CASE-012). Rollback does not exist in the module (CONCERNS: "Rollback for failed upgrades").

Hazards for a naive rollback implementation:
- A rollback that tries to reinstall the old version over the new one will fail at the installer refusal. The only real paths are restore from backup/snapshot on the pre-upgrade state, or rebuild.
- Partial upgrades leave mixed-version infrastructure. Restoring only the primary from backup while compilers/replica stay upgraded produces the same version-skew errors as CASE-045 in reverse.
- PostgreSQL schema migrations run by the new PuppetDB/console services may not be reversible; restoring files without the database leaves a broken pair. `[INFER]`, needs PE docs confirmation.
- `peadm::restore` is destructive (`DROP SCHEMA public CASCADE`) and has no executed SQL tests `[CODE]`.
- VM-snapshot rollback on one node of a replicated pair (CASE-015 asks exactly this) risks the primary and replica disagreeing on database state `[INFER]`.

**Why it happens:**
"Rollback" is thought of as the inverse of upgrade. PE's installer is forward-only, so the inverse operation is a restore, and a restore is only as good as the backup taken before and the order of restoring nodes.

**How to avoid:**
- Define rollback as three explicit tiers and implement them in this order:
  1. **Abort-and-recover (no data change):** failure before the installer touched the primary. Restart stopped services, restore Puppet service state, remove drop-ins and symlinks. Fully automatable.
  2. **Roll forward:** failure partway. Re-run from the failed step with the preconditions re-established (Pitfall 2). This is the main path and the cheapest.
  3. **Restore-based rollback:** requires a verified backup taken by the same plan run. Treat as a guided plan with explicit confirmation, not a one-click "downgrade".
- Make the upgrade plan take (or require proof of) a backup in pre-flight when the user asks for rollback capability: `peadm::backup` completed, backup file exists and is non-empty, and records the PE version it was taken at. Restore refuses a backup whose version differs from the installed binaries' version target.
- Refuse `peadm::upgrade` with a lower version and point to the restore plan (done in P0-3 for number comparison). Also detect the release-date refusal (CASE-009) before stopping services.
- Never ship a rollback implementation without an acceptance scenario that actually performs it on a real cluster and checks `puppet infra status` after (P-TEST).
- Document what is not recoverable (e.g. data written after the backup).

**Warning signs:**
- Rollback design that calls `peadm::upgrade` with a lower version.
- No test that restores into a cluster whose compilers are at a different version.
- A restore implementation with no pre-check that backup version equals installed version.

**Phase to address:** P-UPG (tier 1 and 2 first, tier 3 later in the same phase or a follow-up). Flag for deeper research: PE restore compatibility and schema-migration reversibility.

---

### Pitfall 5: Hard-coded timeouts and fixed sleeps around CA, certificate, and service readiness

**What goes wrong:**
Operations that touch the CA or wait for services fail on slow or loaded systems with timeouts nobody can change:
- Role swap repurposing the old master failed with a "cert-loading timeout" and the operator finished the leftover tasks by hand (CASE-029).
- `enable_ha_failover` CA queries need adjustable timeouts (GJira-11).
- A step failed with exit code 6 from `puppet agent` because "Connection to [CA] failed ... timed out connect operation after 120.1 seconds" (CASE-047) `[INFER: the agent run was routed to a stopped or unreachable node in its server list or CA route during the upgrade; unconfirmed]`.
- `cd4peadm::ctl restart` waited 15 x 5 seconds for the console, then gave up while the containers were still starting after patching (CASE-030, GJira-12) `[CSV, code of cd4peadm not in this repo]`.
- peadm has many retry loops of 3 to 15 seconds with fixed attempt counts, some written to hide warm-up races (PE-44867, PE-46689) `[CODE]` (CONCERNS).

**Why it happens:**
Timeouts are written to fit the developer's lab. Retry loops are a fast fix for a race and never get replaced with a readiness check. Production hosts under PCI scanning, big databases or slow disks take longer.

**How to avoid:**
- Replace fixed sleeps with readiness polling against the specific endpoint that the next step needs (the `status` API of the service, `puppet infrastructure status`, a successful RBAC token request), with a deadline parameter exposed on the plan (default generous, overridable).
- Centralize waiting in one shared function and make every plan call it. CONCERNS already notes at least six independent retry loops.
- Whenever a wait times out, print what was being waited for, the last observed state and the last 20 lines of the relevant service log (Pitfall 6).
- For CA queries during role swap and replica provisioning, expose a `ca_timeout` style parameter and pass it through rather than relying on the PE default.
- Order service stops so the primary's own agent run does not try routes to nodes that are down (use an explicit `--server` for runs executed by the plan) `[INFER]`.

**Warning signs:**
- Same plan fails on a loaded prod and passes in CI.
- A `sleep` or `retry` with no log of what condition is awaited.
- Cases that say "Subsequent attempts succeed" (CASE-002).

**Phase to address:** P-DIAG (shared wait helper), applied in P-UPG and P-DR.

---

### Pitfall 6: Bare exit codes and invisible root causes

**What goes wrong:**
The Bolt output says "The task failed with exit code 1" or `returned: 6`, and the actual reason is in an installer log, `journalctl`, or a container log that the operator must find by hand (CASE-002, CASE-009, CASE-011 "failed at the first step", CASE-047, CASE-005). Support then asks for a support bundle. CASE-011 contains no detail at all.

**Why it happens:**
Tasks write errors to stderr or to files; plans do not collect them. Bolt truncates and hides output at default verbosity. Secrets constraints make authors cautious about printing logs.

**How to avoid:**
- Standard failure report from every long task and plan: command, exit code, tail of the relevant log, state of failed units, disk and memory, timestamp. P0-6 did this for `pe_install` only `[CODE]`; extend it to `puppet_infra_upgrade`, `puppet_runonce`, restore, add_replica, and the CD4PE and SCM plans.
- For `puppet infrastructure configure` failures (CASE-002), capture the specific failing resource lines and the journal for the units involved, not just the installer tail.
- Sanitize the output with the existing `peadm::sanitize_log_text` before printing, because logs contain secrets (Pitfall 14).
- Add a `peadm::support_bundle`-style collector that gathers logs from all nodes into one directory on the controller, so the operator can attach it (CASE-010 and CASE-029 customers already upload support bundles).
- Distinguish failure kinds in structured errors (`peadm/upgrade-precondition-failed`, `peadm/service-timeout`, `peadm/installer-failed`) so retry logic does not match on strings (CONCERNS notes the `peadm/rbac-auth-failure` string literal duplicated across three files).

**Warning signs:**
- A support case whose first reply is "please send the logs".
- A failure message that contains only an exit code.

**Phase to address:** P-DIAG, early. Everything else benefits.

---

### Pitfall 7: Fixing the pe-puppetdb reload failure by guessing

**What goes wrong:**
GJira-1 is Blocker severity: upgrade 2023.8.8 to 2025.12.0 fails when `pe-puppetdb` reload exits 1, systemd schedules a restart, the orchestration-services reload happens immediately afterwards, and `puppet infrastructure configure` returns 6 (CASE-002). A later reload succeeds, and re-running the plan was reported as still failing. The risk is encoding a workaround (extra sleep, retry, `systemctl restart`) without knowing the cause, then shipping it as a "fix" that fails on the next release line. Phase 0 deliberately only mitigated diagnosability (P0-6).

**Why it happens:**
The symptom is a race between two services restarting. A retry hides it in most runs. PuppetDB reload failing is plausibly a PE-core or JVM problem (the reload path in the unit file), not peadm logic `[INFER]`.

**How to avoid:**
- Treat as a research and reproduction item, not a coding item: reproduce on 2023.8.8 to 2025.12.0 with extra-large and standard topologies, collect `journalctl -u pe-puppetdb` around the reload, and determine whether the failure is in PE core (then file upstream and add a pre-flight WARN) or in a peadm-controlled ordering (for example the plan's earlier `systemctl stop pe-puppetdb` on compilers and the pe.conf rewrite) before writing code.
- If a plan-level mitigation is justified, make it narrow: on installer exit 6, check specifically for the pe-puppetdb reload failure signature in the installer log, wait for PuppetDB readiness, and re-run the installer in the documented repair mode. Never blanket-retry the installer, because a second run on a half-migrated database can compound damage `[INFER]`.
- Log the signature check result so a future case can tell if the mitigation fired.
- Gate the mitigation on version range in data.

**Warning signs:**
- The proposed fix is "sleep before reload" or "retry 3 times".
- No reproduction on a real cluster before merge.

**Phase to address:** P-UPG, scheduled after P-TEST has a runnable upgrade scenario for 2023.8 to 2025.12. Flag: needs deeper research.

---

### Pitfall 8: Assuming a tidy classifier (single A, single B, `production` only, no legacy compilers)

**What goes wrong:**
peadm reads cluster topology from classifier node groups and trusted-extension OIDs, and fails or silently misconfigures when the real cluster does not match the assumption:
- `get_peadm_config` expects exactly one A and one B pinned; after a role swap or hand edits it found two A pins, and compiler replacement never ran (CASE-016, PE-43987).
- The same `puppetdb_host` listed twice in Legacy Compiler Group B caused a race (PE-43572, Bug High); a compiler group with 3 hosts and 2 ports broke `pe_format_urls` (CASE-041); mixed puppetdb/database hosts in compiler groups A and B left a customer unsure if it is normal (CASE-042).
- A version of peadm converted compilers to legacy compilers during upgrade (PE-40239, Blocker); upgrade fails when legacy compilers exist (PE-36212, PE-36355); `convert` fails (PE-41637, PE-44017, PE-39099).
- Infrastructure that does not use the `production` environment breaks install, backup, restore, migrate (PE-39789 Blocker, PE-39465, PE-46598 Blocker); migrate does not restore default classifier groups' classification (PE-45758).
- Third-party module changes break peadm: `puppetlabs-node_manager` v0.7.6+ and v1.0.1 (PE-36915, PE-39099); CASE-003 shows node_manager v1.1.0 and stdlib 9.7.0 in a user's modulepath.
- A task checked a classifier value with plain truthiness where the real value is the string `"false"` `[CODE]` (`tasks/check_legacy_compilers.rb`, unverified).

**Why it happens:**
Real clusters accumulate manual edits and history from older peadm versions. Test clusters are built fresh by the same code, so tests never see drift.

**How to avoid:**
- Pre-flight "topology sanity" check that runs first in every plan: exactly one A and one B per group, no duplicate hosts in puppetdb_host lists, compiler count and ports equal, all trusted extensions present, env name resolved from the node group not assumed. Failing output names the offending groups and nodes and says which plan or manual step fixes it.
- Never hard-code `production`; read the environment from the PE Infrastructure node groups (parameter `node_group_environment` exists; apply it consistently in backup, restore, migrate, install).
- Build a fixtures library of real-world drifted classifier states (anonymized from the cases above) and unit-test the config reader against each. Add acceptance scenarios for "legacy compiler present", "non-production environment", "post role swap".
- Pin the Bolt-side module versions (`puppetlabs-node_manager`, `stdlib`) in metadata and run a modulepath sanity check at plan start (name, version, known-bad list).
- Treat every classifier-writing plan (`update_classification`, `convert`, `add_compilers`) as dangerous: dry-run output of the diff first, and make writes idempotent so re-running yields no change.

**Warning signs:**
- Fixes that add a special case for one customer's classification.
- Tests only run against clusters peadm itself just installed.
- A plan that silently picks the first of several matches.

**Phase to address:** P-DR (A/B awareness after role swap is the dominant trigger), P-UPG (legacy compiler logic), P-TEST (drift fixtures).

---

### Pitfall 9: Treating failover and role swap as "promote, then add the old primary back"

**What goes wrong:**
The customers' own runbooks show the real shape of the problem. The manual procedure in CASE-015 has nine steps (freeze Code Manager, backup, pre-flight on replica for CA/CRL/secret keys/SANs/RBAC token/NTP, check streaming replication lag, stop services, `puppet infrastructure promote replica`, repoint LB, verify, rebuild old primary as replica). CASE-023 and CASE-024 follow the same flow. The failure modes:
- Peadm assumes A is the primary and B is the replica; after promotion the roles flip, the classifier pins and the peadm availability-group state are stale (CASE-016, PE-43987). Subsequent peadm plans (add_compilers, upgrade) fail or touch the wrong nodes.
- The replica's certificate had a different TTL and SAN content from the primary's (CASE-015); if the VIP name is not in the SANs, agents behind the load balancer fail TLS after cutover.
- Secret key files (`keys.json` for orchestrator and console services, eyaml keys) must be present on the replica; peadm copies them with mode 0644 `[CODE]` (CONCERNS), and a pre-flight that only checks file existence misses key mismatches.
- Agents may or may not have `server_list` (CASE-024); with a LB fronting only the active primary the agent side needs no change, otherwise it does. Peadm cannot know, so it must ask or detect.
- Reusing the old primary's certname for the rebuilt replica requires forget, `ca clean` and a fresh agent install before `add_replica`; any leftover from the failed or stopped primary breaks `add_replica` (CASE-022: replica auto-replaced by another process, plan reported success but classification missing).
- The cert-loading timeout at the "repurpose old master" stage (CASE-029).
- Replication state: promoting while streaming lag is non-zero loses data. Restoring one node from a VM snapshot after promotion risks split state (CASE-015 asks about this) `[INFER]`.
- PE 2021.x `add_replica` leaves the old replica registered `[CODE]`.
- Mixed OS or PE versions between primary and replica during OS upgrade (CASE-024): is it supported is a vendor-policy question, and an automation that allows it silently is dangerous.

**Why it happens:**
Failover is an infrequent, high-stakes operation with many manual preconditions. It is tempting to automate the happy-path commands (`promote`, `provision`) and skip the checks and the re-converge. PE-39742 (new plans for DR activities) closed, but there is no promote/role-swap plan in `plans/` today `[CODE]` (only `add_replica`, `replace_failed_postgresql`, `add_compilers`, `migrate`).

**How to avoid:**
- Build the failover plan as: (1) `peadm::preflight_failover` (read-only; reuse CASE-015's nine-point checklist as the check table: CA cert/key/CRL match, SANs include the agent-facing name, secret key files present with matching fingerprints, RBAC token valid for more than the expected duration, replication lag near zero for all databases, NTP skew, ports open, Code Manager frozen), (2) `promote`, (3) re-converge classification and A/B state, (4) verify, (5) a separate, explicit `rebuild_replica` plan. Each stage is a separate invocation with its own output so a failure in (5) does not look like a failure of (2). CASE-029 shows that the combined flow already failed in the last stage.
- After promotion, update the classifier A/B pins and peadm-managed trusted extensions in the same plan, and make `get_peadm_config` tolerate both orders. Add a spec fixture for post-swap state.
- Never use VM snapshot restore as the rollback in the plan. Document it as operator-owned.
- Make load-balancer and `server_list` handling an explicit, documented step with a parameter, not silent.
- Test on mixed versions: a non-prod cluster at 2025.10 against prod at 2023.8 was a stated worry (CASE-023). Run the scenarios on at least two PE lines.
- Require a verified backup before promote (Pitfall 4).

**Warning signs:**
- Failover plan with no replication-lag check.
- Plan that takes both promote and rebuild in one run with no stage output.
- Acceptance tests that only run `add_replica` on a fresh cluster.

**Phase to address:** P-DR. Flag for deeper research: A/B state after promote on 2023.8 vs 2025.x; `puppet infrastructure promote replica` behavior when primary is stopped cleanly rather than failed.

---

### Pitfall 10: Node replacement plans that fail on their most common input

**What goes wrong:**
- `peadm::replace_failed_postgresql` fails when `failed_postgresql_host` equals `primary_postgresql_host` (PE-41341). That is the likely scenario; a failure there means the plan fails in its primary use case. `plans/replace_failed_postgresql.pp` has no spec `[CODE]` (CONCERNS).
- A replaced PostgreSQL node did not receive trusted extensions, so it never classified as pe-postgresql and never got the PuppetDB class (CASE-020).
- `add_replica` with external replica database fails (PE-36451).
- `add_compilers` fails first in `get_peadm_config` (CASE-016).
- Replacing a compiler/replica that an "internal process" auto-replaced under the same name leaves stale certs and classification (CASE-022).

**Why it happens:**
Replacement plans combine cert handling, trusted extensions, classification, pg_hba edits and PuppetDB map entries, and each is tested separately or not at all. The reproduction needs a cluster in a failed state, which unit tests do not build.

**How to avoid:**
- Write the replacement plan around the sequence "forget, clean cert, issue cert with required extensions at CSR time, install agent, classify, converge, verify", and verify each of those as a check (Pitfall 1).
- Insert trusted extensions via CSR attributes at install time (`insert_csr_extension_requests` exists with no spec `[CODE]`; add one).
- Cover each replacement path with a scenario in the catalog (several exist in `spec/acceptance/scenarios.yaml`; confirm each has a runnable implementation, not only a catalog entry).
- Include a "fresh host reusing a failed host's certname" case.

**Warning signs:**
- A replacement plan whose spec mocks every task.
- No acceptance scenario for the exact input combination in a ticket.

**Phase to address:** P-DR, with specs landed in P-TEST first.

---

### Pitfall 11: Certificates, CRLs and key formats treated as opaque strings

**What goes wrong:**
The CRL/SSL error class is the single most repeated cause across PE and CD4PE:
- CD4PE 5.18.0 aborts with `ssl_crl does not look like a CRL (no "-----BEGIN X509 CRL-----" header found)` for DigiCert-issued chains (CASE-006, CASE-013, GJira-5). Public CAs publish CRLs in DER form, and the check is a plain PEM header test, so a DER download converted to PEM still failed for the user until fixed upstream `[INFER]`. Likely a cert chain pasted where a CRL was expected, or multiple CRLs concatenated.
- Non-RSA keys rejected because the code did `OpenSSL::PKey::RSA.new` (CASE-032, CDPE-7433).
- `Could not parse the PKCS7: no start line` while decrypting `cd4peadm::config` after a certificate renewal (CASE-018): a hiera-eyaml decryption problem in the Bolt project data (keys, common.yaml encoding, line endings or key file mismatch) `[INFER]`.
- hiera-eyaml with an empty-DN self-signed key stops working inside JRuby after a PE patch release (CASE-012, GJira-7).
- Shared-CA design where internal PE certnames (`console-cert`, `saml-cert`) already exist on the CA breaks the installer (CASE-044).
- The VIP name missing from SANs; short-TTL certs on a replica (CASE-015); `pe.repo` URL changing after migration (CASE-038); the PE CA fingerprint not matching after changing `ca_server` (CASE-044).
- peadm itself: `check_legacy_compilers.rb` disables TLS verification; ~15 tasks each build their own TLS client `[CODE]` (CONCERNS).

**Why it happens:**
Cert handling is done by string checks and hand-rolled `OpenSSL` calls with a single assumed format (PEM, RSA, one cert per file). The inputs come from users' enterprise PKI, which differs from lab self-signed material.

**How to avoid:**
- One shared cert/key validation library (Ruby, in `files/`) used by all tasks and by the CD4PE/SCM plans: parse with `OpenSSL::X509::CRL.new`/`OpenSSL::X509::Certificate.new` (accepts PEM and DER), accept RSA, EC and Ed25519 via `OpenSSL::PKey.read`, split chains and verify chain order, check key-to-certificate match, check expiry and CRL `nextUpdate` (public CRLs expire in days; a pasted CRL goes stale `[INFER]`), check SANs include the advertised hostname. Error messages state what was found and what was expected.
- Support both inline PEM and file-path inputs (GJira-10 did this for CD4PE) and normalize on the way in.
- Pre-flight check cert/CRL state before upgrade and before role swap: expiry horizon of CA, primary, replica and service certs; CRL freshness; CA/key pair match.
- Never bypass verification (replace `VERIFY_NONE` with the shared helper).
- Unit-test with a fixture set: DER CRL, PEM CRL, chain with intermediates, EC key, empty-DN cert, CRLF line endings, trailing whitespace.

**Warning signs:**
- A check that is `include?('-----BEGIN ...')`.
- A parameter called `*_crl` or `*_cert` documented only as "the PEM content".
- A cert-related case that says "worked in lab".

**Phase to address:** P-DIAG (shared library and pre-flight cert checks), reused by P-CD4PE and P-SCM (SCM manual TLS also requires chain, key and CRL `[DOCS]`).

---

### Pitfall 12: Version support as a manual release treadmill

**What goes wrong:**
A customer on the newest PE cannot upgrade because the published peadm does not know the version (CASE-003, PE-47850; peadm 3.38.3 against PE 2025.12.0). The supported range is data now (P0-7), but each new PE line still needs a peadm release, and version gates are scattered (CONCERNS: `pe_db_names` ladder, mixed `versioncmp`/`SemVerRange`). The boundary check may mis-handle `2026.0.x` `[CODE]` (CONCERNS "Supported PE range boundary", not covered by specs). The faster Latest/Latest-1 lifecycle cadence (CASE-043) increases the frequency.

**Why it happens:**
Strict whitelisting protects against untested versions but makes every PE release a blocking event. Gates added per feature accumulate.

**How to avoid:**
- Treat "new PE release" as a recurring process with a checklist and a job: nightly run of the upgrade scenario to the newest available PE build; on pass, a bot PR bumps `data/pe_versions.yaml`.
- Replace the single boundary with explicit tiers: `tested`, `allowed with warning` (newer patch within a known line), `refused`. `permit_unsafe_versions=true` already exists for the override.
- Fix the boundary semantics and add the three specs CONCERNS suggests (`2026.0.1`, `2026.0.99` supported; `2026.1.0` unsupported).
- Centralize the version-feature gates in one function and make plans ask feature questions ("does this version use pg_database_owner?") rather than compare version numbers.
- Do not tighten `oldest: '2019.7'` without a decision (PROJECT.md out-of-scope note); but acknowledge that nothing older than 2023.8 is tested.

**Warning signs:**
- New plan code that contains `versioncmp(` or a literal version number.
- Customer cases appear within days of each PE release.

**Phase to address:** P-UPG (boundary fix and tier model); P-TEST (nightly newest-version job).

---

### Pitfall 13: Version-skew windows during upgrade are service-affecting and not communicated

**What goes wrong:**
After the primary is upgraded, compilers on the old version log "This compiler has a PE version of X ... primary has Y" and fail catalog compilation (CASE-045). The customer expected one installer run to handle every node. Peadm does upgrade compilers in later steps, but a failure partway (or a resume) leaves agents seeing errors from compilers behind the load balancer. Also, `puppet infrastructure status` from the replica may show red toward compilers (CASE-035), which makes health state ambiguous.

**Why it happens:**
PE's architecture requires compiler-by-compiler upgrades. The automation hides that complexity but not the user-visible consequences.

**How to avoid:**
- Document and print the expected skew window at plan start: which node classes will serve errors and for how long.
- Remove compilers from the pool while they are at a different version where the topology permits it (needs research on load-balancer pool management; peadm does not control the LB `[INFER]`).
- Report, at the end of every run, a version table for every node (PE version, agent version) and fail if any differ.
- Keep per-compiler upgrade steps idempotent so re-runs only touch the lagging ones.

**Warning signs:**
- `puppetserver.log` errors matching "ensure that the PE versions are consistent".
- Final plan output does not list node versions.

**Phase to address:** P-UPG, verification in P-DIAG.

---

### Pitfall 14: Secrets in task parameters, logs, files and the Bolt controller

**What goes wrong:**
- CD4PE database role passwords were visible in the Bolt debug log of CASE-005 (`ALTER ROLE cd4pe WITH PASSWORD '...'` passed as a task parameter, then pasted into a support case). Any customer who attaches a debug log leaks credentials.
- peadm leaves `console_admin_password` in `/tmp/pe.conf`, copies secret key files with mode 0644, writes the admin RBAC token with the default umask in `/root/.puppetlabs/token` `[CODE]` (CONCERNS).
- The Bolt project holds the keys that decrypt CD4PE's configuration; the project is also the only place where auto-generated DB passwords exist (CASE-019, CASE-028).
- Upgrade pre-flight and failure reports will newly print log tails and config (Pitfall 6), which can print secrets.
- CI workflows pass secrets inline and use unpinned third-party actions (CONCERNS).

**Why it happens:**
Bolt passes task parameters as JSON on stdin and logs them at debug. Plans use plain strings, not `Sensitive`. Debugging output is expanded to be helpful without a redaction pass.

**How to avoid:**
- Use Bolt `Sensitive` parameters and `"sensitive": true` in task metadata for every password, token and key; pass secrets through files with mode 0600 or stdin, not command lines.
- All new diagnostics go through `sanitize_log_text` and a unit test with a fake secret in the input; add a regex list for `password`, `token`, `PRIVATE KEY`, `ENC[`.
- Fix the three known permission defects first (CONCERNS: `copy_file` mode, `pe.conf` cleanup, token mode) before adding code that copies more files for failover (Pitfall 9 does more copying).
- In the CD4PE plans, back up the Bolt project key material as part of the install and tell the operator to store it (Pitfall 17).
- Tell users in the docs that a Bolt `--log-level debug` file is sensitive.

**Warning signs:**
- A task whose metadata lacks `"sensitive"` on a `password` parameter.
- New code that `cat`s a config file into the failure message.

**Phase to address:** P-UPG for the existing three defects (small and independent), P-DIAG for the sanitizer, P-CD4PE for CD4PE parameters.

---

### Pitfall 15: Air-gapped assumptions in download, verify and image-handling code

**What goes wrong:**
- CD4PE air-gapped install: image tarball upload produced `unexpected EOF` and "payload does not match any of the supported image formats" (CASE-019): a truncated or partially transferred image reached podman, and a path that was a file was treated as a directory (`.../puppet-dev-tools_5.16.0.tar.gz/index.json: not a directory`) `[CSV; root cause INFER]`.
- CD4PE air-gapped upgrade 5.14 to 5.18: the DB container was not found mid-upgrade (CASE-005), and 5.14 to 5.15.1 left every pipeline failing with "Error while committing the transaction" (CASE-031, GJira-14). In the primary internet-connected environment the same steps worked, so the difference is the manual image staging `[INFER]`.
- PE: the tarball must exist for the exact name peadm expects (PE-43373 "Exact name of tarball"; CASE-049); extra agent repo tarballs are needed if `pe_repo` classes are declared (`documentation/upgrade.md`); the download step relies on GPG verification that silently degrades (CONCERNS).
- SCM docs do not describe a fully offline install, only a mirror registry `[DOCS]`.

**Why it happens:**
Online installs always work for the developer. Offline staging is a manual process with human-copied multi-GB files, and the product expects exact names, tags and checksums.

**How to avoid:**
- An "offline bundle manifest": for each version, a list of required artifacts (PE tarball, agent repo tarballs per platform, CD4PE five images, SCM images) with SHA-256. A `peadm::offline_check` (and CD4PE equivalent) plan verifies presence, name and checksum on the staging host and again on the target after upload, as pre-flight. Failure messages list missing or mismatching files.
- Verify with `podman load --input` or `skopeo inspect` on the target as a dry check before changing the running version.
- For container images use a content check (tar listing and `manifest.json` or `index.json` present) as P0-4 did for the PE tarball.
- Never delete the staged artifact before the consumer finishes (Pitfall 2).
- CD4PE upgrade in air-gapped mode must back up the database before touching the DB role (Pitfall 18) because failure here is the common one.
- Test both online and offline modes in acceptance for every install and upgrade scenario; the CASE-005/CASE-031 flows only fail in offline mode.

**Warning signs:**
- Upload code that reports success after `scp` without a checksum.
- Docs that tell the user to put files in a directory without naming files.

**Phase to address:** P-UPG (PE offline check), P-CD4PE (image bundle), P-SCM (registry mirror).

---

### Pitfall 16: CD4PE restart, patching and reboot are not designed for

**What goes wrong:**
- After RHEL patching, `bolt plan run cd4peadm::ctl action=restart` restarted all four containers back-to-back, waited 76 seconds, and gave up (CASE-030, GJira-12).
- After a power outage, code deployments through CD4PE failed and the log view was blank (CASE-026).
- After upgrade, patch and reboot "a number of things went wrong, leaving the system in a fragile state" (CASE-033).
- Pipelines stuck pending with Java heap OutOfMemoryError; the heap dump path already existed (CASE-027).
- `cd4peadm::uninstall` crashes with `NoMethodError` on a missing postgres pod (CDPE-6936), so cleanup of a broken install cannot finish.
- A trusted-cert file with permission denied after `upload_trusted_certs` (CDPE-6941).

**Why it happens:**
CD4PE runs as podman containers under systemd units with start-order dependencies (database before backend before UI). The module's `ctl` restarts in a fixed order with no per-container readiness. Podman containers on RHEL (rootful vs rootless, cgroups, SELinux labels, `systemctl enable` linger) behave differently after reboot or package updates `[INFER]`. Memory sizing is a fixed default.

**How to avoid:**
- Express dependencies explicitly: systemd `Requires=`/`After=` on units or sequential start with per-service health checks (DB accepts connections, backend health endpoint, UI responds) and a long deadline parameter. Start with the database, wait, then others.
- A `cd4peadm`-style `status` plan that reports container state, health, disk, memory, and last log lines, used both as pre-flight and as post-reboot recovery tool.
- A documented and tested "post-patching" scenario: reboot the host, run `ctl status`, run `ctl start`. Put it in the acceptance catalog as a scenario (the current catalog is PE-centric `[CODE: spec/acceptance/scenarios.yaml has 29 scenarios, check whether any are CD4PE]`).
- Make heap and memory sizing configurable and validate against host memory in pre-flight. The preflight shown in CASE-019 checks 7.45 GiB of memory, so the sizing logic exists; the heap setting does not follow it `[INFER]`.
- Make uninstall tolerant of missing resources (idempotent), and test it against a half-installed state.

**Warning signs:**
- A restart plan with a fixed `sleep` or 15 attempts at 5 seconds.
- No reboot test in the CD4PE acceptance matrix.

**Phase to address:** P-CD4PE.

---

### Pitfall 17: Losing the CD4PE (and SCM) Bolt project, then being unable to reattach

**What goes wrong:**
A customer deleted the Bolt project that created CD4PE and asked how to recreate and reattach it (CASE-028). The project holds: `bolt-project.yaml` (version, module), `inventory.yaml`, `data/common.yaml` with eyaml-encrypted `cd4peadm::config`, the PKCS7 keys under `keys/`, and the staged image cache (CASE-019 output shows the generate_config creating keys and `common.yaml`). Without the keys the config cannot be decrypted (the CASE-018 error family) and the generated DB passwords are unrecoverable from the project. Operators hit `Could not parse the PKCS7` after certificate renewal (CASE-018) because the renewal process edited encrypted data.

**Why it happens:**
The installer creates the state on first run on the operator's machine and nothing tells them it is the only copy. SCM docs recommend its own VCS repo for the project `[DOCS]`.

**How to avoid:**
- Build a `reattach` plan that reconstructs a project from the running instance: read the container environment/config on the target, regenerate `inventory.yaml`, create fresh keys, re-encrypt, and write `common.yaml`. Needs research on what is recoverable from the running containers (DB passwords are in container env, so likely yes `[INFER]`).
- At install, write a manifest and print a clear message: "back up `<project>/data` and `<project>/keys`". Offer an export plan that produces a tarball of project state plus the instance's non-secret config.
- Treat certificate renewal as its own plan that decrypts, edits and re-encrypts through the supported lookup, never hand-edits `common.yaml` (CASE-018). Validate `common.yaml` parses and decrypts before applying.
- Support the "path to file" variant for `ssl_cert_chain` and `ssl_crl` (GJira-10) so no PEM sits inside the encrypted blob.

**Warning signs:**
- Install docs with no "what to back up" section.
- Support tickets about decrypt failures after hand edits.

**Phase to address:** P-CD4PE. Flag for deeper research: what runtime state of a CD4PE instance can seed a reattach.

---

### Pitfall 18: CD4PE upgrade is not transactional, and database changes happen before the checks

**What goes wrong:**
`cd4peadm::upgrade` in CASE-005 and CASE-014 reached `update_database_configuration` and failed there ("Failed to update database configuration. Check postgresql logs and re-run the install plan"). In CASE-005 the postgres container was not found, but the plan went on to report `Finished: plan cd4peadm::upgrade`. In CASE-031/GJira-14 the upgrade finished but every pipeline run died with "Error while committing the transaction", which looks like a schema or role problem that the upgrade left behind `[INFER]`. There is no backup step, no rollback, and no resume record for CD4PE (`[CSV]` only; the cd4peadm code is not in this repo).

**Why it happens:**
The DB step is part of the install-role pipeline (`install::roles::database`), designed for install and reused for upgrade. The pipeline pulls new images, stops the old containers, and then changes DB config, in an order that makes a failure leave a half-upgraded stack.

**How to avoid:**
- Pre-flight: DB container running and accepting connections, disk space for new images and a dump, all new images present and loadable (Pitfall 15), runtime version, `bolt` version (the plan already checks this).
- Back up the CD4PE database (`pg_dump` from the container) and the Bolt project state before any change; record the path in the plan output. A failed upgrade then has a documented path: restart the old containers (tag unchanged) and restore the DB if the schema was modified.
- Do not stop the old containers until all new images are loaded and verified.
- Make failures in DB tasks fail the plan (Pitfall 1).
- Post-upgrade smoke test: UI health, run a trivial pipeline or job (CASE-031 would have been caught).

**Warning signs:**
- A plan that stops services before verifying its inputs.
- Upgrade scenarios that run only online.

**Phase to address:** P-CD4PE.

---

### Pitfall 19: CD4PE integration details with PE and source control (webhooks, URLs, trust)

**What goes wrong:**
Webhooks created with `http` instead of `https` (CASE-025). Trusted CA certificates not loaded or not readable (CDPE-6941; CASE-027 log shows `/opt/pfi/trust/trusted_certs/: No such file` and an empty additional JVM certs dir). Code deployment through CD4PE depends on Code Manager and its SSH hostkeys (CASE-008 shows the Code Manager side failing after upgrade). Behind a load balancer or reverse proxy the externally visible URL scheme differs from what the backend sees.

**Why it happens:**
The backend builds public URLs from its own configuration; plans do not ask for the external URL and scheme. Trust stores are populated from directories whose contents and permissions the plan does not verify.

**How to avoid:**
- Add an explicit `external_url` (scheme included) parameter validated at install, and a post-install check that creates a test webhook URL and asserts the scheme.
- Verify trust-store population after `upload_trusted_certs` (listing, permissions readable by the container user, count > 0).
- Document and verify the PE integration set: PE console URL, RBAC token validity, Code Manager reachable, r10k known hosts.
- Add CD4PE advanced configuration examples (GJira-4, CASE-004 asks for install docs).

**Warning signs:**
- Config that has a hostname but no scheme.
- Trust store directory empty after the plan says success.

**Phase to address:** P-CD4PE.

---

### Pitfall 20: SCM has almost no field evidence, so plans are written from docs alone

**What goes wrong:**
The CSV mentions SCM only as a banner in the CD4PE installer ("you'll have the option to separately install Security Compliance Management", CASE-019). There is no SCM case or ticket. Automation written without a failure corpus will repeat the same classes already seen in CD4PE and PE: CRL/TLS input handling, air-gapped images, container runtime and reboot recovery, project state loss.

Facts from the vendor docs that shape the risks `[DOCS]`:
- SCM 3.x installs with its own Bolt plans (`complyadm::install`), needs Bolt 3.27.2 or later, a Forge token, and must not share a host with PE.
- Install is new-installs only; no upgrade or backup guidance on the install page; only a registry mirror for offline use.
- mTLS to PE is auto-generated only if the PE host is in the inventory; manual mode requires chain, key and CRL.
- Sample inventories use `host-key-check: false` and `run-as: root`.
- Containers run under Docker or Podman.

**Why it happens:**
It is a new area for the module. The temptation is to wrap the vendor plans and assume they are robust.

**How to avoid:**
- Scope the first SCM increment narrowly: wrap, pre-flight, and verify. Do not reimplement `complyadm` logic (PROJECT.md: changing internals of CD4PE or SCM is out of scope).
- Reuse the shared libraries from the earlier phases: cert/CRL validation (Pitfall 11), offline manifest (Pitfall 15), post-condition checks (Pitfall 1), container health and reboot recovery (Pitfall 16), project-state export (Pitfall 17).
- Interactions with PE that break SCM: role swap, CA change and certificate renewal (mTLS identity), PE upgrades (RBAC and API ports 8143, 8081, 4433 `[DOCS]`). The failover plan must have an "SCM re-trust" check or at least a warning.
- Do not insecurely default `host-key-check: false` or root.
- Verify actual upgrade and backup procedures with the SCM team before designing them (Gap).
- Seed acceptance tests with a failure-injection run (reboot, kill container, delete project dir) before declaring it done.

**Warning signs:**
- SCM plan with no spec scenario that kills something.
- Requirements saying "automate SCM upgrade" with no vendor procedure behind them.

**Phase to address:** P-SCM. Flag for deeper research: vendor upgrade/backup/restore procedures; interplay with PE certificate changes. LOW confidence for all SCM claims beyond the docs page.

---

### Pitfall 21: Unit specs that mock everything, giving false confidence on a stateful, destructive domain

**What goes wrong:**
All fixes so far are covered by rspec-puppet or BoltSpec specs that stub tasks. The tasks that produce the real failures (installer, systemd, PostgreSQL, container runtime, classifier) are shell or Ruby scripts with no spec, and SQL in `restore.pp` is never executed `[CODE]` (CONCERNS). P0-4 and P0-6 note the shell tasks were run by hand. The acceptance workflows need real infra, credentials and ngrok/SSH access, and run only nightly or manually.

**Why it happens:**
Real PE clusters are slow and expensive to provision. A passing unit suite feels like safety.

**How to avoid:**
- Treat the scenario catalog (`spec/acceptance/scenarios.yaml`, 29 entries) as the contract: each pitfall in this document has a scenario, and every scenario has an owner and a state (cataloged, scripted, running in CI). Track the ratio in the planning docs.
- Land the cheapest high-value acceptance slice first: standard install, upgrade n to n+1, resume at every step after injected failure. Failure injection (corrupt tarball, stop pe-puppetdb mid-run, kill the SSH session, full disk) is what exposes Pitfalls 2, 4 and 7.
- Add spec coverage for shell tasks with a stub-PATH harness (fake `systemctl`, `tar`, `psql`) like P0-6 was verified by hand; make it an rspec helper so it is repeatable.
- Make the fix-log "before/after" run a CI check where possible (the recipe exists in `documentation/fix-log.md`).
- Do not mark a requirement validated on a unit spec alone for install, upgrade, restore, failover.

**Warning signs:**
- A ledger row whose Tests column says "no new spec yet" or "run by hand" for a plan change.
- No acceptance run in the last N days.

**Phase to address:** P-TEST, with the first slice completed before changes to P-UPG and P-DR code.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Add another retry loop with a sleep to hide a warm-up race | Plan passes in CI | Six loops already, each with its own error classification; real failures masked (Pitfall 5) | Never for new code; replace with readiness polling |
| Compare version strings inline (`versioncmp`, `SemVerRange`) in each plan | Fast feature gating | A new PE line needs edits in many files and failures show up only on a real cluster (Pitfall 12) | Never; use one feature-flag function |
| Customer-specific special case in classifier parsing | Unblocks one case | Drift between code paths, conflicts with the A/B model (Pitfall 8) | Only with a fixture and a ledger entry |
| Duplicate TLS client code per task | No shared code review needed | Verification drift, `VERIFY_NONE` slip (Pitfall 11) | Never; extract the helper first |
| `_catch_errors => true` without checking result | Plan keeps going | Success lies (Pitfall 1) | Only when immediately followed by an explicit result check |
| Writing diagnostics that print raw logs | Faster debugging | Secrets in support cases (Pitfall 14) | Never without sanitizing |
| Delete installer or image artifacts after use to save space | Saves GBs | Resume and retry need re-download, which fails offline (Pitfalls 2, 15) | Only after the consumer exits 0, and with a parameter to keep |
| Keep GitLab CI Ruby 2.5 jobs and a private gem job in the pipeline | Nothing to do | Pipeline does not reflect what ships | Retire or update (CONCERNS) |
| Land features before acceptance tests exist for the topology | Faster delivery | Regressions found by customers (Pitfall 21) | Only for non-destructive read-only checks |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| PE classifier (node groups, trusted OIDs) | Assume exactly one A and one B and `production` | Validate topology first; read environment from groups (Pitfall 8) |
| `puppet infrastructure *` CLI (promote, forget, enable, upgrade) | Treat exit 0 as done; assume CLI behavior is stable across lines | Verify result by `infra status` and classifier; gate by version (Pitfalls 1, 9) |
| PE installer | Assume it will accept any target; delete tarball early | Pre-check release date and path; keep tarball until exit 0 (Pitfalls 2, 4) |
| systemd units of `pe-*` services | Stop then forget to restore; fixed sleeps | Cleanup trap; readiness polling (Pitfalls 2, 5) |
| PuppetDB / PostgreSQL | Rewrite pg_hba or pe.conf and assume reload succeeded; run SQL strings | Verify with a connection test; test SQL on every PG version (CONCERNS) |
| Code Manager / r10k | Ignore known-hosts and webhooks during upgrade or failover | Check hostkeys and deploy after the change (CASE-008, CASE-015) |
| Load balancer / VIP in front of PE | Treat as outside scope | Add SAN, port and `server_list` checks as WARN items (CASE-015, CASE-024) |
| Bolt transports | Assume plain SSH | Support whatever the inventory defines; do not shell out to ssh directly (CASE-037 uses Azure `az ssh`) |
| Bolt controller modulepath | Assume dependencies stay compatible | Pin versions; check at plan start (PE-36915, PE-39099) |
| Podman/Docker for CD4PE and SCM | Assume containers start in order after reboot | Dependency order and health checks (Pitfall 16) |
| Forge / container registries | Assume internet | Offline bundle manifest with checksums (Pitfall 15) |
| hiera-eyaml for cd4peadm config | Hand-edit encrypted file | Edit only through a plan that validates decrypt after write (Pitfall 17) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Serial per-node operations from one Bolt controller | Upgrade or install takes hours | `parallelize` independent nodes (compilers), keep dependencies serial | Extra-large with many compilers (more than about 10) |
| Fixed-cost waits per step (about 145 s `ca_storage_import`, 15 s retry loops) | Long no-op runs | Gate on cheap checks (CONCERNS) | Every install; compounds on XL |
| Sequential `copy_file` per path | Slow add_replica | Batch read and upload | Many secret paths and large files |
| Large installer tarball re-download after failure | Retry takes tens of minutes | Keep the staged file; checksum cache | Slow links, air-gapped hosts |
| Single big Bolt transfer of multi-GB images over SSH | Timeout or truncated file (CASE-019) | Chunk or `rsync` with checksum; verify after | CD4PE images, PE tarballs |
| CD4PE JVM heap fixed small | Pipelines pending with OOM (CASE-027) | Configurable heap, sized from host memory | Many pipelines or repos |
| Console and orchestrator restarts timing out under load | `puppet infra upgrade` failing (code comments in upgrade.pp) | Wait for service readiness after each restart | Large catalogs, many nodes |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Secret key stores copied at 0644 | Local users read orchestrator/console keys on replica and compilers | Per-path mode, 0600 for `secrets/` (CONCERNS; High priority) |
| `/tmp/pe.conf` retains console admin password | Plaintext admin password on every node | Remove on success and failure |
| RBAC token written with default umask in `/root` | Long-lived admin token readable | `0600`, consistent path |
| Task parameters with passwords logged at debug | Credentials in support cases (CASE-005) | `Sensitive`, metadata `sensitive`, sanitizer |
| TLS verification disabled in a task | MITM on a local hop, bad precedent | Shared client with `VERIFY_PEER` |
| Installer download without mandatory signature verification | Tampered tarball | Pin key fingerprint, fail if unverifiable (CONCERNS) |
| New failover plan copying secret files | Repeats the 0644 issue on a larger scale | Fix `copy_file` before building failover |
| Rolling back via VM snapshots that contain secrets and tokens | Stale or leaked keys and tokens | Document ownership, check RBAC token validity after restore |
| Sample `host-key-check: false`, `run-as: root` copied into SCM/CD4PE inventories | Weak SSH trust | Safe defaults in generated inventories |
| `read_file` task returns any path as root and interpolates the path | Arbitrary read, quoting bugs | Env-var path, allowlist (CONCERNS) |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Failure shown as an exit code | Operator must find logs and open a case | Standard failure report (Pitfall 6) |
| No dry-run or pre-flight command | Customers ask support for health checks before each change window | `peadm::preflight*` plans with BLOCK/WARN output |
| Prompt-driven install (CD4PE) with no non-interactive path documented | Cannot automate, cannot repeat | Config-file install, documented examples (GJira-4) |
| Typo in `begin_at_step` silently skips all steps | "Success" with nothing done | Validate against the step list |
| Parameter or path names unclear (`ssl_crl` accepts what?) | Case after case | Validate and explain what was found |
| Error text assumes the user can edit module files ("file: ...pp line 25") | User cannot act | Message includes cause and remedy |
| Role swap documented as manual steps in prose | Mistakes in the change window | One plan per stage with output that can be pasted in the change record |
| Silent deprecation of plan names/params | Breaks production automation (PROJECT.md compatibility constraint) | Deprecation warning period, release notes |

## "Looks Done But Isn't" Checklist

- [ ] **Upgrade plan:** often missing the post-upgrade verification (infra status, versions, zero-change Puppet run) — verify the plan output has a verification stage
- [ ] **Resume support:** often missing re-established preconditions (tarball, stopped Puppet, drop-ins) — verify by failing each step in acceptance and resuming at it
- [ ] **Pre-flight:** often missing release-date check, eyaml DN check, cert/CRL expiry, topology sanity — verify against the table in Pitfall 3
- [ ] **Rollback:** often "documented" but never executed — verify a scenario that actually restores to a previous version and passes `infra status`
- [ ] **Failover plan:** often missing A/B re-convergence and replica rebuild verification — verify a second failover back succeeds without manual edits
- [ ] **add_replica / replace_*:** often "success" without classification and trusted extension — verify by querying the classifier and `infra status`
- [ ] **Air-gapped mode:** often only tested online — verify the scenario runs with the network blocked
- [ ] **CD4PE restart/patch:** often only tested with a plain restart — verify with a host reboot
- [ ] **Secrets:** often fixed in code but present in logs — verify with a grep over a debug log of a full run
- [ ] **Version support:** often bumped in data but gates missing — verify with the newest PE build in the nightly run
- [ ] **Change ledger and fix-log:** often updated after the fact — verify an entry exists in the same commit, with the ticket ID (several Phase 0 defects have no ticket; file them)
- [ ] **Tests:** often a stubbed spec — verify the shell/Ruby task was run against a real or stub-PATH harness

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Upgrade fails at `upgrade-primary` (CASE-002) | MEDIUM | Inspect installer log, restart `pe-puppetdb` and orchestration services, confirm primary services healthy, re-stage tarball, resume at `upgrade-primary` |
| Tarball missing on resume (CASE-049) | LOW | Re-stage the tarball (the extracted directory may remain on the node), resume at the failing step |
| Installer refuses older target (CASE-009) | HIGH | Do not retry; restore from the pre-upgrade backup or snapshot and rebuild the rest of the cluster to match |
| Compilers left at old version (CASE-045) | LOW | `puppet infrastructure upgrade compiler <certname>` per node from the primary, or re-run the compiler steps |
| Puppet stopped on infra nodes after failed run | LOW | `systemctl start puppet` on all infra nodes; restart any `pe-puppetdb` stopped on compilers; remove the `delete-reports` symlink and shortcircuit drop-in if present |
| Duplicate A/B pins (CASE-016) | MEDIUM | Fix pinning in the PE Infrastructure groups by hand per `documentation/classification.md`, then re-run |
| Replica added but unclassified (CASE-022) | MEDIUM | `puppet infrastructure forget`, clean cert, reinstall agent with extensions, `add_replica`, verify |
| Role swap fails at repurpose stage (CASE-029) | MEDIUM | Complete leftover provisioning by hand with the same commands, and file the timeout evidence |
| eyaml regression after patch (CASE-012) | HIGH | Roll back from snapshot or regenerate keys with a non-empty subject and re-encrypt every repo; pin vendored hiera-eyaml (GJira-7) |
| CD4PE DB config step failed (CASE-005, CASE-014) | MEDIUM | Check container list; start DB container; re-run install role for DB; if schema modified restore the DB dump |
| CD4PE does not start after patching (CASE-030) | LOW | Start containers one by one, DB first, check each with logs, then run `ctl` |
| CD4PE project deleted (CASE-028) | HIGH | Rebuild project, recover DB passwords from container environment, generate new keys, re-encrypt, reattach (procedure not yet automated) |
| Airgap image upload corrupt (CASE-019) | LOW | Verify checksum, re-copy the file, `podman load` manually to test |
| CRL rejected (CASE-006, CASE-013) | LOW | Convert to PEM with `openssl crl -inform DER`, ensure one CRL per block, use file-path form |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. Success without post-condition | P-DIAG, consumed by P-UPG/P-DR/P-CD4PE | A failing inner command makes the plan fail in spec and acceptance |
| 2. Resume without preconditions | P-UPG | Acceptance: injected failure at each step, resume at that step succeeds |
| 3. Shallow pre-flight | P-UPG, P-DR | Each Pitfall 3 table row has a spec and a ledger entry |
| 4. Rollback as reverse upgrade | P-UPG | Scenario performs tier 1, 2 and 3 recovery on a real cluster |
| 5. Hard-coded timeouts | P-DIAG | No fixed `sleep` in new code; overridable deadlines; timeouts print last state |
| 6. Bare exit codes | P-DIAG | Failure output contains log tail and unit state for every long task |
| 7. pe-puppetdb reload | P-UPG (after P-TEST scenario exists) | Reproduced and documented before and after on 2023.8.8 to 2025.12 |
| 8. Tidy-classifier assumption | P-DR, P-UPG, P-TEST | Drift fixtures pass (dup A pin, non-production env, legacy compilers) |
| 9. Failover as promote + add | P-DR | Staged plans; second failover-back scenario passes |
| 10. Replacement plans fail on common input | P-DR | `replace_failed_postgresql` with `failed == primary_postgresql_host` scenario passes |
| 11. Certificates and CRLs as strings | P-DIAG, reused by P-CD4PE/P-SCM | Fixture matrix (DER, PEM, chain, EC, empty DN) in unit specs |
| 12. Version support treadmill | P-UPG, P-TEST | `2026.0.1` supported, `2026.1.0` unsupported specs; nightly newest-version job |
| 13. Version-skew window | P-UPG, P-DIAG | Final version table check and documented skew behavior |
| 14. Secrets exposure | P-UPG (known three defects), P-DIAG, P-CD4PE | Grep of full debug log finds no secrets; mode specs for secret paths |
| 15. Air-gapped assumptions | P-UPG, P-CD4PE, P-SCM | Offline acceptance scenarios; checksum checks |
| 16. CD4PE reboot/patch | P-CD4PE | Reboot scenario passes; ordered start with health checks |
| 17. Lost Bolt project | P-CD4PE, P-SCM | Reattach plan scenario: delete project, recreate, run `status` |
| 18. CD4PE upgrade not transactional | P-CD4PE | Failure-injected upgrade restores from backup; smoke test runs a pipeline |
| 19. CD4PE integrations (webhook scheme, trust) | P-CD4PE | Webhook URL check; trust store listing |
| 20. SCM with no field evidence | P-SCM | Failure-injection run; vendor procedure confirmed |
| 21. Mock-heavy tests | P-TEST (first slice before P-UPG/P-DR) | Scenario catalog states: percentage scripted and running |

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| P-TEST first slice | Building a big matrix before any scenario runs | Start with upgrade + injected failure on a standard cluster |
| P-UPG pre-flight | Pre-flight placed after services are stopped | Run before `preparation` stops anything; separate plan |
| P-UPG rollback | Calling `upgrade` with an old version | Tiered recovery; restore plan with backup-version check |
| P-UPG pe-puppetdb reload | Guessing a fix | Reproduce first (Pitfall 7) |
| P-UPG security defects | Leaving 0644 secret copy in place while adding failover | Fix before P-DR |
| P-DIAG | Printing logs unsanitized | Sanitizer in the shared helper, spec with fake secrets |
| P-DR failover | Combined promote and rebuild | Separate stage plans; A/B re-convergence |
| P-DR replacement | Untested `replace_failed_postgresql` | Spec and scenario for primary DB host failure |
| P-CD4PE install/upgrade | Online-only testing | Offline scenarios mandatory |
| P-CD4PE patching | Fixed waits after reboot | Dependency order and health checks |
| P-CD4PE reattach | Assuming project is recoverable | Export plan and reattach plan |
| P-SCM | Design from docs, no failure corpus | Narrow wrap, reuse shared libs, failure injection |
| Cross-cutting | Behavior change to public plan names | Keep names and parameters; deprecation warnings |

## Sources

- `~/Code/peadm.csv`: 50 support cases and 52 Jira tickets (cases cited by ID; HIGH confidence for symptoms, MEDIUM or LOW for inferred causes)
- `/home/matthew/Code/puppetlabs-peadm/.planning/codebase/CONCERNS.md` (HIGH, verified against code where marked)
- `/home/matthew/Code/puppetlabs-peadm/.planning/PROJECT.md`
- Code read directly: `plans/upgrade.pp`, `tasks/pe_install.sh`, `tasks/puppet_runonce.sh`, `tasks/enable_replica.sh`, `tasks/get_peadm_config.rb`, `lib/puppet/functions/peadm/plan_step.rb`, `documentation/change-ledger.md`, `documentation/fix-log.md`, `documentation/upgrade.md` (HIGH)
- Security Compliance Management 3.x install page, https://help.puppet.com/scm/current/Content/UserGuide/SCM/Installation/scm_bolt_install.htm (MEDIUM; vendor docs fetched via a summarizing tool)
- SCM system requirements and install pages found by search, https://help.puppet.com/scm/current/Content/UserGuide/SCM/Installation/scm_system_requirements.htm (not opened; search snippet only, LOW to MEDIUM)
- No source was available for `cd4peadm` code or PE-core behavior; those causes are marked `[INFER]`. The research-plan/research-store cache seam was not used because the evidence is local files plus one doc fetch.

---
*Pitfalls research for: Bolt-based PE, CD4PE and SCM lifecycle automation (peadm)*
*Researched: 2026-11-10*

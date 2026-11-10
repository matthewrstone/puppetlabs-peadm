---
last_mapped_commit: e36923acdd0c8f080d9afc874fb38d5ab3a8db97
last_mapped_at: 2026-11-10
---
<!-- refreshed: 2026-11-10 -->
# Architecture

**Analysis Date:** 2026-11-10

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────┐
│                    Bolt CLI / Bolt project (operator)                 │
│        `bolt plan run peadm::<plan> ...`   `bolt task run ...`         │
└───────────────┬───────────────────────────────────┬──────────────────┘
                │ plans                              │ tasks (direct)
                ▼                                    ▼
┌──────────────────────────────────┐   ┌────────────────────────────────┐
│ Public plans  `plans/*.pp`        │   │ Tasks  `tasks/*.{rb,sh,ps1,py}`│
│ install, upgrade, convert,        │   │ + `tasks/*.json` metadata      │
│ add_compilers, add_replica, ...   │──▶│ executed on PE nodes by Bolt   │
└───────────────┬──────────────────┘   └───────────────┬────────────────┘
                │ run_plan                              │ run_task / run_command
                ▼                                       ▼
┌──────────────────────────────────┐   ┌────────────────────────────────┐
│ Subplans `plans/subplans/*.pp`    │   │ Util plans `plans/util/*.pp`   │
│ and `plans/misc/*.pp`             │──▶│ (cert ext, classification,     │
│ (private, `@api private`)         │   │  DB settings, file copy)       │
└───────────────┬──────────────────┘   └────────────────────────────────┘
                │ uses
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Shared logic                                                          │
│  Puppet functions `functions/*.pp`   Ruby functions `lib/puppet/...`  │
│  Types `types/*.pp`   Data `data/pe_versions.yaml`                    │
│  Templates `templates/*.epp`   Static files `files/`                  │
└───────────────┬──────────────────────────────────────────────────────┘
                │ node-side configuration (applied via puppet apply)
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Node classes `manifests/setup/*.pp`  (peadm::setup::node_manager, …)  │
│ Applied on PE primary during bootstrap; manage PE node groups         │
└──────────────────────────────────────────────────────────────────────┘
```

PEADM is a Puppet module packaged for Bolt (`metadata.json` name `puppetlabs-peadm`, version 3.40.0). It has no long-running service of its own. All behavior runs as Bolt plans that orchestrate PE nodes over Bolt transports, invoking tasks and commands on those nodes and, for bootstrap, applying a small node-side class.

## Pattern Overview

**Overall:** Orchestration-as-code. Bolt plans (Puppet language) sequence imperative steps across a set of PE infrastructure targets. Reusable logic is factored into Puppet functions and tasks; the plans themselves hold the control flow.

**Key Characteristics:**
- Entry points are Bolt plans, each a single `plan peadm::<name>(...)` declared in `plans/*.pp`. Each public plan validates inputs, resolves targets, and delegates to subplans via `run_plan`.
- Architecture is inferred from which host parameters are supplied (standard, large, extra-large, with/without DR, cloud database). Helper `peadm::assert_supported_architecture` in `functions/assert_supported_architecture.pp` validates the combination.
- Cluster role is recorded on certificates using PEADM-specific OIDs (`functions/oid.pp`: `peadm_role` 1.3.6.1.4.1.34380.1.1.9812, `peadm_availability_group` …9813, `peadm_legacy_compiler` …9814). Plans and tasks read these to discover topology rather than relying only on inventory.
- Cluster configuration lives in PE's own stores: `pe.conf` (read/written via `functions/get_pe_conf.pp`, `functions/update_pe_conf.pp`), and PE node groups (via classifier tasks such as `tasks/get_group_rules.rb`, `tasks/node_group_unpin.rb`, and `plans/util/update_classification.pp`).
- Supported PE versions are data-driven: `data/pe_versions.yaml` (`oldest: '2019.7'`, `newest: '2026.0'`) is read by the Ruby function `lib/puppet/functions/peadm/supported_pe_versions.rb` and enforced by `functions/assert_supported_pe_version.pp`.
- Long operations are resumable. Upgrades and some restores are split into named steps; `peadm::plan_step` (`lib/puppet/functions/peadm/plan_step.rb`) skips steps before a `begin_at_step` value.

## Layers

**Public plans (entry points):**
- Purpose: User-facing operations, one plan per lifecycle action.
- Location: `plans/*.pp`
- Contains: `install.pp`, `upgrade.pp`, `convert.pp`, `convert_compiler_to_legacy.pp`, `add_compilers.pp`, `add_compiler.pp` (deprecated wrapper), `add_replica.pp`, `add_database.pp`, `backup.pp`, `backup_ca.pp`, `restore.pp`, `restore_ca.pp`, `migrate.pp`, `replace_failed_postgresql.pp`, `status.pp`, `uninstall.pp`, `modify_certificate.pp`, `modify_cert_extensions.pp`.
- Depends on: subplans, util plans, functions, tasks, types.
- Used by: operators via Bolt CLI; acceptance plans in `spec/acceptance/peadm_spec/plans/`.

**Subplans (private orchestration):**
- Purpose: Reusable multi-step phases shared by public plans. Marked `# @api private` in their headers.
- Location: `plans/subplans/`
- Contains: `install.pp` (645 lines: PE installer run, pe.conf generation, Code Manager/r10k setup, license, agent prep), `configure.pp` (first-time classification, DR, LDAP, final agent state), `component_install.pp`, `db_populate.pp`, `modify_certificate.pp`, `prepare_agent.pp`.
- Depends on: util plans, functions, tasks.
- Used by: `plans/install.pp` (calls `peadm::subplans::install` then `peadm::subplans::configure`), `plans/upgrade.pp`, `plans/convert.pp`, `plans/add_database.pp`, `plans/add_replica.pp`.

**Util plans (narrow helpers):**
- Purpose: Single-concern operations reused across plans.
- Location: `plans/util/`
- Contains: `update_classification.pp`, `insert_csr_extension_requests.pp` (called 11 times across plans), `copy_file.pp`, `retrieve_and_upload.pp`, `db_disable_pglogical.pp`, `db_purge.pp`, `init_db_server.pp`, `sanitize_pg_pe_conf.pp`, `update_db_setting.pp`, `code_sync_status.pp`.
- Depends on: tasks, functions.
- Used by: subplans and public plans.

**Misc plans:**
- Location: `plans/misc/divert_code_manager.pp`. Used for Code Manager diversion during operations.

**Tasks (node-side actions):**
- Purpose: Execute on PE nodes via Bolt. Each task is a pair of `tasks/<name>.json` (metadata: description, parameters, `input_method`) and an executable.
- Location: `tasks/`
- Language mix: Ruby (`#!/opt/puppetlabs/puppet/bin/ruby`, using `ruby_task_helper` idioms; e.g., `tasks/get_peadm_config.rb`, `tasks/classify_compilers.rb`, `tasks/sign_csr.rb`), Bash (`tasks/pe_install.sh`, `tasks/download.sh`, `tasks/precheck.sh`, `tasks/wait_until_service_ready.sh`), PowerShell (`tasks/agent_install.ps1`, `tasks/submit_csr.ps1`, `tasks/os_identification.ps1`, `tasks/download.ps1`, `tasks/filesize.ps1`), and one Python task (`tasks/transform_classification_groups.py`).
- Depends on: PE node services (classifier, RBAC, CA, PuppetDB, PostgreSQL) and the installed PE binaries under `/opt/puppetlabs/`.
- Used by: all plans via `run_task('peadm::<name>', ...)`. The task names used most are `peadm::puppet_runonce` (27 call sites), `peadm::get_peadm_config` (11), `peadm::cert_data` (8), `peadm::read_file` (7), `peadm::pe_install` (6).

**Puppet functions (plan-language logic):**
- Purpose: Pure or near-pure helpers invoked from plans and classes.
- Location: `functions/*.pp` (DSL functions, namespace `peadm::`) and `lib/puppet/functions/peadm/*.rb` (Ruby functions).
- Examples: `functions/get_targets.pp` normalizes `TargetSpec` into `Array[Target]`; `functions/certname.pp` resolves a Target's certname; `functions/oid.pp` maps short names to OIDs; `functions/determine_status.pp` and `functions/convert_status.pp` drive `peadm::status` output; `functions/assert_supported_bolt_version.pp` gates on Bolt version via `lib/puppet/functions/peadm/bolt_version.rb`; `lib/puppet/functions/peadm/file_content_upload.rb` and `sanitize_log_text.rb` support safe upload and log redaction.

**Types:**
- Purpose: Constrain parameter shapes and enumerate allowed values.
- Location: `types/*.pp`
- Contains: `singletargetspec.pp` (one target only), `pe_version.pp`, `download_mode.pp`, `known_hosts.pp`, `ldap_config.pp`, `pem.pp`, `recovery_opts.pp`, `convertsteps.pp`, `upgradesteps.pp` (the seven valid `begin_at_step` values).

**Node classes (applied with puppet apply):**
- Purpose: Declarative configuration of PE node groups applied as a bootstrap action, not continuously enforced.
- Location: `manifests/setup/`
- Contains: `node_manager.pp` (class `peadm::setup::node_manager`, creates/updates PE Primary A/B, compiler groups, and database groups), `node_manager_yaml.pp`, `convert_node_manager.pp`, `convert_pre20197.pp`, `legacy_compiler_group.pp`.
- Rendered input: `templates/node_manager.yaml.epp`, `templates/autosign.conf.epp`.
- Used by: `plans/subplans/configure.pp` and `plans/convert.pp` via a `puppet apply --exec` invocation.

**Data:**
- `data/pe_versions.yaml`: supported PE range, read at runtime.

## Data Flow

### Primary Request Path: `peadm::install`

1. Operator invokes `plans/install.pp` with `primary_host` plus optional replica, compiler, and PostgreSQL hosts. The plan logs parameters with `peadm::log_plan_parameters` and checks the Bolt version (`peadm::assert_supported_bolt_version`) and PE version (`peadm::assert_supported_pe_version`).
2. `run_plan('peadm::subplans::install', ...)` (`plans/subplans/install.pp`) resolves targets with `peadm::get_targets`, downloads or uploads the PE tarball (`tasks/download.sh`, `tasks/verify_tarball.sh`, `plans/util/retrieve_and_upload.pp`), runs `tasks/pe_install.sh`, and installs agents (`tasks/agent_install.*`).
3. `run_plan('peadm::subplans::configure', ...)` (`plans/subplans/configure.pp`) classifies nodes, applies `peadm::setup::node_manager`, configures DR/availability groups, LDAP, and sets the final agent state.
4. The plan returns `[$install_result, $configure_result]` as its banner.

### Upgrade Path: `peadm::upgrade` (step-resumable)

1. `plans/upgrade.pp` validates the architecture, gathers targets, and fails early on transports unsuitable for the primary (`peadm::fail_on_transport`, requiring non-`pcp`).
2. The body is a sequence of `peadm::plan_step('<name>') || { ... }` blocks in this order: `preparation`, `upgrade-primary`, `upgrade-node-groups`, `upgrade-primary-compilers`, `upgrade-replica`, `upgrade-replica-compilers`, `finalize` (lines 246, 316, 375, 420, 429, 486, 495).
3. `begin_at_step` (type `Peadm::UpgradeSteps`) selects the entry point. `plan_step` prints `# Plan Step: <name>` for each step and prints `- SKIPPING` for steps before the requested one, then runs the block for the first matched step and everything after it.
4. Compiler upgrades depend on an RBAC token validated by `tasks/validate_rbac_token.rb`; primary and replica upgrades use `tasks/puppet_infra_upgrade.rb` and related PE service tasks.

### Convert Path: `peadm::convert`

1. `plans/convert.pp` (503 lines) turns an existing PE cluster into a PEADM-managed one: it sets OID certificate extensions (`plans/modify_certificate.pp`, `plans/subplans/modify_certificate.pp`, `plans/util/insert_csr_extension_requests.pp`), creates the required node groups (`manifests/setup/convert_node_manager.pp`, `convert_pre20197.pp`), and uses the same `begin_at_step`-style structure via `types/convertsteps.pp`.
2. Reverse-direction helpers `plans/convert_compiler_to_legacy.pp` and `manifests/setup/legacy_compiler_group.pp` handle legacy compilers.

### Status Path: `peadm::status`

1. `plans/status.pp` runs `tasks/infrastatus.sh` on each primary (`run_task('peadm::infrastatus', ...)`).
2. The result is reduced by `functions/determine_status.pp` and rendered by `functions/convert_status.pp` into a table or JSON.

**State Management:**
- No plan-external state store. PEADM reads and writes PE's own state: `pe.conf`, the PE classifier (node groups), certificate extensions, and PostgreSQL settings.
- Plan-run state is in Bolt's scope. The only cross-step state is the `__first_plan_step_reached__` flag set in the scope by `plan_step.rb` during resumed runs.
- Config discovery for an existing cluster: `tasks/get_peadm_config.rb` returns the PEADM-configured parameters by inspecting the "PE Primary A" node group and certificate data; it returns an error for non-PEADM clusters.

## Key Abstractions

**Target specifications:**
- Purpose: Accept either a single host or a group of hosts in plan parameters.
- Types: `Peadm::SingleTargetSpec` (`types/singletargetspec.pp`), Bolt's `TargetSpec` for multi-host params such as `compiler_hosts`.
- Helpers: `functions/get_targets.pp` (normalizes to `Array[Target]`, with optional count of 1), `functions/certname.pp`.
- Pattern: Plans call `peadm::get_targets($host, 1)` to obtain a single Target array and pass the Target into tasks.

**Plan step:**
- Purpose: Named, skippable checkpoints for long multi-step plans.
- Example: `plans/upgrade.pp` lines 246–495, `lib/puppet/functions/peadm/plan_step.rb`.
- Pattern: `peadm::plan_step('name') || { ... }`. Use the same form for new step names, and add any new name to `types/upgradesteps.pp` so `begin_at_step` accepts it.

**Availability groups and roles:**
- Purpose: Identify A/B pools for DR and compiler placement.
- Examples: `functions/availability_group_for.pp`, `functions/assert_supported_architecture.pp`, `functions/get_node_group_environment.pp`.
- Pattern: Certificates carry `peadm_role` and `peadm_availability_group` OIDs; classification groups use the "PE Primary A/B" and "PE Compiler Group A/B" naming.

**Version gating:**
- Purpose: Refuse unsupported PE or Bolt versions unless `permit_unsafe_versions` is set.
- Examples: `functions/assert_supported_pe_version.pp` (reads `peadm::supported_pe_versions`), `functions/assert_supported_bolt_version.pp`.
- Pattern: Every public plan that accepts `version` or runs on a primary calls one of these first.

**Log redaction and parameter logging:**
- `functions/log_plan_parameters.pp` logs inputs for debugging. `plans/upgrade.pp` logs only the basename of `pe_installer_source` because signed URLs can carry credentials. `lib/puppet/functions/peadm/sanitize_log_text.rb` scrubs log text.

## Entry Points

**Plans (primary entry points, invoked via `bolt plan run peadm::<name>`):**
- `plans/install.pp`: `peadm::install`. Greenfield install for standard, large, and extra-large, with optional DR, cloud database, Code Manager, and LDAP.
- `plans/upgrade.pp`: `peadm::upgrade`. Step-resumable upgrade of PE and PEADM-managed nodes.
- `plans/convert.pp`: `peadm::convert`. Adopt an existing PE cluster.
- `plans/add_compilers.pp`: `peadm::add_compilers`. Add compilers to a managed cluster.
- `plans/add_compiler.pp`: `peadm::add_compiler`. Deprecated wrapper that warns and calls `peadm::add_compilers`.
- `plans/add_replica.pp`: `peadm::add_replica`. Add a replica primary.
- `plans/add_database.pp`: `peadm::add_database`. Add a PostgreSQL node.
- `plans/backup.pp`, `plans/restore.pp`, `plans/backup_ca.pp`, `plans/restore_ca.pp`: backup and restore of PE and CA.
- `plans/migrate.pp`: `peadm::migrate`.
- `plans/replace_failed_postgresql.pp`: recovery of a failed PostgreSQL node.
- `plans/status.pp`: `peadm::status`. Read-only health report.
- `plans/uninstall.pp`: `peadm::uninstall`.
- `plans/modify_certificate.pp`, `plans/modify_cert_extensions.pp`: certificate management.
- `plans/convert_compiler_to_legacy.pp`: convert compilers to legacy mode.

**Tasks (direct entry points):** Each file in `tasks/` with a matching `.json` is runnable through `bolt task run peadm::<name>`.

**Puppet classes (bootstrap entry point):**
- `manifests/setup/node_manager.pp` (`peadm::setup::node_manager`), applied with `puppet apply --exec 'class { "peadm::setup::node_manager": ... }'` during primary bootstrap.

**Rake tasks:** `Rakefile` wires `puppetlabs_spec_helper`, `puppet-syntax`, `puppet-strings` (docs), and an optional `changelog` task.

## Architectural Constraints

- **Threading:** Bolt plans run sequentially on the controller. Tasks and commands fan out in parallel across the Bolt targets in a single `run_task` or `run_command` call. There is no in-module concurrency primitive.
- **Global state:** No module-level mutable state. The only process-wide state is the Bolt scope variable managed by `plan_step`. Cached data comes only from `data/pe_versions.yaml`, read on each call.
- **Circular imports:** Puppet modules do not allow circular plan calls by design. Subplans are called from public plans only. `plans/add_compiler.pp` calls `plans/add_compilers.pp`; no reverse path was found.
- **Bolt and PE version coupling:** `Gemfile` and `metadata.json` pin Puppet/Bolt-compatible dependencies (`puppetlabs/stdlib` `>= 9.0.0 < 11.0.0`, `puppetlabs/node_manager` `>= 1.0.1 < 2.0.0`, `puppet/format` `>= 0.1.0 < 3.0.0`). The `Puppetfile` pins `node_manager` 1.0.1, `format` 1.1.1, and `stdlib` 9.5.0 for the managed moduledir.
- **Transport restriction:** `peadm::upgrade` rejects the `pcp` transport for the primary because the upgrade restarts the orchestration service (`functions/fail_on_transport.pp`).

## Anti-Patterns

### Hardcoded default PE version in `install`

**What happens:** `plans/install.pp` declares `Peadm::Pe_version $version = '2025.12.1'`, while `data/pe_versions.yaml` declares `newest: '2026.0'`.
**Why it's wrong:** The install default and the supported range are maintained separately, so bumping the supported range does not move the default. If the default is left behind when the range moves, new installs silently start from an older release than the newest supported one.
**Do this instead:** Derive the default from the data source or keep it as a documented constant updated in the same change as `data/pe_versions.yaml`. Check consistency when editing either file.

### Duplicated subplan parameter lists

**What happens:** `plans/install.pp`, `plans/subplans/install.pp`, `plans/subplans/configure.pp`, and `plans/upgrade.pp` each restate the full set of architecture parameters (`primary_host`, `replica_host`, `compiler_hosts`, `primary_postgresql_host`, and so on) and forward them with `run_plan`.
**Why it's wrong:** Adding a parameter means editing every layer by hand, and missed forwards fail silently with defaults.
**Do this instead:** When adding a parameter, update the public plan, every subplan it reaches, and the matching `@param` docs together. Search for the parameter name across `plans/` before committing.

### Deprecated wrapper retained in the public surface

**What happens:** `plans/add_compiler.pp` prints a deprecation warning via `out::message` and delegates to `peadm::add_compilers`.
**Why it's wrong:** Two public entry points with overlapping semantics expand the test and documentation surface.
**Do this instead:** Keep the wrapper only until removal is scheduled; new callers should use `peadm::add_compilers`.

## Error Handling

**Strategy:** Fail fast on invalid input, using Puppet `assert_*` and `fail()` in functions and plans. Resumable plans rely on `begin_at_step` for recovery rather than automatic retry.

**Patterns:**
- Input and version checks run at the top of each public plan (`functions/assert_supported_architecture.pp`, `functions/assert_supported_pe_version.pp`, `functions/assert_supported_bolt_version.pp`, `functions/fail_on_transport.pp`).
- Task results are checked by reading the parsed JSON (`run_task(...).first['content']`, `functions/get_pe_conf.pp`). Ruby tasks print a JSON `error` key on failure (`tasks/get_peadm_config.rb`).
- Recovery from interrupted operations is done by re-running the plan with `begin_at_step`. Recovery procedures are documented in `documentation/recovery/recovery.md` and `documentation/recovery/automated_recovery.md`.

## Cross-Cutting Concerns

**Logging:** `out::message` (Bolt built-in, not a Forge dependency) for step banners and warnings. `functions/log_plan_parameters.pp` for parameter dumps, with `sanitize_log_text.rb` redaction.

**Validation:** Puppet data types in plan signatures (`types/*.pp`), `assert_*` functions in `functions/`, `data/pe_versions.yaml` for version range.

**Authentication:** Bolt transports (SSH, WinRM, `local`) for node access. PE RBAC tokens are fetched and validated by `tasks/rbac_token.rb` and `tasks/validate_rbac_token.rb`, and used by the Code Manager and compiler upgrade paths. Certificates are signed through `tasks/sign_csr.rb` and `tasks/submit_csr.rb`, with extension requests inserted by `plans/util/insert_csr_extension_requests.pp`.

---

*Architecture analysis: 2026-11-10*

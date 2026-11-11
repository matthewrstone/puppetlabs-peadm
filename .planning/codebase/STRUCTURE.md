---
last_mapped_commit: e36923acdd0c8f080d9afc874fb38d5ab3a8db97
last_mapped_at: 2026-11-10
---
# Codebase Structure

**Analysis Date:** 2026-11-10

## Directory Layout

```
puppetlabs-peadm/
├── plans/                  # Bolt plans: public entry points, subplans, util, misc
│   ├── subplans/           # Private multi-step phases (@api private)
│   ├── util/               # Single-concern helper plans
│   └── misc/               # Miscellaneous plans (divert_code_manager)
├── tasks/                  # Node-side tasks (.json metadata + executable)
├── functions/              # Puppet-language functions, namespace peadm::
├── lib/puppet/functions/peadm/   # Ruby functions, namespace peadm::
├── types/                  # Puppet type aliases (Peadm::*)
├── manifests/setup/        # Node classes applied via puppet apply
├── templates/              # EPP templates (node_manager.yaml, autosign.conf)
├── files/                  # Static files (task_helper.sh)
├── data/                   # pe_versions.yaml (supported PE range)
├── spec/                   # RSpec unit tests, acceptance, docker harnesses, fixtures
│   ├── acceptance/         # Acceptance scenarios and the peadm_spec fixture module
│   ├── classes/            # Class specs (setup/node_manager_spec.rb)
│   ├── docker/             # Docker-based cluster definitions per architecture
│   ├── fixtures/           # Test fixtures; modules/ holds vendored dependencies
│   ├── functions/          # Function specs
│   ├── plans/              # Plan specs (mirrors plans/ layout)
│   └── unit/task/          # Task unit specs
├── documentation/          # User docs (Markdown), images, recovery, migration
├── examples/               # Bolt inventory and provision examples
├── .planning/codebase/     # Generated codebase maps (this directory)
├── .github/workflows/      # GitHub Actions acceptance and CI workflows
├── .gitlab-ci.yml          # GitLab CI: lint, rubocop, parallel_spec
├── .devcontainer/          # Dev container definition
├── .bundle/                # Bundler configuration
├── metadata.json           # Module metadata and version (3.40.0)
├── Puppetfile              # Bolt-managed module pins (node_manager, format, stdlib)
├── .fixtures.yml           # spec_helper fixture declarations
├── Gemfile / Gemfile.lock  # Ruby dependencies
├── Rakefile                # puppetlabs_spec_helper, puppet-syntax, puppet-strings
├── README.md               # Entry documentation
├── REFERENCE.md            # Generated Puppet Strings reference
├── CHANGELOG.md / HISTORY.md
└── pedev_inventory.yaml, provision.yaml   # Local dev/provisioning inputs
```

## Directory Purposes

**`plans/`:**
- Purpose: All Bolt plans. Public plans sit at the top level; subdirectories hold private orchestration.
- Contains: `install.pp`, `upgrade.pp`, `convert.pp`, `add_compilers.pp`, `add_replica.pp`, `add_database.pp`, `backup.pp`, `restore.pp`, `migrate.pp`, `status.pp`, `uninstall.pp`, and others.
- Key files: `plans/install.pp` (install entry, 174 lines), `plans/upgrade.pp` (step-resumable upgrade, 544 lines), `plans/convert.pp` (503 lines), `plans/restore.pp` (478 lines), `plans/subplans/install.pp` (645 lines, largest plan).

**`plans/subplans/`:**
- Purpose: Private phases called by public plans via `run_plan('peadm::subplans::<name>')`.
- Contains: `install.pp`, `configure.pp`, `component_install.pp`, `db_populate.pp`, `modify_certificate.pp`, `prepare_agent.pp`.
- Key files: `plans/subplans/install.pp` (PE install), `plans/subplans/configure.pp` (classification and DR).

**`plans/util/`:**
- Purpose: Narrow reusable plans.
- Contains: `insert_csr_extension_requests.pp`, `update_classification.pp`, `copy_file.pp`, `retrieve_and_upload.pp`, `db_purge.pp`, `db_disable_pglogical.pp`, `init_db_server.pp`, `sanitize_pg_pe_conf.pp`, `update_db_setting.pp`, `code_sync_status.pp`.

**`plans/misc/`:**
- Purpose: One-off plans not fitting the other groups.
- Contains: `divert_code_manager.pp`.

**`tasks/`:**
- Purpose: Actions that run on PE nodes. Every task is a pair: `<name>.json` (metadata) plus `<name>.rb`, `<name>.sh`, `<name>.ps1`, or `<name>.py`.
- Naming: `snake_case`, verb-noun or noun where the task reads state (`get_peadm_config`, `cert_data`, `read_file`, `precheck`, `sign_csr`, `submit_csr`, `pe_install`, `pe_uninstall`, `pe_reinstall`, `classify_compilers`, `puppet_infra_upgrade`).
- Platform variants: Windows-capable tasks ship `.ps1` alongside `.sh`: `agent_install`, `submit_csr`, `os_identification`, `download`, `filesize`.
- Ruby tasks use `#!/opt/puppetlabs/puppet/bin/ruby` (for example `tasks/get_peadm_config.rb`) and require `puppet` or `json`/`net/http`.
- Count: roughly 75 files (about 37 tasks).

**`functions/`:**
- Purpose: Puppet-language functions in namespace `peadm::`. One function per file, filename matches function name.
- Naming: `snake_case.pp`, e.g. `get_targets.pp` → `peadm::get_targets`, `assert_supported_pe_version.pp` → `peadm::assert_supported_pe_version`.
- Key files: `get_targets.pp`, `certname.pp`, `oid.pp`, `get_pe_conf.pp`, `update_pe_conf.pp`, `generate_pe_conf.pp`, `assert_supported_architecture.pp`, `assert_supported_pe_version.pp`, `assert_supported_bolt_version.pp`, `fail_on_transport.pp`, `log_plan_parameters.pp`, `determine_status.pp`, `convert_status.pp`, `recovery_opts_default.pp`, `migration_opts_default.pp`.

**`lib/puppet/functions/peadm/`:**
- Purpose: Ruby-implemented functions needing Ruby logic or file I/O.
- Contains: `supported_pe_versions.rb` (reads `data/pe_versions.yaml`), `plan_step.rb` (resumable step control), `bolt_version.rb`, `module_version.rb`, `file_content_upload.rb`, `node_manager_yaml_location.rb`, `sanitize_log_text.rb`.

**`types/`:**
- Purpose: Named types for plan and function parameters.
- Naming: `snake_case.pp`, type name is `Peadm::<PascalCase>` (`singletargetspec.pp` → `Peadm::SingleTargetSpec`; `upgradesteps.pp` → `Peadm::UpgradeSteps`).

**`manifests/setup/`:**
- Purpose: Classes applied on PE nodes during bootstrap. Not continuously enforced.
- Contains: `node_manager.pp` (`peadm::setup::node_manager`), `node_manager_yaml.pp`, `convert_node_manager.pp`, `convert_pre20197.pp`, `legacy_compiler_group.pp`.

**`templates/`:**
- Purpose: EPP templates rendered by classes or plans.
- Contains: `node_manager.yaml.epp`, `autosign.conf.epp`.

**`files/`:**
- Purpose: Static files uploaded to nodes.
- Contains: `task_helper.sh`.

**`data/`:**
- Purpose: Module data read at runtime.
- Contains: `pe_versions.yaml` (`oldest`, `newest`). Bump `newest` when a new PE line is tested (see comment in the file).

**`spec/`:**
- Purpose: All tests and test harnesses.
- Layout mirrors source: `spec/plans/{subplans,util,misc}/`, `spec/functions/<name>_spec.rb`, `spec/unit/task/<name>_spec.rb`, `spec/classes/setup/node_manager_spec.rb`.
- `spec/acceptance/`: `peadm_spec.rb`, `scenarios.rb`, `scenarios.yaml` (scenario catalog; source for `documentation/test-scenarios.md` and CI matrix), `peadm_spec/` (fixture module with its own `plans/` and `tasks/`, symlinked as `peadm_spec` per `.fixtures.yml`).
- `spec/docker/<arch>/`: `docker-compose.yaml`, `params.json`, `upgrade_params.json` for `standard`, `standard-ha`, `large`, `large-ha`, `extra-large`, `extra-large-ha`. Shared `install.sh`, `upgrade.sh`, `setup-agents.sh`, `inventory.yaml`, `Puppetfile`.
- `spec/fixtures/`: `modules/` contains vendored third-party modules (treated as dependencies; not analyzed). `plans/` and `manifests/` hold fixture content. Module is also symlinked at `spec/fixtures/modules/peadm` per `.fixtures.yml`.

**`documentation/`:**
- Purpose: User-facing Markdown guides.
- Key files: `install.md`, `upgrade.md`, `convert.md`, `add_compilers.md`, `add_replica.md`, `backup_restore.md`, `backup_restore_ca.md`, `architectures.md`, `classification.md`, `status.md`, `pre_post_checks.md`, `test-coverage.md`, `test-scenarios.md`, `change-ledger.md`, `release_process.md`.
- Subdirectories: `documentation/recovery/` (`recovery.md`, `automated_recovery.md`), `documentation/migration/` (`migrating.md`), `documentation/images/` (architecture diagrams and PNGs), `documentation/res/` (summarized JSON data).

**`examples/`:**
- Purpose: Reference inputs.
- Contents: `examples/provision/*.json` (per-architecture provisioning params, e.g. `standard-ha.json`, `extra-large.json`), `examples/haproxy/*.pp` (load balancer and compiler examples), `examples/upgrade.json`, `examples/ruby_task.rb`.

**`.github/workflows/`:**
- Purpose: GitHub Actions for acceptance tests and release.
- Naming: `test-<feature>.yaml` (`test-install.yaml`, `test-upgrade.yaml`, `test-failover.yaml`, `test-backup-restore.yaml`, `test-migration.yaml`, `test-add-compiler.yaml`, `test-add-replica.yaml`), matrix variants `test-<feature>-matrix.yml`, nightly variants `test-*-nightly`. Also `ci.yml`, `spec.yml`, `release.yml`, `release-prep.yml`, `auto_release.yml`, `nightly.yml`, `mend.yml`. See `.github/workflows/README.md` for shared-step maintenance rules.

## Key File Locations

**Entry Points (plans):**
- `plans/install.pp`: `peadm::install`
- `plans/upgrade.pp`: `peadm::upgrade`
- `plans/convert.pp`: `peadm::convert`
- `plans/add_compilers.pp`: `peadm::add_compilers`
- `plans/add_replica.pp`: `peadm::add_replica`
- `plans/add_database.pp`: `peadm::add_database`
- `plans/status.pp`: `peadm::status`
- `plans/backup.pp`, `plans/restore.pp`: backup and restore

**Entry Points (node bootstrap):**
- `manifests/setup/node_manager.pp`: applied on the primary during bootstrap

**Configuration:**
- `metadata.json`: module name, version, dependency ranges, supported OS list
- `data/pe_versions.yaml`: supported PE range
- `Puppetfile`: Bolt-managed module pins
- `.fixtures.yml`: spec fixtures
- `.rubocop.yml`, `.rubocop_todo.yml`, `.puppet-lint.rc`, `.sync.yml`, `pdk.yaml`: lint and sync config
- `.ruby-version`: Ruby version for the module

**Core Logic:**
- `plans/subplans/install.pp`, `plans/subplans/configure.pp`: install and configure orchestration
- `functions/get_targets.pp`, `functions/certname.pp`, `functions/oid.pp`: target and identity helpers
- `lib/puppet/functions/peadm/plan_step.rb`: resumable step control
- `manifests/setup/node_manager.pp`: PE node group definitions

**Testing:**
- `spec/plans/`, `spec/functions/`, `spec/unit/task/`, `spec/classes/setup/`: unit specs
- `spec/spec_helper.rb`, `spec/spec_helper_local.rb`, `spec/default_facts.yml`: unit test setup
- `spec/acceptance/scenarios.yaml`: acceptance scenario catalog
- `spec/acceptance/peadm_spec/README.md`: acceptance fixture module notes

## Naming Conventions

**Files:**
- Plans, functions, types, tasks: `snake_case` matching the Puppet or task name. Example: `plans/add_compilers.pp` → `peadm::add_compilers`.
- Ruby functions: `snake_case.rb` under `lib/puppet/functions/peadm/`. Example: `plan_step.rb` → `peadm::plan_step`.
- Specs: `<name>_spec.rb` mirroring the source name. Example: `spec/functions/get_targets_spec.rb`.
- Task metadata: `<task>.json` sits next to `<task>.<ext>` with the same base name.
- Workflows: `test-<feature>.yaml` or `.yml`.

**Directories:**
- Lowercase, `snake_case` for Puppet and task directories (`plans/subplans`, `plans/util`, `manifests/setup`).
- Docker architecture directories use hyphenated names matching architecture labels: `extra-large-ha`, `standard-ha`.

**Puppet identifiers:**
- Plans and functions: `peadm::<snake_case>`. Subplans: `peadm::subplans::<name>`. Util plans: `peadm::util::<name>`. Classes: `peadm::setup::<name>`.
- Types: `Peadm::<PascalCase>`.
- Plan parameters: `snake_case` (`primary_host`, `replica_host`, `compiler_hosts`, `primary_postgresql_host`, `pe_installer_source`, `begin_at_step`).
- Upgrade step names: lowercase hyphenated (`upgrade-primary`, `upgrade-replica-compilers`). These must appear in `types/upgradesteps.pp`.

**Architecture labels:**
- `standard`, `large`, `extra-large`, with `-ha` and `-with-dr` variants used in tests and docs.

## Where to Add New Code

**New public plan (operator action):**
- Implementation: `plans/<action>.pp` with `@summary`, `@param` docs, and `peadm::assert_supported_bolt_version()` / `assert_supported_pe_version` calls where a version is involved.
- If it has resumable steps, wrap them with `peadm::plan_step('<name>') || { ... }` and add the name to `types/upgradesteps.pp` or a new type alongside `types/convertsteps.pp`.
- Tests: `spec/plans/<action>_spec.rb`.
- Docs: `documentation/<action>.md`, and add an entry to `REFERENCE.md` by regenerating Puppet Strings.
- Acceptance: a scenario in `spec/acceptance/scenarios.yaml` and a workflow under `.github/workflows/test-<action>.yaml`.

**New private subplan:**
- Implementation: `plans/subplans/<name>.pp`, with `# @api private`.
- Tests: `spec/plans/subplans/<name>_spec.rb`.

**New util plan:**
- Implementation: `plans/util/<name>.pp`.
- Tests: `spec/plans/util/<name>_spec.rb`.

**New task:**
- Implementation: `tasks/<name>.json` plus `tasks/<name>.rb` (or `.sh`; add `.ps1` if Windows support is needed). Use the `#!/opt/puppetlabs/puppet/bin/ruby` shebang for Ruby tasks that need PE's Ruby.
- Tests: `spec/unit/task/<name>_spec.rb` for Ruby tasks.

**New Puppet function:**
- Implementation: `functions/<name>.pp` for DSL logic; `lib/puppet/functions/peadm/<name>.rb` when file I/O or Ruby libraries are needed.
- Tests: `spec/functions/<name>_spec.rb`.

**New type:**
- Implementation: `types/<name>.pp`, exported as `Peadm::<Name>`.

**New node class:**
- Implementation: `manifests/setup/<name>.pp`. Templates go in `templates/`.
- Tests: `spec/classes/setup/<name>_spec.rb`.

**Shared utilities:**
- Puppet-language: `functions/`. Ruby: `lib/puppet/functions/peadm/`.

**New PE version support:**
- Update `data/pe_versions.yaml` (`newest`), `types/pe_version.pp` if the pattern changes, and the install default in `plans/install.pp` (see ARCHITECTURE.md anti-patterns).

## Special Directories

**`spec/fixtures/modules/`:**
- Purpose: Vendored third-party modules fetched for tests (stdlib, node_manager, service, package, inifile, ruby_task_helper, reboot, provision, puppet_agent, facts, apply_helpers, bolt_shim, container_inventory, format). Also contains a `peadm` symlink to the repo root.
- Generated: Yes (by `rake spec_prep` / `.fixtures.yml`).
- Committed: No.

**`spec/fixtures/`, `.modules/`, `.yardoc/`:**
- `.yardoc/` is generated YARD output; `.modules/` is the Bolt-managed moduledir when `bolt module install` runs.
- Generated: Yes. Committed: No.

**`spec/acceptance/peadm_spec/`:**
- Purpose: Acceptance fixture module used by GitHub workflows. Symlinked as `peadm_spec` per `.fixtures.yml`.
- Generated: No. Committed: Yes.

**`.planning/`:**
- Purpose: GSD planning artifacts including `codebase/` analysis documents.
- Generated: Yes. Committed: depends on project policy.

**`documentation/res/`:**
- Purpose: JSON summaries (`raw_summary.json`, `summarized.json`) backing documentation content.
- Generated: Likely yes. Committed: Yes.

---

*Structure analysis: 2026-11-10*

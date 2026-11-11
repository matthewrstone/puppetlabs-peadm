---
last_mapped_commit: e36923acdd0c8f080d9afc874fb38d5ab3a8db97
last_mapped_at: 2026-11-10
---
# External Integrations

**Analysis Date:** 2026-11-10

## APIs & External Services

**Puppet Enterprise internal HTTP APIs (on PE nodes, accessed by Ruby tasks via `Net::HTTP`):**
- Classifier API (node groups) - `/classifier-api/v1/groups`, `/classifier-api/v1/import-hierarchy`, `/classifier-api/v2/classified/nodes/<certname>` on port 4433
  - Used in: `tasks/backup_classification.rb`, `tasks/restore_classification.rb`, `tasks/classify_compilers.rb`, `tasks/node_group_unpin.rb`, `tasks/update_pe_master_rules.rb`, `tasks/check_pe_master_rules.rb`, `tasks/get_group_rules.rb`, `tasks/check_legacy_compilers.rb`
  - Client: `Net::HTTP` (Ruby stdlib); host from `Puppet.settings[:certname]`
  - Auth: PE client certificates (`Puppet.settings`) and RBAC token where required
- RBAC API - `/rbac-api/v1/auth/token` and `/rbac-api/v2/auth/token/authenticate` on port 4433
  - Used in: `tasks/rbac_token.rb`, `tasks/validate_rbac_token.rb`
  - Auth: username/password supplied as task parameters; returns token used by other tasks
- Orchestrator API - `/orchestrator/v1/inventory` on port 8143
  - Used in: `tasks/puppet_infra_upgrade.rb`
- PuppetDB query API - `/pdb/query/v4` over HTTPS (via `Net::HTTP`) and `pdb_query` in Puppet code
  - Used in: `tasks/get_peadm_config.rb`, `tasks/check_pe_master_rules.rb`
- Code Manager / file-sync API - `https://localhost:8140/file-sync/v1/commit`, `/file-sync/v1/force-sync`, `/puppet-admin-api/v1/environment-cache`
  - Used in: `tasks/code_manager.sh` (via `curl -ks`)
- Status API - `/status/v1/simple`, `/status/v1/services?level=debug` on ports 8140 and service-specific endpoints
  - Used in: `tasks/wait_until_service_ready.sh`, `tasks/code_sync_status.rb`
- Certificate/CA endpoints on port 8140 - Used by `tasks/sign_csr.rb`, `tasks/submit_csr.rb`, `tasks/cert_data.rb`, `tasks/cert_valid_status.rb`, `tasks/ssl_clean.rb`, `tasks/list_compiler_icas.rb`
- Agent install endpoint - `https://<server>:8140/packages/current/install.bash` (Linux) and `install.ps1` (Windows)
  - Used in: `tasks/agent_install.sh`, `tasks/agent_install.ps1` (Windows path disables certificate validation via `ServerCertificateValidationCallback`; Linux path uses `curl --fail -k`)

**Puppet Enterprise release artifacts:**
- PE installer tarballs from public S3 - `https://s3.amazonaws.com/pe-builds/released/<version>/<tarball>`
  - Set in: `plans/subplans/install.pp`, `plans/upgrade.pp`, `plans/util/init_db_server.pp`
  - Downloaded by: `tasks/download.sh`, `tasks/download.ps1` (via `curl -s -f -L`); size checked with `curl --head`
  - Override: `pe_installer_source` plan parameter (must be `Stdlib::HTTPSUrl`) in `plans/install.pp`, `plans/upgrade.pp`, `plans/subplans/install.pp`
  - Alternate path: `plans/util/retrieve_and_upload.pp` retrieves a tarball to the Bolt controller and uploads it to targets
- PE installer tarball from internal Artifactory (CI only) - `https://artifactory.delivery.puppetlabs.net/artifactory/generic_enterprise__local/main/ci-ready/puppet-enterprise-<ver>-el-8-x86_64.tar`
  - Used in: `.github/workflows/test-install-latest-dev.yaml`, `.github/workflows/test-upgrade-latest-dev.yaml`, `.github/workflows/test-upgrade-latest-xlarge-dev-nightly.yaml`, `.github/workflows/test-upgrade-pg-major-ha-nightly.yaml`, `.github/workflows/test-install-latest-xlarge-dev-nightly.yaml`

**PE installer task (on node):**
- `tasks/pe_install.sh` runs the PE installer on each target; `tasks/pe_reinstall.sh` and `tasks/reinstall_pe.sh` perform reinstall. `tasks/reinstall_pe.sh` downloads its installer from `https://s3.amazonaws.com/pe-builds/released/${PT_version}/`.

**Puppet Forge:**
- `https://forge.puppet.com` - Module dependency source (`metadata.json`, `.fixtures.yml` `forge_modules`, `Puppetfile`)
- Documentation links only: `https://forge.puppet.com/modules/puppetlabs/peadm/plans` (referenced in `plans/util/retrieve_and_upload.pp`)

**Git repositories (test fixtures only, `.fixtures.yml`):**
- `https://github.com/puppetlabs/puppetlabs-facts.git`
- `https://github.com/puppetlabs/puppetlabs-puppet_agent.git`
- `https://github.com/puppetlabs/provision.git` (ref `v3.2.0`)
- `https://github.com/puppetlabs/puppetlabs-stdlib.git`
- `https://github.com/puppetlabs/puppetlabs-apply_helpers`
- `https://github.com/puppetlabs/puppetlabs-bolt_shim`
- `https://github.com/voxpupuli/puppet-format`
- `https://gitlab.com/nwops/bolt-container_inventory.git`
- `https://github.com/puppetlabs/puppetlabs-node_manager.git`

**Package registries:**
- RubyGems - `https://rubygems.org` (default `GEM_SOURCE` in `Gemfile`)
- Puppet private gem source - `https://rubygems-puppetcore.puppet.com`, used when `PUPPET_FORGE_TOKEN` is set; credentials come from CI secrets `PUPPET_FORGE_TOKEN` / `PUPPET_FORGE_TOKEN_PUBLIC` (`.github/workflows/spec.yml`, `.github/workflows/test-add-compiler-matrix.yml`)

**Documentation links (not called at runtime):**
- `https://www.puppet.com/docs/pe/latest/rbac_token_auth_intro` (`tasks/validate_rbac_token.rb`)
- `https://www.puppet.com/docs/bolt/latest/bolt_transports_reference.html` (`plans/upgrade.pp`, `plans/subplans/modify_certificate.pp`, `plans/util/retrieve_and_upload.pp`)
- `https://puppet.com/docs/pe/2018.1/static_catalogs.html` (`plans/misc/divert_code_manager.pp`)

## Data Storage

**Databases:**
- PostgreSQL - Managed by PE, not by this module directly. Plans configure and inspect it through PE installer answers and tasks.
  - Relevant plans: `plans/add_database.pp`, `plans/replace_failed_postgresql.pp`, `plans/util/init_db_server.pp`, `plans/subplans/install.pp`
  - Tasks: `tasks/get_psql_version.rb` (reads `/opt/puppetlabs/puppet/cache/lib/pe_install/pe_postgresql_info.rb`), `tasks/enable_replica.sh`, `tasks/provision_replica.sh`
  - Database names defined in `functions/pe_db_names.pp`
- PuppetDB - PE-managed; queried over HTTPS (`/pdb/query/v4`) by tasks listed above
- No ORM or application database client in this module

**File Storage:**
- Local filesystem only on targets and the Bolt controller
  - Upload directory on targets is created by `tasks/mkdir_p_file.sh` and `tasks/mv.sh`; installer tarballs staged via `tasks/download.sh` and `tasks/read_file.sh`
  - Backups produced by `plans/backup.pp` and `plans/backup_ca.pp`; restored by `plans/restore.pp` and `plans/restore_ca.pp` (Puppet Server `puppet-backup` artifacts; see `documentation/backup_restore.md`)
- Puppet code deployment via Code Manager (see Webhooks & Callbacks)

**Caching:**
- None. Puppet environment cache is cleared through the Code Manager admin API (`tasks/code_manager.sh`).

## Authentication & Identity

**Auth Provider:**
- PE RBAC and certificate-based authentication
  - Tasks obtain RBAC tokens via `tasks/rbac_token.rb` and validate them via `tasks/validate_rbac_token.rb`
  - Node identity and mutual TLS use the Puppet CA (`Puppet.settings[:certname]`, `tasks/sign_csr.rb`, `tasks/submit_csr.rb`, `tasks/ssl_clean.rb`, `plans/modify_certificate.pp`, `plans/modify_cert_extensions.pp`)
  - Certificate extensions (OIDs) handled by `functions/oid.pp`
- LDAP directory service configuration
  - `tasks/pe_ldap_config.rb` writes LDAP connection settings through the RBAC/classifier API on port 4433
- Bolt transports (controller to targets)
  - SSH: `provision.yaml` and `pedev_inventory.yaml` configure `transport: ssh` with `user: root`, `private-key: ~/.ssh/id_rsa-acceptance` (path only; key contents not read), `host-key-check: false`
  - WinRM and other Bolt transports are referenced in docs but not configured in this repo

**Secrets:**
- Test inventory `pedev_inventory.yaml` contains a plaintext console admin password under `vars` for acceptance environments. Do not reuse it outside test infrastructure.

## Monitoring & Observability

**Error Tracking:**
- None detected

**Logs:**
- Plans log via Bolt/Puppet logging: `plans/misc/log_plan_parameters.pp` and `functions/log_plan_parameters.pp`
- PE installer log and failed services surfaced by `tasks/pe_install.sh` (see recent commit "Report installer log and failed services when pe_install fails")
- Service health probes: `tasks/infrastatus.sh`, `tasks/precheck.sh`, `tasks/code_sync_status.rb`

## CI/CD & Deployment

**Hosting:**
- Puppet Forge - module publishing target (`metadata.json`, `puppetlabs-peadm` 3.40.0)
- GitHub - primary source host (`https://github.com/puppetlabs/puppetlabs-peadm`, `metadata.json` `source`)

**CI Pipeline:**
- GitHub Actions - `.github/workflows/ci.yml` calls reusable workflows `puppetlabs/cat-github-actions/.github/workflows/module_ci.yml@main` and `module_acceptance.yml@main` (secrets passed via `secrets: inherit`); `spec.yml` runs the unit matrix; `release.yml`, `release-prep.yml`, `auto_release.yml` handle releases; `nightly.yml`, `test-*.yaml` run PE install, upgrade, failover, backup/restore, and compiler scenarios; `mend.yml` for dependency/security scanning; `add-to-project.yml` for project board automation; `yamlformatter.yml` for YAML style
- Auto-release uses `GITHUB_TOKEN` and `CHANGELOG_GITHUB_TOKEN` (`.github/workflows/auto_release.yml`)
- Legacy GitLab CI - `.gitlab-ci.yml` (stages `syntax` and `unit`, Ruby 2.5.7 and 2.7.2 images)
- AppVeyor - `appveyor.yml`
- Coverage uploads via Codecov (`codecov` gem; `simplecov-cobertura` output)

## Environment Configuration

**Required env vars (CI and local development):**
- `PUPPET_GEM_VERSION`, `FACTER_GEM_VERSION`, `HIERA_GEM_VERSION` (optional) - select gem versions in `Gemfile`
- `PUPPET_FORGE_TOKEN` (optional) - enables private `puppetcore` gem source
- `BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM` (set by CI from forge token)
- `RSPEC_UNIT_TEST_MODE` - set to skip task `main` execution during unit tests
- `CHANGELOG_GITHUB_TOKEN` - required for `rake changelog`
- `RUBYGEMS_VERSION` (optional) - pins RubyGems in GitLab CI (`.gitlab-ci.yml`)

**Required plan parameters (not env vars):**
- `pe_installer_source` (optional HTTPS URL) or PE `version`; defined in `plans/install.pp`, `plans/upgrade.pp`
- `console_admin_password` - passed to `pe_install` task (see `tasks/pe_install.sh`, `tasks/pe_reinstall.sh`)
- `dns_alt_names`, `compiler_pool_address`, and related PE topology parameters in `plans/install.pp`

**Secrets location:**
- GitHub Actions secrets: `PUPPET_FORGE_TOKEN`, `PUPPET_FORGE_TOKEN_PUBLIC`, `GITHUB_TOKEN`, and `CHANGELOG_GITHUB_TOKEN` (referenced in `.github/workflows/`)
- Bolt SSH private key path: `~/.ssh/id_rsa-acceptance` (not stored in repo)
- No `.env` file is read or committed by the module

## Webhooks & Callbacks

**Incoming:**
- None. The module does not expose webhook endpoints.
- Puppet Server endpoints that it calls are listed under APIs above.

**Outgoing:**
- Code Manager file-sync commit and force-sync, plus environment cache flush (`tasks/code_manager.sh`, `https://localhost:8140/file-sync/v1/*`)
- Node group pinning and classifier updates (`tasks/node_group_unpin.rb`, `tasks/update_pe_master_rules.rb`, `tasks/classify_compilers.rb`)
- No outbound webhooks to third-party services

---

*Integration audit: 2026-11-10*

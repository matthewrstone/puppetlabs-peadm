---
last_mapped_commit: e36923acdd0c8f080d9afc874fb38d5ab3a8db97
last_mapped_at: 2026-11-10
---
# Technology Stack

**Analysis Date:** 2026-11-10

## Languages

**Primary:**
- Puppet DSL - Bolt plans in `plans/` (e.g. `plans/install.pp`, `plans/upgrade.pp`, `plans/subplans/install.pp`), Puppet functions in `functions/` (e.g. `functions/assert_supported_pe_version.pp`, `functions/oid.pp`), manifests in `manifests/` (e.g. `manifests/setup/node_manager.pp`), and types in `types/`
- Ruby - Bolt/PE task implementations in `tasks/*.rb` (e.g. `tasks/get_peadm_config.rb`, `tasks/rbac_token.rb`), Puppet 4.x-style functions in `lib/puppet/functions/`, and the RSpec suite in `spec/`

**Secondary:**
- Bash/POSIX shell - Installer, download, and Code Manager tasks: `tasks/pe_install.sh`, `tasks/download.sh`, `tasks/code_manager.sh`, `tasks/wait_until_service_ready.sh`, `tasks/agent_install.sh`
- PowerShell - Windows agent helpers: `tasks/agent_install.ps1`, `tasks/download.ps1`, `tasks/submit_csr.ps1`, `tasks/os_identification.ps1`, `tasks/filesize.ps1`
- Python - Classification transform helper: `tasks/transform_classification_groups.py`
- YAML/JSON - Task metadata (`tasks/*.json`), data (`data/pe_versions.yaml`), Bolt inventory and fixtures (`.fixtures.yml`, `provision.yaml`, `pedev_inventory.yaml`), and CI definitions (`.github/workflows/*.yml`, `.gitlab-ci.yml`)

## Runtime

**Environment:**
- Target runtime is Puppet Enterprise (PE) on the managed Puppet infrastructure nodes. Plans run on a Bolt controller; tasks execute on target nodes via Bolt transports.
- Puppet language requirement: `>= 8.0.0 < 9.0.0` (`metadata.json` `requirements`).
- Ruby development version: `3.1.0` (`.ruby-version`). The GitLab pipeline in `.gitlab-ci.yml` also uses `ruby:2.5.7` (Puppet ~> 6) and `ruby:2.7.2` (Puppet ~> 7) images, which are legacy matrix entries.
- Gemfile conditionally pins gems per Ruby version (`Gemfile`): `json`, `racc`, `i18n` (`< 1.15.0` below Ruby 3.2), and default gems `benchmark`, `ostruct`, `logger`, `csv`, `base64` on Ruby 4.0+.

**Package Manager:**
- Bundler (Ruby gems) - `Gemfile` and `Gemfile.lock` (both present)
- Bolt module manager - `Puppetfile` (`moduledir '.modules'`) with pinned modules `puppetlabs/node_manager` 1.0.1, `puppet/format` 1.1.1, `puppetlabs/stdlib` 9.5.0
- Fixture manager - `.fixtures.yml` (Forge modules and git repositories cloned into `spec/fixtures/modules/`)
- Lockfile: present (`Gemfile.lock`); `Puppetfile` is managed by Bolt and has no separate lock file

## Frameworks

**Core:**
- Puppet Bolt (`bolt` gem, `>= 4.0.0` in `Gemfile`) - Orchestration framework that runs the plans and tasks in this module. Plans use `run_task`, `run_plan`, `run_command`, and `get_targets`.
- Puppet Enterprise (PE) - The product being deployed. Installer is `pe_install` task (`tasks/pe_install.sh`, `tasks/pe_install.json`). Supported version range is read from `data/pe_versions.yaml` (`oldest: '2019.7'`, `newest: '2026.0'`).
- Puppet (`puppet` gem 8.10.0 in `Gemfile.lock`) - Used for unit tests and Ruby-side settings access (`Puppet.settings[:certname]`) inside tasks.
- Puppet module `puppetlabs/stdlib` (`>= 9.0.0 < 11.0.0`) - Required module, pinned to 9.5.0 in `Puppetfile`.

**Testing:**
- RSpec via `puppetlabs_spec_helper` 6.0.3 (`Gemfile.lock`) - Config in `spec/spec_helper.rb`, `spec/spec_helper_local.rb`; `.rspec` at root
- `rspec-puppet` 4.0.2 - Catalog/compile tests for classes, plans, functions, and tasks (`spec/classes`, `spec/plans`, `spec/functions`, `spec/unit`)
- `rspec-puppet-facts` ~> 2.0 and `facterdb` ~> 1.18 - Default OS facts (`spec/default_facts.yml`)
- `puppet_litmus` 2.8.1 and `serverspec` ~> 2.41 - Acceptance tests (`spec/acceptance/`, `spec/spec_helper_acceptance.rb`); `system_tests` group is excluded from CI bundle installs
- `parallel_tests` = 3.12.1 - Used by `rake parallel_spec`
- `simplecov-cobertura` ~> 3.2, `simplecov-console` ~> 0.5, `codecov` ~> 0.2 - Coverage reporting
- `pry` ~> 0.10 and `puppet-debugger` ~> 1.0 - Development helpers

**Build/Dev:**
- Rake - Task runner; see `Rakefile` (`changelog_since_tag: 2.5.0`, `PuppetSyntax.exclude_paths` for lint)
- PDK 3.0.0 template (`metadata.json` `pdk-version`, `pdk.yaml`) - Module scaffolding; `.sync.yml` drives template sync
- `puppet-lint` 4.3.0 with `voxpupuli-puppet-lint-plugins` ~> 5.0 - Config in `.puppet-lint.rc`
- `metadata-json-lint` ~> 3.0 - Validates `metadata.json`
- `rubocop` = 1.79.0, `rubocop-performance` = 1.25.0, `rubocop-rspec` = 3.6.0, `rubocop-rspec_rails` ~> 2.31.0, `rubocop-factory_bot` ~> 2.27.1, `rubocop-capybara` ~> 2.22.1 - Config in `.rubocop.yml` and `.rubocop_todo.yml`
- `puppet-strings` ~> 4.0 (release_prep group) - API docs generation; `.yardopts` and `.yardoc/` present
- `github_changelog_generator` 1.16.4 and `octokit` 4.21.0 - Changelog generation (`rake changelog`); `CHANGELOG.md` and `HISTORY.md` maintained
- `dependency_checker` ~> 1.0.0 - Dependency audit
- `orchestrator_client` < 0.7.1 - Development dependency pinned for CI stability (`.sync.yml`)
- Vagrant/Docker/Litmus test environment: `.devcontainer/`, `provision.yaml`, `pedev_inventory.yaml`, `.fixtures.yml`

## Key Dependencies

**Critical (declared in `metadata.json` `dependencies`):**
- `puppetlabs/stdlib` `>= 9.0.0 < 11.0.0` - Core Puppet helper functions used in plans and functions
- `puppetlabs/node_manager` `>= 1.0.1 < 2.0.0` - Node group management; see `manifests/setup/node_manager.pp`
- `puppet/format` `>= 0.1.0 < 3.0.0` - String formatting helpers
- `puppetlabs/service` `>= 1.3.0 <= 4.0.0` - Service management resources
- `puppetlabs/package` `>= 2.1.0 <= 4.0.0` - Package management resources
- `puppetlabs/inifile` `>= 6.1.0 < 7.0.0` - INI file management
- `puppetlabs/ruby_task_helper` `>= 1.0.0 < 2.0.0` - Task helper library used by Ruby tasks

**Fixture-only (in `.fixtures.yml`, not runtime dependencies):**
- `puppetlabs/reboot`, `puppetlabs-facts`, `puppetlabs-puppet_agent`, `provision` (v3.2.0), `apply_helpers`, `bolt_shim`, `container_inventory` (gitlab.com/nwops), `puppetlabs-bolt_shim`, `format` (voxpupuli)
- Symlinks: `peadm` and `peadm_spec` point into `spec/fixtures/modules/` for test runs

**Vendored test modules:**
- `spec/fixtures/modules/` contains third-party Puppet modules downloaded for tests (`apply_helpers`, `bolt_shim`, `container_inventory`, `facts`, `format`, `inifile`, `node_manager`, `package`, `peadm`, `peadm_spec`, `provision`, `puppet_agent`, `reboot`, `ruby_task_helper`, `service`, `stdlib`). These are treated as dependencies and are not analyzed internally.

**Infrastructure:**
- Puppet Forge - Source for module dependencies (`https://forge.puppet.com`, referenced in `plans/util/retrieve_and_upload.pp`)
- `puppetcore` private gem source - `https://rubygems-puppetcore.puppet.com`, used only when `PUPPET_FORGE_TOKEN` is set (`Gemfile`)

## Configuration

**Environment:**
- No application `.env` file is read by the module. Installer and deployment inputs are Bolt plan parameters (e.g. `pe_installer_source`, `version`, `dns_alt_names`) defined in `plans/install.pp`, `plans/upgrade.pp`, and `plans/subplans/install.pp`.
- Ruby tasks check `ENV['RSPEC_UNIT_TEST_MODE']` to skip execution during unit tests (e.g. `tasks/get_peadm_config.rb`, `tasks/rbac_token.rb`).
- `CHANGELOG_GITHUB_TOKEN` is required for `rake changelog` (`Rakefile`).
- `PUPPET_GEM_VERSION`, `FACTER_GEM_VERSION`, `HIERA_GEM_VERSION` select Puppet/Facter/Hiera gem versions (`Gemfile`).
- `PUPPET_FORGE_TOKEN` and `BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM` enable private gem resolution in CI (`.github/workflows/spec.yml`).
- Gemfile evaluates `Gemfile.local` and `~/.gemfile` if present.
- Existence of `.env*` files was not inspected for contents by design.

**Build:**
- `Gemfile`, `Gemfile.lock`, `Puppetfile`, `.fixtures.yml`, `.sync.yml`, `pdk.yaml`, `metadata.json`
- Lint and style: `.puppet-lint.rc`, `.rubocop.yml`, `.rubocop_todo.yml`
- Test: `.rspec`, `spec/spec_helper*.rb`, `.pdkignore`, `.gitattributes`
- CI: `.github/workflows/` (GitHub Actions, including `ci.yml`, `spec.yml`, `release.yml`, `release-prep.yml`, `auto_release.yml`, `nightly.yml`, and PE install/upgrade/failover scenario workflows), `.gitlab-ci.yml`, `appveyor.yml`
- Dev environment: `.devcontainer/`

## Platform Requirements

**Development:**
- Ruby 3.1.0 (per `.ruby-version`) with Bundler
- Bolt `>= 4.0.0` and Puppet 8.x (`Gemfile`)
- `bundle exec rake spec_prep` and `rake parallel_spec` for unit tests; `rake validate lint check rubocop` for static checks
- Linux recommended; Windows agent helper tasks exist but are not the primary development target

**Supported target OS (`metadata.json` `operatingsystem_support`):**
- Amazon Linux 2
- AlmaLinux 8, 9
- RedHat 7, 8, 9
- CentOS 9
- Ubuntu 18.04, 20.04, 22.04, 24.04
- SLES 12

**Production:**
- Module is published to the Puppet Forge as `puppetlabs-peadm` (version 3.40.0 per `metadata.json`) and executed via Bolt against PE infrastructure nodes (primary, replica, compiler, and PostgreSQL nodes).
- Supported PE range: 2019.7 through 2026.0 (`data/pe_versions.yaml`).

---

*Stack analysis: 2026-11-10*

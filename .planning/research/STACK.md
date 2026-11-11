# Technology Stack

**Project:** PEADM Modernization (safe upgrades, failover/day-2, CD4PE and SCM automation)
**Researched:** 2026-11-10
**Scope:** What to run, test with and integrate against. The existing system is not re-researched (see `.planning/codebase/STACK.md`).

## Headline Findings

Six things changed since the codebase map was written or are not visible in it. They drive the recommendations below.

1. **Bolt is now 5.x and is licence-gated.** Current is Bolt 5.2.1 (2026-10-05). Since 5.0.0 (2025-09-23) Bolt ships only as an OS package from an authenticated repo (username `forge-key` + Puppet Core API key, or `license-id` + PE licence ID). Gem install, Homebrew, Chocolatey, the PuppetBolt PowerShell module and the Docker image were removed. The public `bolt` gem on rubygems.org stops at **4.0.0 (2024-12-03)**. PEADM's `Gemfile` (`bolt >= 4.0.0`), `Gemfile.lock` (bolt 4.0.0) and the `BOLT_GEM=true` workflows are on the frozen gem path. [HIGH]
2. **Puppet 9 / Ruby 4 is real.** PE 2026.0 supports Puppet 9. Bolt 5.2.0+ packages bundle Puppet 8 (Ruby 3) and Puppet Core 9 (Ruby 4). PDK 4.0 (Oct 2026) targets Puppet 8 and Puppet Core 9. `cd4peadm` 5.17+ supports Puppet 9. PEADM's `metadata.json` still says `puppet >= 8.0.0 < 9.0.0`. [HIGH]
3. **Support lifecycle moved to Latest / Latest-1.** PE 2025.y and 2026.y are current; 2023.8 (last LTS) maintenance ended 2026-08-27 and overlap support ends **2027-02-27**. Latest security release is PE 2026.0.1 / 2025.12.1 / 2023.8.13 (Nov 2026). [HIGH]
4. **CD4PE and SCM both install with their own premium Bolt modules, not with PEADM.** `puppetlabs/cd4peadm` (5.19.0, 2026-10-27) and `puppetlabs/complyadm` (3.9.1, 2026-09-01) are Forge-premium, token-gated, container-based (Docker or Podman), and must run from a Bolt project separate from PE. PEADM should wrap and operate them, not reimplement them. [HIGH]
5. **The test gems are a major version behind.** `puppetlabs_spec_helper` 6.0.3 -> 9.0.0, `rspec-puppet` 4.0.2 -> 5.0.0 (6.0.0 exists, helper 9 pins `~> 5.0`), `rspec-puppet-facts` ~> 2.0 -> 6.3.x, `puppet_litmus` 2.8.1 is already current. [HIGH]
6. **Several Puppet 9 / PE 2026 behaviour changes touch PEADM code directly** (see "Puppet 9 / PE 2026 impact on PEADM code"). [MEDIUM-HIGH]

## Recommended Stack

### Core Framework (controller side)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Puppet Bolt (OS package) | 5.2.x (current 5.2.1) for operators and the acceptance "real jumphost" lane | Runs PEADM plans and tasks | Current supported line; 5.2.0 packages work with Puppet 8 and Puppet Core 9 without depending on the host Ruby/Puppet. Release notes: 5.1.2 fixed `bolt apply` over PCP, 5.2.1 refreshed bundled modules for Puppet Core 9 | HIGH |
| Puppet Bolt (gem) | `4.0.0` (pinned, last public gem) for unit specs and Litmus-driven CI | `BoltSpec::Plans`, `bolt plan run` in CI | Only version obtainable without credentials. Litmus 2.8.1 depends on `bolt >= 4.0, < 6.0`. Keep until CI has Bolt 5 credentials (see Open Questions) | MEDIUM |
| Puppet DSL plans + Ruby/Bash tasks | unchanged | Orchestration | Constraint in PROJECT.md. Bolt has no native resume or retry, so keep `peadm::plan_step` as the resumability mechanism and `catch_errors` / `_catch_errors` for failure handling | HIGH |
| Puppet language requirement | `>= 8.0.0 < 10.0.0` (change from `< 9.0.0`) | `metadata.json` `requirements` | Bolt 5.2 can run plans under Puppet Core 9; `cd4peadm` 5.19.0 already declares `>= 7.0.0 < 10.0.0`, `complyadm` `< 10.0.0` | HIGH |
| Supported Bolt range | keep `>= 3.17.0 < 6.0.0` in `peadm::assert_supported_bolt_version`; raise floor to `>= 4.0.0` in a later cleanup | Version gate | Already admits Bolt 5.x. cd4peadm needs `>= 3.27.4` and complyadm `>= 3.27.2`, so no conflict. Do not widen to 6 until tested | HIGH |

### Target-side runtime (PE being managed)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Puppet Enterprise | 2023.8.x (maintenance ends 2027-02-27), 2025.12.1, 2026.0.1 as test lines | Product under automation | `data/pe_versions.yaml` `newest: '2026.0'` already covers 2026.0.x. Acceptance matrix should use newest patch of each of the three lines | HIGH |
| Primary OS test set | EL 8, EL 9, EL 10 (RHEL), Ubuntu 22.04, 24.04, 26.04, SLES 15, Amazon Linux 2023 | Target platforms | PE 2026.0.1 primary platform list. Ubuntu 26.04 and EL 10 are new primary platforms in 2026.0; Ubuntu 20.04 and Amazon Linux 2 primary support was dropped | HIGH |
| Stale `metadata.json` OS entries | Amazon 2, RedHat 7, Ubuntu 18.04, SLES 12 | Declared OS support | No longer valid PE primary platforms in any current line. Remove, and add EL 10, Ubuntu 26.04, SLES 15, AL2023. Needs an explicit decision (PROJECT.md scopes out work for pre-2023.8, but the list is metadata, not test coverage) | MEDIUM |
| PE database-backed CA (`pe-ca` PostgreSQL DB) | default on new 2026.0 installs; kept on upgrade | CA storage | Changes what "back up the CA" means and makes a lost CA passphrase unrecoverable. Backup/DR plans must detect the CA backend | HIGH |

### Premium modules PEADM must integrate with (CD4PE / SCM)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| `puppetlabs/cd4peadm` | 5.19.0 (module version == CD app version) | Install, upgrade, config, ctl for Continuous Delivery 5.x | Official and only supported installer. Plans seen in docs and cases: `install`, `install_from_config`, `generate_config`, `upgrade`, `apply_configuration`, `ctl`, `uninstall`, `upload_trusted_certs`. Premium: needs a Forge API token in `bolt-project.yaml` `authorization_token: 'Bearer <token>'` | HIGH |
| `puppetlabs/complyadm` | 3.9.1 (SCM 3.x) | Install, upgrade, backup, validate, configure, migrate SCM server | Official installer: `complyadm::install`, `::upgrade`, `::backup`, `::validate`, `::configure`, `::migrate` (2.x to 3.x), `::install::create_offline_bundle` | HIGH |
| `puppetlabs/comply` | 3.9.1 | PE-side module/task that runs the CIS assessor on scan targets; deployed through Puppetfile/Code Manager | Version must match SCM major.minor. Needs SCM certificates generated in PE first | MEDIUM |
| `puppetlabs/cd4pe_jobs` | >= 1.7.4 (current 1.7.6) | Job-side module in PE | CD 5.16.0 requires >= 1.7.4. Upgrade preflight should check it | HIGH |
| Container runtime on CD / SCM host | Podman >= 4.9.4 or Docker >= 26.1.3 (CD air-gapped doc minimums) | Runs CD and SCM containers | Podman is the default direction (systemd units `podman-pipelinesinfra`, `podman-query` seen in CASE-029). Docker path needs `puppetlabs/docker` 9.1.0, `apt` 9.4.0, `reboot` 5.0.0, `stdlib` 9.6.0 in the Bolt project | HIGH (versions) / MEDIUM (which is preferred) |
| CD host sizing | 4 CPU, 8 GB RAM, 100 GB `/var/lib`; not on a PE node | Preflight thresholds | Official system requirements. SCM is identical (4 / 8 GB / 100 GB) | HIGH |
| CD external PostgreSQL | PostgreSQL 17, TLS `verify-full`, `max_connections >= 60`, `pgcrypto` and `lo` extensions, both `cd4pe` and `query` DBs on one instance | Optional external DB (since cd4peadm 5.16.0) | Preflight list for the external-DB path | HIGH |
| CD host OS | Docker: Alma/Rocky/OL/RHEL 8-9, AL2023, Ubuntu 20.04-24.04. Podman: Alma/Rocky/OL/RHEL 8-9, SLES 15, Ubuntu 22.04-24.04 | Preflight OS check | Official list. Note it does not yet list EL 10 or Ubuntu 26.04 | HIGH |
| SCM host OS | Alma/OL/Rocky 8-9, RHEL 7-10, Debian 12, SLES 12/15, Ubuntu 18.04-24.04 | Preflight OS check | Official list. Compatible PE: 2025.0+, 2023.0+, 2021.7.2+ | MEDIUM (page tables lack headers) |

**Integration decision: wrap, do not fork.** PEADM plans (`peadm::cd4pe::*`, `peadm::scm::*` or similar) should call `cd4peadm::` / `complyadm::` plans via `run_plan` from a managed Bolt project, add PEADM-side preflight and post-checks, and never copy their internals. Reasons: the modules are premium and version-locked to the application; CD4PE/SCM internals are out of scope in PROJECT.md; and recent bugs (CASE-019 image tarball format, CASE-013 CRL header, CASE-032 RSA-only key parsing) live inside those modules and are fixed upstream (cd4peadm 5.16.0 fixed non-RSA chain verification).

**What the CD4PE and SCM modules do not provide** (and therefore what PEADM can add):
- cd4peadm docs describe no backup, rollback or general preflight for upgrades. SCM has preflight (`ignore_failing_preflights`) and an optional `complyadm::backup`, but its docs state no general rollback.
- Neither handles the post-patching or reboot recovery flow, a lost Bolt project (CASE-005, CASE-028), or air-gapped image verification (CASE-019's `unexpected EOF`) beyond what the installer does.
- Known cd4peadm gotchas to encode as preflights: Windows Bolt runner unsupported; `/tmp` mounted `noexec` breaks Bolt; Podman reboot leaves stale `/etc/puppetlabs/cd4pe/*.ip.txt` (fixed in 5.2.0, but older installs exist); 5.18.0 memory regression (fixed 5.19.0; workaround `java_args: "-Xmx2048M -Xms2048M"` in `data/common.yaml` then `cd4peadm::apply_configuration`); upgrade from a version before 3.7.1 on SCM requires 3.7.1 first.

### Dependent Puppet modules (PEADM `metadata.json` / `Puppetfile`)

| Module | PEADM today | Latest | Recommendation | Confidence |
|--------|-------------|--------|----------------|------------|
| `puppetlabs/stdlib` | `>= 9.0.0 < 11.0.0`, Puppetfile 9.5.0 | 10.1.1 (2026-10-27) | Keep range, move Puppetfile pin to 10.1.1 after a Puppet 8 and Puppet 9 spec run. Note: cd4peadm 5.19.0 docs pin stdlib 9.6.0 in its own project, so never share one Bolt project between PEADM and cd4peadm | HIGH |
| `puppetlabs/node_manager` | `>= 1.0.1 < 2.0.0`, Puppetfile 1.0.1 | 1.1.0 (2024-09-16), declares `puppet < 9.0.0` | Stay at 1.0.1 unless a bug needs 1.1.0 (history: PE-36915 and PE-39099 were node_manager regressions). Must verify Bolt 5.2 + Puppet Core 9 loads it; if not, upstream or vendor change is needed. PEADM's own `manifests/setup/node_manager.pp` depends on it | MEDIUM |
| `puppet/format` | `>= 0.1.0 < 3.0.0`, Puppetfile 1.1.1 | 2.2.0, declares an `openvox` requirement instead of `puppet` | Stay on 1.1.1. Do not bump to 2.x without testing; its metadata now targets OpenVox | MEDIUM |
| `puppetlabs/service`, `package` | `<= 4.0.0` | 4.0.0 (2026-08-31), `puppet >= 8 < 10` | Already compatible | HIGH |
| `puppetlabs/inifile` | `>= 6.1.0 < 7.0.0` | 6.6.0 | Compatible | HIGH |
| `puppetlabs/ruby_task_helper` | `>= 1.0.0 < 2.0.0` | 1.1.0 | Compatible | HIGH |
| `puppetlabs/puppet_agent`, `facts` (fixtures, git HEAD) | unpinned git HEAD | 4.28.0; facts 1.8.1 | Pin fixtures to tags. Unpinned HEAD in `.fixtures.yml` makes spec runs non-reproducible | HIGH |
| `puppetlabs/provision` (fixture) | ref v3.2.0 | v3.2.0 (2026-10-29) | Current | HIGH |

### Health-check building blocks (do not rebuild)

| Technology | Version | Purpose | When to use | Confidence |
|------------|---------|---------|-------------|------------|
| `puppetlabs/puppet_status_check` (successor to `pe_status_check`) | 0.10.0 (2026-10-20), `puppet >= 8 < 10` | Maintained indicator set (`pe_status_check` fact), exposes support-derived health indicators | Source indicators for the pre-upgrade and pre-failover health gate rather than inventing new ones. The older `pe_status_check` 4.6.0 is `< 9.0.0` and bundled with PE; avoid installing both. Confirm which one the target PE ships before relying on the fact | MEDIUM |
| `puppet infrastructure status`, `puppet-backup`, `puppet infrastructure recover_configuration`, `puppet infrastructure configure` | shipped with PE | Native PE health, backup, and recovery | Already used by PEADM. PE docs: major primary OS upgrades require backup + restore (or migrate), `puppet-backup` does not cover replicas, compilers or secret keys, and a restore needs the same PE version | HIGH |

### Testing and tooling

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| `puppetlabs_spec_helper` | `~> 9.0` (now 6.0.3) | rake spec tasks, fixtures | 9.0.0 (2026-08-20): uses puppetlabs-syntax, drops Puppet 7 infra, allows puppet-lint 5.x, adds Ruby 4 / Puppet 9 nightly lane. v8 removed build tasks and added Forge auth for fixtures. Requires Ruby `>= 3.2` | HIGH |
| `rspec-puppet` | `~> 5.0` (now 4.0.2). 6.0.0 exists but helper 9 pins `~> 5.0`; do not pin ahead of the helper | Catalog, function, type specs | Follow the helper; avoid a second source of drift | HIGH |
| `rspec-puppet-facts` | `~> 6.3` (now `~> 2.0`) and `facterdb ~> 4.5` (now `~> 1.18`) | OS fact sets for spec matrices | Needed to get EL 10 / Ubuntu 26.04 facts for the new primary platforms. Requires Ruby `>= 3.2` | MEDIUM (check facterdb fact-set coverage for EL10 / 26.04 before the bump) |
| `BoltSpec::Plans` (inside Bolt) | via Bolt gem | Plan unit tests with mocked `run_task` / `run_command` | Already used (`spec/plans`). Extend for every new plan: preflight, failover, CD/SCM wrappers. Cheap and catches parameter plumbing errors (the duplicated-parameter-list debt) | HIGH |
| `puppet_litmus` | 2.8.1 (2026-09-23, current); `~> 2.8` | Provisioning and acceptance harness | Already in use. 2.4.0 added Bolt 5 support, 2.8.1 added Ubuntu 26.04 Docker, 2.6.0 RHEL-10 provision-service matrix. Requires Ruby `>= 3.1` | HIGH |
| `puppetlabs/provision` | v3.2.0 | Litmus provisioners (`provision_service`, docker, etc.); existing acceptance plans `peadm_spec::provision_test_cluster` use `provider=provision_service` | Keep. Cost is the real constraint: full PE clusters take up to 120 min (workflow timeouts), so keep the catalog-driven on-demand model in `spec/acceptance/scenarios.yaml` | HIGH |
| `puppet-lint` | 5.1.1 via `voxpupuli-puppet-lint-plugins ~> 7.0` (now `~> 5.0`, which pins an older lint) | Lint | Helper 9 requires `puppet-lint ~> 5.0`; plugin 7.0.0 requires `puppet-lint ~> 5.1` | HIGH |
| `puppet-strings` | `~> 5.1` (now `~> 4.0`) | REFERENCE.md generation | PDK 4.0 template pins puppet-strings v5 | MEDIUM |
| `metadata-json-lint` | `~> 5.1` (now `~> 3.0`) | metadata validation | Current. Recheck rules once `puppet` requirement and OS list change | MEDIUM |
| `rubocop` | pin per `voxpupuli-rubocop ~> 5.3` family rather than hand-pinned `= 1.79.0` | Style | Hand-pinned rubocop plus six plugin pins is the maintenance burden; PDK 4.0 "streamlined RuboCop defaults" | LOW-MEDIUM |
| `parallel_tests` | `~> 5.9` (now `= 3.12.1`) | `rake parallel_spec` | Hard pin at 3.12.1 predates Ruby 3.4 / 4.0 | LOW-MEDIUM |
| PDK | 4.0.1 (Oct 2026) | Template sync, `pdk validate` | Optional. Next `pdk update` brings Puppet Core as the default gem source, `GEM_SOURCE_PUPPETCORE` env var no longer supported (use `bundle config set gemsource.public true`) | HIGH |
| Ruby (dev + CI) | 3.3 or 3.4 primary lane; 3.1 as floor until CI matrix drops it; add a Ruby 4.0 + Puppet 9 lane | Test runtime | spec helper 9 / rspec-puppet-facts 6 require Ruby >= 3.2. Existing Gemfile already carries Ruby 4 default-gem shims (benchmark, ostruct, logger, csv, base64) | MEDIUM |
| Puppet gem source | `rubygems-puppetcore.puppet.com` via `PUPPET_FORGE_TOKEN` (already in Gemfile) | Puppet 8.17+ / Puppet 9 gems | Public `puppet` gem stops at 8.10.0 (Oct 2024). Bolt 5.1.0 bundles Puppet Core 8.17.0. A matrix that only uses rubygems.org is testing a 2-year-old Puppet | HIGH |

### Infrastructure (CI)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| GitHub Actions | existing | Unit + on-demand acceptance workflows | Already hosts 20+ scenario workflows. Replace `actions/checkout@v4` / `ruby/setup-ruby@v1` floating usage when touched; drop `.gitlab-ci.yml` Ruby 2.5/2.7 entries (Puppet 6/7 are out of scope) | HIGH |
| GCP images via Litmus `provision_service` | existing | Test clusters | Existing default (`almalinux-cloud/almalinux-8`). Add `rhel-10`, `ubuntu-2604` images once the provision service lists them | MEDIUM |
| Private package registry mirror (air-gap tests) | n/a | Simulate air-gapped CD / SCM / PE installs | CD air-gapped needs 5 image archives; SCM needs `create_offline_bundle` and a pre-installed runtime. Acceptance for air-gap should block egress on the target, not on the controller | MEDIUM |

## Puppet 9 / PE 2026 impact on PEADM code

Concrete items found by grepping the repository. These are stack-compatibility tasks, not new features. Confidence: MEDIUM-HIGH (vendor doc + local code evidence; not yet run on Puppet 9).

| Change in Puppet Core 9 / PE 2026 | PEADM location | Action |
|-----------------------------------|----------------|--------|
| `/status/v1/services` requires an authenticated client (`/status/v1/simple` stays open) | `tasks/code_sync_status.rb` (uses host cert; likely fine), `tasks/wait_until_service_ready.sh` (uses `/status/v1/simple`; fine) | Verify with an acceptance run on PE 2026.0. Never add unauthenticated `curl` calls to `/status/v1/services` in new health checks |
| `bootstrap.cfg` replaced with a new uncustomised file, old one not overwritten | `plans/backup.pp` line 62 and `plans/restore.pp` line 108 read `/etc/puppetlabs/puppetserver/bootstrap.cfg` | Re-test backup/restore on 2026.0; do not assume customisations are in the file that is read |
| PuppetDB plaintext listener (port 8080) disabled by default in 2026.0 | No `8080` references found in `tasks/`, `plans/`, `functions/` | Keep it that way; use 8081 with certs |
| Hardcoded RSA key parsing breaks EC / SEC1 keys (PE notes EC SEC1 catalog failures in 2025.11.x, CASE-032 for cd4peadm) | `tasks/code_sync_status.rb`: `OpenSSL::PKey::RSA.new` on `hostprivkey` | Use `OpenSSL::PKey.read`. Same pattern as the cd4peadm bug |
| `preprocess_deferred` defaults to true; strict mode; JDK 21 / PostgreSQL 17 / OpenSSL 3.5 | Plans using `Deferred` (if any) and the PostgreSQL major-upgrade path (`plans/util/*db*`; the `test-upgrade-pg-major-ha-nightly` workflow exists) | Add PG 17 major upgrade to the scenario catalog |
| Database-backed CA; `puppetserver ca storage --cleanup-fs` needs root and DB backend | `plans/backup_ca.pp`, `restore_ca.pp`, migration plans | New scenario and backend detection in preflight. Backup must handle the CA passphrase |
| `metadata.json` `puppet < 9.0.0`, OS list stale, `data/pe_versions.yaml` `newest: '2026.0'` while `plans/install.pp` default is `2025.12.1` | `metadata.json`, `plans/install.pp` | Update together; add a spec asserting the default version is within `peadm::supported_pe_versions()` |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Orchestrator | Bolt 5.x (package) | OpenBolt (OpenVox fork), Ansible, Puppet Enterprise task/plan orchestrator only | PROJECT.md: staying on Bolt is a decision. Bolt 5 needs PE licence credentials, which every PEADM user already has. OpenBolt would fork the support story. The PE orchestrator cannot drive the infra upgrade itself (restarts the orchestration service; `fail_on_transport` already bans `pcp` for the primary) |
| Bolt in CI | Bolt 4.0.0 gem now, Bolt 5.2 package lane added | Bolt 5 only | CI cannot obtain Bolt 5 anonymously on forks. Keep a credentialed lane for the real jumphost path only |
| CD4PE/SCM install | Wrap `cd4peadm` / `complyadm` | Reimplement container + systemd installs in PEADM | Premium, version-locked, out-of-scope internals; would duplicate and then diverge from vendor fixes (non-RSA keys, CRL header, image handling) |
| Health indicators | Reuse `puppet_status_check` indicators plus PEADM-specific preflights | Write all checks from scratch | Support-curated indicator set already exists; PEADM adds only topology-aware checks (availability groups, replica state, legacy compiler OIDs) |
| Test harness | Litmus + BoltSpec + scenario catalog | Test Kitchen, Vagrant-only, pure rspec | Litmus is the module-ecosystem standard and already wired to `provision_service`. Pure rspec cannot prove installer, service and cluster behaviour (PROJECT.md constraint) |
| Rollback mechanism | Documented, tested snapshot + `puppet-backup` + restore/migrate; plan-level resume via `plan_step` | Installer "downgrade" | PE installer blocks downgrade (CASE-009 "You can't upgrade to a version that was..."); PE docs treat backup-restore or migrate as the OS-upgrade and recovery path. Do not promise in-place downgrade |
| Version-range data | `data/pe_versions.yaml` | Hardcoded constants | Already decided (PE-47850) |
| Plan state for resume | `peadm::plan_step` | External state store, database, Bolt rerun | Bolt keeps plan state in memory only and has no resume; an external store adds a new component the project excludes. Extend `Peadm::UpgradeSteps` and add a persisted marker only if cross-session resume proves necessary |

## Installation

```bash
# Controller (operators): Bolt 5.x from the authenticated repo
#   Debian/Ubuntu: wget https://apt-puppetcore.puppet.com/public/puppet8-release-<codename>.deb
#                  dpkg -i it, put credentials in /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf
#   RHEL:          rpm -Uvh https://yum-puppetcore.puppet.com/public/puppet8-release-el-<N>.noarch.rpm
#                  put username/password in /etc/yum.repos.d/puppet8-release.repo
sudo apt-get install puppet-bolt        # or: sudo yum install puppet-bolt

# Developer / CI: unit specs (no credentials needed)
bundle install
bundle exec rake spec_prep
bundle exec rake parallel_spec

# Developer / CI with Puppet 8.17+ or Puppet 9 gems (credentials needed)
export PUPPET_FORGE_TOKEN=<puppet-core-forge-key>   # Gemfile switches to rubygems-puppetcore.puppet.com
PUPPET_GEM_VERSION='~> 9.0' bundle update puppet

# Proposed Gemfile dev-group changes (verify resolution on Ruby 3.3/3.4 first)
#   gem "puppetlabs_spec_helper", "~> 9.0"
#   gem "rspec-puppet-facts",     "~> 6.3"
#   gem "facterdb",               "~> 4.5"
#   gem "voxpupuli-puppet-lint-plugins", "~> 7.0"
#   gem "puppet-strings",         "~> 5.1"
#   gem "metadata-json-lint",     "~> 5.1"
#   gem "parallel_tests",         "~> 5.9"
#   gem "bolt", "= 4.0.0"          # last public gem; litmus allows >= 4.0, < 6.0
#   gem "puppet_litmus", "~> 2.8"

# CD4PE (separate Bolt project, separate host from PE)
bolt project init cd4pe_bolt_project
#   bolt-project.yaml: modules: [{name: puppetlabs-cd4peadm, version_requirement: 5.19.0}]
#                      authorization_token: 'Bearer <forge-api-token>'
bolt module install
bolt plan run cd4peadm::install        # or generate_config + install_from_config for non-interactive
bolt plan run cd4peadm::upgrade        # after bumping version_requirement and `bolt module install --force`

# SCM (separate Bolt project, not on the PE host)
bolt project init comply_bolt_project
#   bolt-project.yaml: modules: [{name: puppetlabs-complyadm, version_requirement: 3.9.1}] + Forge token
bolt module install
bolt plan run complyadm::install
bolt plan run complyadm::upgrade       # air-gapped: complyadm::install::create_offline_bundle first
```

## Open Questions (need decisions or a spike)

1. **Where do CI and Litmus get a Bolt 5 binary from?** The public gem is frozen at 4.0.0 and Bolt 5 is not installable as a gem per its release notes, yet Litmus 2.8.1 advertises Bolt 5 support. Could not verify whether `rubygems-puppetcore.puppet.com` hosts a `bolt` gem (index returned 401 without a token). Spike: with a Puppet Core token, test `bundle update bolt` against the puppetcore source. Confidence in the "gem stays at 4.0.0" plan: MEDIUM.
2. **Does PEADM run unchanged on Bolt 5.2 packaged Puppet Core 9?** Not tested. Spike: run `bundle exec rake spec` and one `peadm::status` plus one `peadm::upgrade` acceptance on PE 2026.0.1 under Puppet 9, with `node_manager` 1.0.1 and `format` 1.1.1.
3. **Does `puppet_status_check` ship on the PE lines PEADM supports**, and which fact name should preflights read? Verify on a 2023.8.13, 2025.12.1 and 2026.0.1 cluster before designing the health gate.
4. **Support decision:** keep `oldest: '2019.7'` in `data/pe_versions.yaml` and stale OS entries in `metadata.json`, or tighten? Out of scope per PROJECT.md without an explicit decision, but they conflict with the vendor lifecycle.
5. **CD host OS gap:** cd4peadm docs do not yet list EL 10 or Ubuntu 26.04. Do not promise those for CD/SCM preflights.

## Sources

- Bolt release notes (5.0.0 to 5.2.1): https://help.puppet.com/bolt/current/topics/changelog.htm [HIGH, official]
- Bolt 5 install and credentials: https://help.puppet.com/bolt/current/topics/bolt_installing.htm [HIGH, official]
- Install Puppet Core on Bolt targets: https://help.puppet.com/bolt/current/topics/bolt_install_core_on_targets.htm [HIGH, official]
- Bolt plan-language reference (no native resume/retry, `catch_errors`): https://help.puppet.com/bolt/current/topics/writing_plans.htm [HIGH, official]
- RubyGems API for `bolt`, `puppet`, `puppet_litmus`, `puppetlabs_spec_helper`, `rspec-puppet`, `rspec-puppet-facts`, `puppet-lint`, `voxpupuli-puppet-lint-plugins`, `puppet-strings`, `metadata-json-lint`, `facterdb`, `parallel_tests`: https://rubygems.org/api/v1/gems/<name>.json (queried 2026-11-10) [HIGH]
- Forge API for module versions and `puppet` requirements (`peadm`, `cd4peadm`, `complyadm`, `comply`, `cd4pe_jobs`, `stdlib`, `node_manager`, `puppet_agent`, `puppet_status_check`, `pe_status_check`, `service`, `package`, `inifile`, `ruby_task_helper`, `docker`, `facts`, `reboot`, `format`): https://forgeapi.puppet.com/v3/modules/<name> (queried 2026-11-10) [HIGH]
- puppetlabs_spec_helper changelog: https://raw.githubusercontent.com/puppetlabs/puppetlabs_spec_helper/main/CHANGELOG.md [HIGH]
- puppet_litmus changelog: https://raw.githubusercontent.com/puppetlabs/puppet_litmus/main/CHANGELOG.md [HIGH]
- PDK 4.0 release notes: https://help.puppet.com/pdk/current/topics/release_notes_pdk.htm [HIGH, official]
- Puppet 8 to 9 upgrade guide: https://help.puppet.com/core/current/Content/PuppetCore/upgrading-from-puppet8-to-puppet9.htm [HIGH, official]
- PE 2026.0 release notes: https://help.puppet.com/pe/current/topics/release-notes-pe-x-0.htm [HIGH, official]
- PE support lifecycle (Latest / Latest-1, 2023.8 dates): https://www.puppet.com/products/puppet-enterprise/support-lifecycle [HIGH, official]
- PE downloads (2026.0.1 primary platforms): https://www.puppet.com/downloads/puppet-enterprise [HIGH, official]
- PE what's new (2026.0.1 / 2025.12.1 / 2023.8.13 security release): https://www.puppet.com/products/puppet-enterprise/whats-new [MEDIUM, summarised page]
- PE upgrading overview: https://help.puppet.com/pe/current/topics/upgrading.htm [HIGH, official; upgrade-paths and rollback subpages not read]
- CD install: https://help.puppet.com/cdpe/current/Content/UserGuide/CDPE/Installation/cd_install.htm [HIGH, official]
- CD air-gapped install: https://help.puppet.com/cdpe/current/Content/UserGuide/CDPE/Installation/cd_install_airgapped.htm [HIGH, official]
- CD system requirements: https://help.puppet.com/cdpe/current/Content/UserGuide/CDPE/Installation/cd_system_requirements.htm [HIGH, official]
- CD upgrade: https://help.puppet.com/cdpe/current/Content/UserGuide/CDPE/Upgrade/upgrade-application.htm [HIGH, official]
- CD release notes 5.14 to 5.18 (5.19.0 date from search snippet): https://help.puppet.com/cdpe/current/Content/UserGuide/CDPE/ReleaseNotes/cd_release_notes.htm [HIGH / MEDIUM for 5.19]
- CD known issues: https://help.puppet.com/cdpe/current/Content/UserGuide/CDPE/ReleaseNotes/known_issues_cdpe.htm [HIGH, official]
- SCM install: https://help.puppet.com/scm/current/Content/UserGuide/SCM/Installation/scm_bolt_install.htm [HIGH, official]
- SCM module install: https://help.puppet.com/scm/current/Content/UserGuide/SCM/Installation/install_scm_module.htm [HIGH, official]
- SCM system requirements: https://help.puppet.com/scm/current/Content/UserGuide/SCM/Installation/scm_system_requirements.htm [MEDIUM, tables lack headers]
- SCM air-gapped upgrade: https://help.puppet.com/scm/current/Content/UserGuide/SCM/Upgrading/upgrade_scm_airgapped.htm [HIGH, official]
- Puppetlabs modules roundup, August 2026 (cd4peadm 5.17/5.18, comply 3.9.0, stdlib 10.0.2): https://dev.to/puppet/puppetlabs-modules-roundup-august-2026-38ch [MEDIUM, vendor blog]
- Local evidence: `/home/matthew/Code/puppetlabs-peadm/Gemfile`, `Gemfile.lock`, `metadata.json`, `.fixtures.yml`, `.github/workflows/test-upgrade.yaml`, `functions/assert_supported_bolt_version.pp`, `tasks/code_sync_status.rb`, `plans/backup.pp`, `plans/restore.pp`; support cases and Jira tickets in `~/Code/peadm.csv` (CASE-005, 009, 013, 019, 028, 029, 031, 032; PE-36915, PE-39099, CDPE-6936/6941/7433, GJira-5/10/12/14)

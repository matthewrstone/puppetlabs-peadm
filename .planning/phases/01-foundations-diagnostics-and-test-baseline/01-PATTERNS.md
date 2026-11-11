# Phase 1: Foundations, Diagnostics and Test Baseline - Pattern Map

**Mapped:** 2026-11-10
**Files analyzed:** 27 new/modified
**Analogs found:** 25 / 27

Locked after research: Ruby floor 3.3 (not 3.2); cert helper adoption only in `tasks/code_sync_status.rb`; ticket keys are placeholders P0-1..P0-3. All analog paths below are git-tracked (checked `git ls-files` for the ones that live outside obvious tracked dirs).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `files/failure_report.sh` (new) | utility (shell fn lib) | transform | `tasks/pe_install.sh` `report_install_failure` (lines 24-42) | exact (lift) |
| `tasks/pe_install.sh` (mod) | task | request-response | itself | n/a |
| `tasks/pe_install.json` (mod) | config | - | itself (`files` array) | n/a |
| `tasks/wait_until_service_ready.sh/.json` (mod) | task | polling | itself | n/a |
| `functions/wait_until_service_ready.pp` (mod) | function | request-response | itself | n/a |
| `tasks/code_manager.sh` (mod) | task | request-response | `tasks/pe_install.sh` | role-match |
| `files/cert_check.rb` (new) | utility | transform | `tasks/code_sync_status.rb` cert/key load (lines 23-30) | partial |
| `tasks/validate_cert.rb/.json` (new) | task | request-response | `tasks/code_sync_status.rb` + `tasks/pe_install.json` (`files`) | role-match |
| `tasks/code_sync_status.rb` (mod) | task | request-response | itself | n/a |
| `spec/unit/task/validate_cert_spec.rb` (new) | test | - | `spec/unit/task/code_sync_status_spec.rb` | role-match |
| `spec/support/shell_task_harness.rb` (new) | test helper | file-I/O | RESEARCH.md "Harness core" (no in-repo analog) | none |
| `spec/unit/shell_tasks/*_spec.rb` (new) | test | - | `spec/unit/task/code_sync_status_spec.rb` (style) | partial |
| `spec/spec_helper_local.rb` (mod) | config | - | itself | n/a |
| `data/pe_versions.yaml` (mod) | config | - | itself | n/a |
| `lib/puppet/functions/peadm/supported_pe_versions.rb` (mod) | function | transform | itself | n/a |
| `spec/functions/supported_pe_versions_spec.rb` (mod) | test | - | itself | n/a |
| `plans/install.pp` (mod, line 61) | plan | request-response | itself | n/a |
| `types/adddatabasesteps.pp` (new) | type | - | `types/upgradesteps.pp` | exact |
| `plans/add_database.pp` (mod) | plan | request-response | itself | n/a |
| `spec/unit/step_names_spec.rb` (new) | test | static | `spec/unit/peadm_scenarios_spec.rb` (repo-consistency spec) | role-match |
| `plans/util/copy_file.pp` (mod) | plan | file-I/O | itself | n/a |
| `tasks/rbac_token.rb` (mod, line 69) | task | file-I/O | itself | n/a |
| `Gemfile`, `Rakefile`, `.sync.yml`, `.fixtures.yml`, `.ruby-version`, `metadata.json`, `manifests/setup/node_manager.pp:77` (mod) | config | - | themselves | n/a |
| `.github/workflows/spec.yml` (mod) | config | - | itself (Puppet 9 job, lines 91-130) | exact |
| `spec/acceptance/peadm_spec/plans/<injected_failure>.pp` (new) | test plan | event-driven | `spec/acceptance/peadm_spec/plans/upgrade_test_cluster.pp` | role-match |
| `spec/acceptance/scenarios.yaml` + `documentation/test-scenarios.md` (mod) | config/doc | - | existing U-01 entry | exact |
| `documentation/change-ledger.md`, `documentation/fix-log.md` (mod) | doc | - | Phase 0 table rows | exact |

## Pattern Assignments

### `files/failure_report.sh` (utility, transform)

**Analog:** `tasks/pe_install.sh` lines 24-42 (lift verbatim, then add redaction).

```bash
report_install_failure() {
	installer_log_dir="${PE_INSTALLER_LOG_DIR:-/var/log/puppetlabs/installer}"
	echo
	echo "=== Puppet Enterprise installer failed with exit code $1 ==="
	latest_log=$(ls -t "$installer_log_dir"/*.install.log 2>/dev/null | head -n 1)
	if [ -n "$latest_log" ]; then
		echo "--- Last 40 lines of $latest_log"
		tail -n 40 "$latest_log"
	else
		echo "--- No installer log found in $installer_log_dir"
	fi
	for unit in $(systemctl list-units 'pe-*' --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}'); do
		echo "--- systemctl status $unit"
		systemctl status "$unit" --no-pager -l -n 15 2>&1
	done
}
```

Changes: make `40`/`15` come from `${PEADM_REPORT_LOG_LINES:-40}` / `${PEADM_REPORT_UNIT_LINES:-15}`; pipe `cat "$latest_log"` through `peadm_redact` BEFORE `tail`; pipe `systemctl status` through `peadm_redact`. Use the `peadm_redact` sed block in RESEARCH.md "Redaction". File defines functions only: no traps, no fd redirects (unlike `files/task_helper.sh`, which redirects fds 6/7 and installs an EXIT trap).

### `tasks/pe_install.sh` / `tasks/pe_install.json` (task)

**Source line convention** (`tasks/pe_install.sh` line 2):
```bash
source "$(dirname $0)/../../peadm/files/task_helper.sh"
```
Add directly below: `source "$(dirname $0)/../../peadm/files/failure_report.sh"`, delete the inline function, keep both call sites (`report_install_failure "$exit_code"`, lines ~96 and ~101). Exit code passthrough stays `exit $exit_code`. Add the env seam `PE_SYSTEMD_DROPIN_DIR` (default `/etc/systemd/system/pe-puppetdb.service.d`) mirroring the existing `${PE_INSTALLER_LOG_DIR:-...}` seam, so the harness can cover `install_extra_large`.

**JSON `files` entry** (`tasks/pe_install.json` lines 21-23):
```json
"files": [
  "peadm/files/task_helper.sh"
],
```
Add `"peadm/files/failure_report.sh"` beside it.

### `tasks/wait_until_service_ready.sh` / `.json` / `functions/wait_until_service_ready.pp` (task + function)

**Current task** (whole file, 16 lines): `until [ $n -ge 20 ] ... sleep 3 ... exit 1`, no `source`, plain text output. It does NOT source `task_helper.sh`; source only `failure_report.sh` (functions-only) so the output contract stays plain text. Replace the constants with `PT_timeout`/`PT_interval` (defaults 60/3, attempts = timeout/interval) and on expiry print what was awaited, last curl result, then call the helper for failed `pe-*` units and log tail, then `exit 1`.

**JSON**: this task uses per-implementation `input_method` (lines 14-16):
```json
"implementations": [
  {"name": "wait_until_service_ready.sh", "input_method": "environment"}
]
```
Add params in the style of `tasks/pe_install.json` (`"type": "Optional[Integer[1]]", "description": ...`), add a top-level `"files": ["peadm/files/failure_report.sh"]`, and fix the wrong "timeout after 15 seconds" description.

**Function** (`functions/wait_until_service_ready.pp`): add `Integer[1] $timeout = 60,` after `TargetSpec $target,` and pass `timeout => $timeout` in the `run_task` hash. Follow the Optional/default conventions in CLAUDE.md; add a `@param` doc block if the file gains one.

### `tasks/code_manager.sh` (task)

**Analog:** `tasks/pe_install.sh` for sourcing and `exit` passthrough. `code_manager.sh` starts `#!/bin/bash` + `function main()` with `getopts ":v"`, no helper source. Per RESEARCH Pitfall 7, `curl_wrapper` swallows failures: first pin current behaviour with a harness spec (stub `curl`), then change deliberately, and add a fix-log entry. Source `failure_report.sh` with the same `$(dirname $0)/../../peadm/files/` form and add `files` to `tasks/code_manager.json`.

### `files/cert_check.rb` (utility, transform)

**Analog (partial):** `tasks/code_sync_status.rb` lines 20-30 is the only site shape to replace:
```ruby
def https_client
  client = Net::HTTP.new(Puppet.settings[:certname], 8140)
  client.use_ssl = true
  client.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
  client.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
  client.verify_mode = OpenSSL::SSL::VERIFY_PEER
  client.ca_file = Puppet.settings[:localcacert]
  client
end
```
Module shape, findings struct and OpenSSL calls: RESEARCH.md "Certificate findings". `# frozen_string_literal: true` header (new files per CLAUDE.md). No `#!/opt/puppetlabs/puppet/bin/ruby` (it is a library, not a task). RuboCop: `Style/ClassAndModuleChildren: compact`, trailing commas, `['a', 'b']` arrays, `%r{}` regexes.

### `tasks/validate_cert.rb` + `.json` (task, request-response)

**Analog:** `tasks/code_sync_status.rb` structure (lines 1-20) plus the bottom-of-file guard used by other tasks.

```ruby
#!/opt/puppetlabs/puppet/bin/ruby

# Puppet Task Name: code_sync_status
require 'net/https'
require 'uri'
require 'json'
require 'puppet'

# CodeSyncStatus task class
class CodeSyncStatus
  def initialize(params)
    @params = params
  end

  def execute!
    puts sync_status.to_json
  end
```
Use `require_relative '../files/cert_check'` (RESEARCH A2: must be confirmed on first real run; do not use `../../peadm/files/` for Ruby). Wrap execution in `unless ENV['RSPEC_UNIT_TEST_MODE']` (pattern from `tasks/get_peadm_config.rb`). Print findings as JSON on STDOUT (string keys), diagnostics on STDERR. JSON: `"files": ["peadm/files/cert_check.rb"]`, typed params with `description`, mirror `tasks/pe_install.json` layout.

### `tasks/code_sync_status.rb` (mod, the single adoption site, D-07 as narrowed)

Replace line 26 `OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))` with the checker's `load_key` (`OpenSSL::PKey.read`) via `require_relative '../files/cert_check'`. Leave the other 15 `PKey::RSA.new` sites alone; list them in the ledger as follow-ups. In `spec/unit/task/code_sync_status_spec.rb` line 37 the spec stubs `allow(OpenSSL::PKey::RSA).to receive(:new)`; change the stub to `OpenSSL::PKey` `:read` (or the checker method).

### `spec/unit/task/validate_cert_spec.rb` (test)

**Analog:** `spec/unit/task/code_sync_status_spec.rb` (lines 1-20): `require 'spec_helper'`, `require_relative '../../../tasks/<task>'`, `let(:task) { described_class.new(params) }` (plain `let`, not `subject`, per RuboCop `RSpec/SubjectStub`), `# Catches a mutation that ...` comments on each `it`. Generate real certs/keys with stdlib OpenSSL in the spec (RSA, EC, expired, empty subject, `BEGIN CRL` header) instead of stubbing.

### `spec/support/shell_task_harness.rb` + `spec/unit/shell_tasks/*_spec.rb` (test)

**No in-repo analog** (no shell-task specs exist). Use RESEARCH.md "Harness core" verbatim. Load it from `spec/spec_helper_local.rb` (which starts `# frozen_string_literal: true`, `require 'bolt_spec/plans'`, `BoltSpec::Plans.init`, sets `ENV['RSPEC_UNIT_TEST_MODE'] ||= 'TRUE'`, then SimpleCov block): add `require_relative 'support/shell_task_harness'`. Hard rule: temp module dir must be named `peadm` (tasks source `../../peadm/files/...`). Task stdout is JSON from `task_helper.sh`; parse `_output`. Planted-secret spec asserts no secret in `_output`. Raise the SimpleCov floor note only if coverage moves (the file documents the floor history in comments; add a short PE-ticket-style note when changing).

### `data/pe_versions.yaml`, `lib/puppet/functions/peadm/supported_pe_versions.rb`, `spec/functions/supported_pe_versions_spec.rb` (D-11)

**Analog:** the files themselves.

Function today (lines 8-17):
```ruby
dispatch :supported_pe_versions do
  return_type 'Struct[{oldest => String, newest => String}]'
end

def supported_pe_versions
  path = File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'data', 'pe_versions.yaml')
  data = YAML.safe_load_file(path)
  { 'oldest' => data.fetch('oldest').to_s, 'newest' => data.fetch('newest').to_s }
end
```
Add `default => String` to the Struct and `'default' => data.fetch('default').to_s`. YAML gets `default: '2025.12.1'` (quoted, same style as `oldest`/`newest`), and update the header comment. Spec (lines 6-14) currently asserts exact hash and `contain_exactly('oldest', 'newest')` plus `\d{4}\.\d+` on all values: update both (default is x.y.z so the all-values regex must be relaxed). New example: `SemanticPuppet::VersionRange.parse(">= #{oldest} <= #{newest}")` includes default. Keep `# Catches a mutation ...` style.

### `plans/install.pp` (mod, line 61)

```puppet
  Peadm::Pe_version                 $version                          = '2025.12.1',
```
becomes `= peadm::supported_pe_versions()['default'],` keeping column alignment. Regenerate `REFERENCE.md` (default text at ~line 2538).

### `types/adddatabasesteps.pp` (type) + `plans/add_database.pp`

**Analog:** `types/upgradesteps.pp` (full file):
```puppet
#
# @summary type for the different steps where the peadm::upgrade plan can be started
#
type Peadm::UpgradeSteps = Enum[
  'preparation',
  ...
  'finalize'
]
```
New type `Peadm::AddDatabaseSteps` with the six values currently inline in `plans/add_database.pp` lines 8-14 (`init-db-node, replicate-db, update-classification, update-db-settings, cleanup-db, finalize`). Plan line becomes `Optional[Peadm::AddDatabaseSteps] $begin_at_step = undef,`.

### `spec/unit/step_names_spec.rb` (test, static)

**Analog:** `spec/unit/peadm_scenarios_spec.rb` (repo-consistency spec: validates a catalog against docs). Parse `plans/{upgrade,convert,add_database}.pp` for `peadm::plan_step('...')` names and the matching `types/*steps.pp` Enum values; assert set equality per plan. Plan-step form: `peadm::plan_step('name') || { ... }` (CLAUDE.md, `plans/upgrade.pp` lines 246-495).

### `plans/util/copy_file.pp` (mod, FND-06)

Current core (lines 15-23):
```puppet
    run_task('peadm::mkdir_p_file', $replica_target,
      path    => $path,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => $source_content,
    )
```
Add optional `Optional[String] $mode = undef` (and owner/group) params; compute `$mode_real = $mode ? { undef => ($path =~ /\/secrets\//) ? { true => '0600', default => '0644' }, default => $mode }` (or an `if`). Keep `# @api private`. `tasks/mkdir_p_file.sh` already chmods before writing content, so no task change. Extend `spec/plans/util/copy_file_spec.rb` (existing, check it) with a secrets path asserting `0600`.

### `tasks/rbac_token.rb` (mod, FND-06)

Lines 68-69:
```ruby
FileUtils.mkdir_p('/root/.puppetlabs')
File.open('/root/.puppetlabs/token', 'w') { |file| file.write(token) }
```
Becomes `FileUtils.mkdir_p(dir, mode: 0o700)` and `File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600)` plus `File.chmod(0o600, path)`; add a path seam (constructor param, default `/root/.puppetlabs/token`) so `spec/unit/task/rbac_token_spec.rb` can use a tmpdir.

### Toolchain files (Gemfile, Rakefile, .sync.yml, .fixtures.yml, .ruby-version, metadata.json, node_manager.pp)

Edit exactly as in RESEARCH.md: Gemfile lines 35/38/65 (`voxpupuli-puppet-lint-plugins ~> 7.0`, helper `~> 9.0` twice); Rakefile line 6 delete `require 'puppet-syntax/tasks/puppet-syntax'`, last line `PuppetlabsSyntax.exclude_paths.concat([...])` (mirror in `.sync.yml` `extras:`); `.fixtures.yml` uses the `repo:`/`ref:` hash form already used for `provision` (lines 11-13 of the file: `repo: https://github.com/puppetlabs/provision.git` / `ref: v3.2.0`), keep expanded not flow style; `manifests/setup/node_manager.pp:77` add trailing comma. **Locked override:** Ruby floor is 3.3, not 3.2: set `.ruby-version` and every `ruby-version: '3.1'` (spec.yml lines 42 and 150, plus the 22 acceptance workflows) to `'3.3'`; update CLAUDE.md stack text that cites 3.1.0 and the `.rubocop.yml` `TargetRubyVersion` only if the planner decides (currently `2.7`; not required). Add `BOLT_GEM_VERSION` switch in the Gemfile per RESEARCH "Gemfile switch".

### `.github/workflows/spec.yml` (config)

**Analog:** the existing Puppet 9 job, lines 91-130: token mapping step at 117-121:
```yaml
FORGE_TOKEN: ${{ secrets.PUPPET_FORGE_TOKEN || secrets.PUPPET_FORGE_TOKEN_PUBLIC }}
...
echo "PUPPET_FORGE_TOKEN=$FORGE_TOKEN" >> $GITHUB_ENV
echo "BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM=forge-key:$FORGE_TOKEN" >> $GITHUB_ENV
```
(`PUPPET_GEM_VERSION: ~> 9.0` at 110, `ruby-version: '4.0'` at 126.) The comment at ~line 104 says `continue-on-error` was dropped; D-09 requires re-adding `continue-on-error: true` to that job, and a new `check_token` + `Bolt5Puppet9` job per RESEARCH "CI gating" (secrets are not usable in job `if:`).

### `spec/acceptance/peadm_spec/plans/<injected failure plan>.pp` (test plan)

**Analog:** `spec/acceptance/peadm_spec/plans/upgrade_test_cluster.pp` lines 1-40: header with typed params and a PE-ticket explanatory comment, `$t = get_targets('*')`, `wait_until_available($t)`, `parallelize($t) |$target| { ... set_var('certname', ...) }`, `$common_params`, then `$arch_params` `case $architecture`. Copy this scaffold; inject the fault with a `run_command` (e.g. write `fail('injected')` into production `site.pp`, RESEARCH Pitfall 6 option A) and a `begin_at_step` resume call. No knob in `peadm::upgrade` (D-14). Note `plans/**/*.pp` under acceptance are excluded from syntax checks in the Rakefile.

### Scenario catalog, ledger, fix-log

- `spec/acceptance/scenarios.yaml`: add a new id (last upgrade id is U-12, so U-13) modelled on U-01 (`ci_from: 2023.8.13`, `ci_to: 2025.12.1`). After editing, run `ruby spec/acceptance/scenarios.rb --format markdown --write` so `documentation/test-scenarios.md` stays in sync (guarded by `spec/unit/peadm_scenarios_spec.rb`).
- `documentation/change-ledger.md`: add a "Phase 1" section with the Phase 0 table schema: `| ID | Change | Files | Jira | Cases | Relation | Tests | Commit |`, rows like `| P0-6 | ... |`. Use "None filed" where there is no ticket; include a note that `puppetlabs-syntax` arrives transitively.
- Commit subject style from the ledger header: `(PE-47850) Read supported PE range from data file`. With placeholder keys: `(P0-1) ...`.
- `documentation/fix-log.md`: one entry per fix with complaint + reproduce/demonstrate guide (check the existing entry shape in the file before writing).

## Shared Patterns

### Shell task sourcing and metadata
**Source:** `tasks/pe_install.sh` line 2, `tasks/pe_install.json` lines 21-23
**Apply to:** all shell tasks adopting `failure_report.sh`. Source via `$(dirname $0)/../../peadm/files/...`; list the file in the task JSON `files`; `PT_*` env params; `input_method: environment`.

### Env-var seams for testability
**Source:** `tasks/pe_install.sh` `${PE_INSTALLER_LOG_DIR:-/var/log/puppetlabs/installer}`
**Apply to:** any hard-coded absolute path a harness spec needs to redirect (`PE_SYSTEMD_DROPIN_DIR`, report line counts).

### Ruby task conventions
**Source:** `tasks/code_sync_status.rb`
**Apply to:** `validate_cert.rb`, `rbac_token.rb`. Class named after task (`UpperCamelCase`), `initialize(params)`, `execute!` prints JSON, `unless ENV['RSPEC_UNIT_TEST_MODE']` guard at the bottom, errors as JSON `error` key or specific rescued classes, diagnostics on STDERR.

### Spec style
**Source:** `spec/unit/task/code_sync_status_spec.rb`
**Apply to:** all new Ruby specs. `# frozen_string_literal: true`, plain `let` for the object under test, `# Catches a mutation that ...` comments, file name matches the task file name.

### Plan failures and messages
**Source:** CLAUDE.md Error Handling; `plans/convert.pp` heredoc `fail_plan` messages
**Apply to:** any new plan-side validation: `fail_plan(@("EOL"/L) ...)`, `out::message` for progress, `_catch_errors => true` where failure is expected.

### Types in `types/`
**Source:** `types/upgradesteps.pp`
**Apply to:** `Peadm::AddDatabaseSteps`; new constraints go in `types/`, not plan bodies.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `spec/support/shell_task_harness.rb` | test helper | file-I/O | No shell-task specs or `spec/support/` exist; use RESEARCH.md "Harness core" |
| `spec/unit/shell_tasks/*_spec.rb` | test | - | Same; Ruby spec style only is borrowed from `spec/unit/task/*` |
| Bolt 5 CI job (`check_token`, `Bolt5Puppet9`) | config | - | No existing token-gated job; use RESEARCH.md "CI gating for the Bolt 5 lane" |

## Metadata

**Analog search scope:** `tasks/`, `files/`, `functions/`, `lib/puppet/functions/peadm/`, `plans/`, `types/`, `spec/unit`, `spec/functions`, `spec/acceptance/peadm_spec/plans`, `.github/workflows/spec.yml`, root toolchain files, `documentation/`
**Files scanned:** about 25 read in full or in part
**Pattern extraction date:** 2026-11-10

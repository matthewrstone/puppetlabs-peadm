# Phase 1: Foundations, Diagnostics and Test Baseline - Research

**Researched:** 2026-11-10
**Domain:** Bolt/Puppet module test toolchain, shell and Ruby task hardening, CI lanes, acceptance runs for a Puppet Enterprise lifecycle module
**Confidence:** MEDIUM-HIGH (toolchain bump, harness, redaction and cert checks were run in this session; Puppet 9 / Bolt 5 behaviour and PE 2026 on-node details could not be run without a Puppet Core token or a PE node)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Failure diagnostics and redaction (FND-01, FND-05)**
- **D-01:** The failure report (log tail, failed `pe-*` units, exit code) becomes a shared shell helper in `files/task_helper.sh` (or a sibling file sourced the same way). `tasks/pe_install.sh` is refactored onto it, reusing the P0-6 logic.
- **D-02:** Secrets are removed by pattern redaction inside the helper (e.g. `password=`, tokens, `BEGIN ... PRIVATE KEY` blocks, `console_admin_password`, signed-URL query strings). A spec plants fake secrets and asserts none appear in task output or plan output.
- **D-03:** Default output is the last 40 log lines and 15 lines per failed unit, overridable by a task parameter or env var.
- **D-04:** In Phase 1 the helper is adopted by the installer and service-wrapping shell tasks (`pe_install.sh` plus tasks that start, stop or wait on `pe-*` services, such as `wait_until_service_ready.sh` and `code_manager.sh`), not all 19 shell tasks.

**Shared certificate helper (FND-03)**
- **D-05:** One Ruby module (stdlib OpenSSL only, under `files/` or `lib/`) does the checks: PEM and DER, RSA and EC keys, chains, expiry, empty subject, CRL. A thin task (`peadm::validate_cert` or similar) wraps it for plans; Ruby tasks require the module directly.
- **D-06:** The checker returns structured findings (severity error/warn, code, message) and the caller decides to fail or warn. This shape is reused as BLOCK/WARN results in Phase 2 preflight and by the Phase 5 CD4PE/SCM plans.
- **D-07:** Adoption in Phase 1 is limited to replacing the RSA-only `PKey.read` site (TST-03). Other cert tasks (`cert_data`, `cert_valid_status`, `sign_csr`, `modify_certificate`) migrate when their phases touch them.

**Test toolchain and CI lanes (TST-01, 02, 03, 05, 06)**
- **D-08:** Bump `puppetlabs_spec_helper` to 9, `rspec-puppet` to 5 and pin fixtures to tags in one change on the existing Ruby 3.1 / Puppet 8 lane, fixing fallout in the same plan. Lint baseline must not regress.
- **D-09:** The Puppet 9 lane and the credentialed Bolt 5 lane are informational and non-blocking (continue-on-error). Puppet 8 stays the merge gate. The Bolt 5 lane runs only when the Puppet Core token secret is present.
- **D-10:** The shell-task harness is an RSpec helper that builds a temp dir of stub executables (`systemctl`, `tar`, `puppet-enterprise-installer`, ...), prepends it to PATH, runs the task with `PT_*` env vars and asserts on stdout and exit code. It runs inside `rake spec` and turns the hand-run P0-4 and P0-6 checks into specs.
- **D-11:** `data/pe_versions.yaml` gains a `default` key read via `peadm::supported_pe_versions`; `plans/install.pp` reads it instead of a hardcoded version. A spec asserts `default` lies within `oldest..newest`.

**First acceptance slice (TST-04)**
- **D-12:** Topology is a standard architecture, one n to n+1 upgrade on a current pair of PE lines. Large, XL and DR are left to Phases 2 and 4.
- **D-13:** The slice is run manually on the user's own VMs and the results are recorded; no CI wiring in Phase 1. Nightly CI for the newest PE stays in Phase 2 (UPG-07).
- **D-14:** The injected failure for the resume test lives in a test-only plan under `spec/acceptance/peadm_spec/plans/`. No test-only knob is added to `peadm::upgrade`.

### Claude's Discretion
- Environment detection for non-`production` PE environments (FND-02), validation mechanism for `begin_at_step` (FND-04), per-path file modes and the `/tmp/pe.conf` cleanup (FND-06), and the overridable readiness deadline parameter naming and defaults (FND-07). Requirements and codebase maps are clear enough; follow existing conventions (types in `types/`, `fail_plan` heredoc messages).
- Exact scenario IDs and exact PE version pair for the acceptance run; pick from `spec/acceptance/scenarios.yaml` (I-01, U-01 plus a new injected-failure scenario).

### Deferred Ideas (OUT OF SCOPE)
None - discussion stayed within phase scope. (Wider adoption of the cert helper and failure report is intentionally left to Phases 2 and 5.)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FND-01 | Underlying cause (log tail, failed units, exit code, sanitized) in Bolt output for installer / service-wrapping task failures | Harness prototype proved `pe_install.sh` already prints a report (P0-6) but it leaks planted secrets today; shared `files/failure_report.sh` design, redact-then-tail rule, sed patterns tested (Pattern 2, Code Examples) |
| FND-02 | Plans work against non-`production` PE environments (install, backup, restore, migrate) | Concrete defects found in code: 4 `puppet-backup restore` calls without `--pe-environment`, hard-coded `environments/production` stub in install, `configure` never passes `node_group_environment` (see Architecture Pattern 5) |
| FND-03 | One shared certificate, CRL and key validation | Stdlib OpenSSL behaviour probed on Ruby 3.2 / OpenSSL 3.0 for PEM, DER, RSA, EC (PKCS8 and SEC1), Ed25519, encrypted keys, chains, expiry, empty subject, CRL header (Pattern 3, Code Examples) |
| FND-04 | Invalid `begin_at_step` fails immediately | Typed plans already reject unknown names; real gap is type/`plan_step` drift (the P0-1 class) and one remote call before validation. Static drift spec plus a new type for `add_database` (Pattern 6) |
| FND-05 | Secrets never in plan output or diagnostics, proven by a spec with planted secrets | Redaction prototype; plan-output capture technique proven (`publish_event` wrap); harness asserts on task `_output` (Code Examples) |
| FND-06 | Restrictive modes: `copy_file` 0644, `/tmp/pe.conf`, token file | Exact sites located (`plans/util/copy_file.pp:19`, `plans/subplans/install.pp` pe.conf upload, `tasks/rbac_token.rb:69`); `mkdir_p_file` already applies mode before writing content |
| FND-07 | Readiness waits with overridable deadlines incl. the CA timeout | `wait_until_service_ready.sh` is a fixed 20 x 3 s loop that exits 1 with no message; add `timeout`/`interval` task params and a function argument (Pattern 7) |
| TST-01 | Specs on `puppetlabs_spec_helper` 9, `rspec-puppet` 5, fixtures pinned to tags | Bump executed in a scratch copy: 534 examples, 0 failures on `rspec`, `rake parallel_spec` and `rake spec:simplecov`; exact Gemfile, Rakefile, `.sync.yml`, lint and Ruby-floor changes listed |
| TST-02 | Know whether peadm runs unchanged on Bolt 5.2 / Puppet Core 9; CI lane for Puppet 9 and credentialed lane for Bolt 5 | Bolt 5.2.1 gem is documented as installable from the puppetcore source; Gemfile switch tested; Puppet 9 lane already exists in `spec.yml`; metadata widening adds a blocking Puppet 9 job to the shared `ci.yml` (see Pitfall 4) |
| TST-03 | PE 2026.0 / Puppet 9 fixes: `bootstrap.cfg`, RSA-only parsing, `metadata.json` range | 16 `PKey::RSA.new` sites (none use `PKey.read`); `bootstrap.cfg` CA-backend detection is duplicated in `backup.pp` and `restore.pp` and needs an on-node check; metadata range edit |
| TST-04 | First acceptance slice (install, n to n+1 upgrade, injected failure and resume) | Existing acceptance plans and `pedev_inventory.yaml` pattern; injected-failure placement must respect the known tarball-deleted-before-installer defect (Pitfall 6) |
| TST-05 | Stub-PATH harness for shell tasks | Prototype ran against `pe_install.sh`; layout, fake tarball shape and testability seams documented (Pattern 1) |
| TST-06 | Default PE version derived from `data/pe_versions.yaml` | `plans/install.pp:61` hard-codes `'2025.12.1'`; function and spec design (Pattern 4); `REFERENCE.md` default text needs regenerating |
| TRC-01 | Every change in `documentation/change-ledger.md` with ticket | New "Phase 1" ledger section; commit-subject convention needs ticket keys (Open Question 6) |
| TRC-02 | Every fix in `documentation/fix-log.md` with reproduce/demonstrate | Recipe in fix-log still works with tag-pinned fixtures; entries needed per fix, with a planted-secret before/after available from the prototype |
| TRC-03 | Jira tickets for P0-1, P0-2, P0-3 | Manual action; no Atlassian tooling in this environment; ledger "Tickets that need filing" list is the source text |
</phase_requirements>

## Summary

The phase is mostly well-understood shared-library work, but four findings change the plan. (1) **`puppetlabs_spec_helper` 9 requires Ruby >= 3.2**, so D-08's "existing Ruby 3.1 lane" cannot hold: the static-check job, the coverage job, `.ruby-version` and 22 acceptance workflows pin Ruby 3.1 and will fail `bundle install` after the bump. The Puppet 8 spec matrix is already Ruby 3.2 (litmus matrix table). (2) The bump itself is small and was proven: in a scratch copy, helper 9.0.0 + rspec-puppet 5.0.0 + `voxpupuli-puppet-lint-plugins ~> 7.0` + a three-line Rakefile fix + one trailing comma gave 534 examples, 0 failures on plain `rspec`, `rake parallel_spec` and `rake spec:simplecov` (83.0% line coverage against the 82 floor), with all fixtures pinned to tags. Do **not** also bump `rspec-puppet-facts` to 6.x: it depends on `openfact` (the OpenVox Facter fork) and resolves side by side with `facter`. (3) The earlier research claim that Bolt 5 is not installable as a gem is contradicted by the current Bolt install page, which documents `gem 'bolt', '~> 5.2.1'` from `https://rubygems-puppetcore.puppet.com` with a Puppet Core key; this could not be confirmed here (401 without a token), so the Bolt 5 lane is the spike. (4) Several requirement texts are less literal than the code: there is no `PKey.read` site (there are 16 `OpenSSL::PKey::RSA.new` sites), typed plans already reject a bad `begin_at_step`, and `code_manager.sh` swallows every curl failure.

The stub-PATH harness (D-10) was prototyped against `pe_install.sh` and works with real `tar`, a fake installer inside a real tarball, and a stub `systemctl`. It also demonstrated the FND-05 problem: today's P0-6 failure report prints `password=hunter2` verbatim from the installer log. The sed redaction prototype removes planted passwords, URL userinfo, signed-URL signatures, auth headers and PEM private-key blocks; redaction must run over the whole log file **before** `tail` so a key block cut by the window cannot leak.

**Primary recommendation:** Do the toolchain bump first as its own plan (Ruby floor 3.2, helper 9, plugins 7, Rakefile `PuppetlabsSyntax`, fixture tags, lanes), then the harness, then the failure helper and the other shared helpers on top of it; leave the acceptance run and ledger/Jira work last.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Failure report and redaction | Target node (shell task) | Bolt controller (plan messages) | Logs and `systemctl` live on the node; Bolt prints the task's `_output` unredacted, so redaction must happen before output leaves the node |
| Certificate / CRL / key validation | Target node (Ruby task using PE Ruby) | Bolt controller (plan decides fail or warn) | Key and cert files are on the node; findings are returned as data, the plan chooses severity handling |
| Non-`production` environment resolution | Bolt controller (plan/function reads pe.conf) | Target node (`puppet-backup --pe-environment`) | `peadm::get_node_group_environment` already runs plan-side; the PE CLI flag is node-side |
| `begin_at_step` validation | Bolt controller (plan parameter types, spec) | CI (drift spec) | Types are enforced by the Puppet language; drift is a repo-consistency problem caught in specs |
| File modes for secret copies, `/tmp/pe.conf`, token | Target node (`mkdir_p_file`, `rbac_token.rb`) | Bolt controller (passes mode) | Mode is applied where the file is written |
| Readiness waits with deadlines | Target node (polling loop) | Bolt controller (passes deadline) | The task polls localhost status API; plan supplies the deadline |
| Shell-task test harness | CI / dev workstation | - | Runs under `rake spec`; no PE needed |
| Puppet 9 / Bolt 5 signal lanes | CI (GitHub Actions) | - | Gemfile env switches choose gem source |
| Acceptance slice | Operator's own VMs (manual) | Bolt controller plans in `spec/acceptance/peadm_spec/plans/` | D-13: no CI wiring in Phase 1 |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| puppetlabs_spec_helper | `~> 9.0` (9.0.0, 2026-08-20) | `rake spec`, fixtures, `parallel_spec` | Locked by D-08. Needs Ruby >= 3.2, `puppet-lint ~> 5.0`, `rspec-puppet ~> 5.0`, replaces `puppet-syntax` with `puppetlabs-syntax ~> 7.2` [VERIFIED: rubygems.org API v2, queried this session] |
| rspec-puppet | `~> 5.0` (resolved 5.0.0) | Catalog, function, plan specs | Locked by D-08; helper 9 pins `~> 5.0`, so 6.0.0 (exists) cannot be used with it [VERIFIED: rubygems.org API] |
| voxpupuli-puppet-lint-plugins | `~> 7.0` (7.0.0) | Lint checks | Helper 9 requires `puppet-lint ~> 5.0`; plugins 5.x and 6.x pin `puppet-lint ~> 4.0`, so the current `~> 5.0` makes the Gemfile unresolvable [VERIFIED: bundler error reproduced in scratch] |
| Bolt (gem) | 4.0.0 (public, default lanes); `~> 5.2.1` on the credentialed lane | `BoltSpec::Plans`, plan runs | Last public gem is 4.0.0; 5.2.1 documented from puppetcore [VERIFIED: rubygems.org for 4.0.0; CITED: help.puppet.com/bolt/current/topics/bolt_installing.htm for 5.2.1] |
| Ruby | 3.2 minimum (3.3 recommended for dev); 4.0 on the Puppet 9 lane | Test runtime | Helper 9 and plugins 7 require >= 3.2 [VERIFIED: rubygems.org API]. Local machine is Ruby 3.2.3 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| rspec-puppet-facts / facterdb | keep `~> 2.0` / `~> 1.18` | OS fact sets | Do NOT bump to 6.x / 4.x now: rspec-puppet-facts 6.3.1 depends on `openfact >= 5, < 7` and both `facter 4.10.0` and `openfact 5.7.3` resolved together in a scratch lock [VERIFIED: bundle lock run this session]. Specs here do not use `on_supported_os` (grep), so there is no benefit in Phase 1 |
| parallel_tests | keep `= 3.12.1` | `rake parallel_spec` | Worked on Ruby 3.2 with the bumped set (534 examples, 2m13s) [VERIFIED: run this session] |
| puppetlabs-syntax | 7.2.1 (transitive) | Replaces `puppet-syntax` for `rake syntax` | Module constant is `PuppetlabsSyntax`, not `PuppetSyntax` [VERIFIED: gem source `module PuppetlabsSyntax`] |
| puppet_litmus | `~> 2.8` (Gemfile has `~> 2.0`) | Acceptance provisioning | Requires `bolt >= 4.0, < 6.0`, Ruby >= 3.1 [VERIFIED: rubygems.org API] |
| OpenSSL (Ruby stdlib) | Ruby's bundled | Certificate helper | No new gem (D-05) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Single Gemfile for Ruby 3.1 and 3.2+ | puppet_agent module's pattern: helper `~> 8.0` below Ruby 3.2, `~> 9.0` from 3.2 [VERIFIED: `spec/fixtures/modules/puppet_agent/Gemfile`] | Keeps a 3.1 lane alive but needs lint ~> 4 and plugins 5 on that lane too; Ruby 3.1 is end-of-life [ASSUMED], so prefer dropping 3.1 |
| Bash sed redaction | Ruby redactor called from tasks | Shell tasks have no Ruby guarantee on every node; sed is on every target. Keep sed for the shell helper |
| Bats / shunit2 for shell tests | RSpec harness (D-10, locked) | Locked decision; no new tool, runs inside `rake spec` |

**Installation (Gemfile changes, both `development` and `release_prep` groups list the helper):**
```ruby
gem "puppetlabs_spec_helper", '~> 9.0', require: false   # lines 38 and 65 of the current Gemfile
gem "voxpupuli-puppet-lint-plugins", '~> 7.0', require: false   # line 35
```
```bash
bundle install && bundle exec rake spec_prep && bundle exec rake parallel_spec
```

**Version verification:** `puppetlabs_spec_helper` 9.0.0 (2026-08-20), `rspec-puppet` 5.0.0 (2024-09-06; 6.0.0 exists, 2026-09-21), `voxpupuli-puppet-lint-plugins` 7.0.0 (2025-09-27), `bolt` 4.0.0 (2024-12-03), `puppet_litmus` 2.8.1 (2026-09-23) [VERIFIED: https://rubygems.org/api/v1/versions/<gem>.json, 2026-11-10].

## Package Legitimacy Audit

The `gsd-tools package-legitimacy check` seam accepts only `npm|pypi|crates` (it printed `Usage: ... --ecosystem <npm|pypi|crates>` for `rubygems`), so these were checked against the RubyGems API directly. All are existing project dependencies or major-version bumps of them, except `puppetlabs-syntax`, which is new and transitive.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| puppetlabs_spec_helper | RubyGems | 14 yrs (2012-06) | 17.6M | github.com/puppetlabs/puppetlabs_spec_helper | OK (existing dep, bump) | Approved |
| rspec-puppet | RubyGems | 15 yrs (2011-07) | 17.5M | github.com/puppetlabs/rspec-puppet | OK (existing dep, bump) | Approved |
| voxpupuli-puppet-lint-plugins | RubyGems | 5 yrs (2021-08) | 1.4M | github.com/voxpupuli/voxpupuli-puppet-lint-plugins | OK (existing dep, bump) | Approved |
| puppetlabs-syntax | RubyGems | 2.5 months (single release 7.2.1, 2026-08-20) | 36K | github.com/puppetlabs/puppetlabs-syntax; owner handle `ia-content` | SUS by age only: pulled in by the official helper 9.0.0, not installed directly | Approved as transitive; do not add to the Gemfile; planner notes it in the PR description |
| bolt (5.2.1 from puppetcore) | rubygems-puppetcore.puppet.com | n/a | n/a | github.com/puppetlabs/bolt | Not checkable without a token | Credentialed lane only; documented install path [CITED: help.puppet.com/bolt/current/topics/bolt_installing.htm] |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** `puppetlabs-syntax` (age only; transitive of the official helper). No `checkpoint:human-verify` is needed for a transitive of a package that is already trusted, but record it in the change ledger entry.

*No postinstall scripts apply (RubyGems; native extensions built for existing deps during `bundle install`).*

## Architecture Patterns

### System Architecture Diagram

```
                         Phase 1 data flow

 maintainer / CI
   |
   |  bundle exec rake parallel_spec   (Ruby >= 3.2, helper 9, rspec-puppet 5, tag-pinned fixtures)
   v
 +-------------------------------+      +--------------------------------------+
 | spec/plans, spec/functions,   |      | spec/unit/shell_tasks/*_spec.rb      |
 | spec/unit/task (BoltSpec,     |      |  ShellTaskHarness                    |
 |  rspec-puppet)                |      |   temp modules/peadm/{tasks,files}   |
 +-------------------------------+      |   stubs/ (systemctl, curl, sleep..)  |
        ^                               |   PATH=stubs:$PATH, PT_* env         |
        | asserts out::message and      |   run task, parse JSON _output       |
        | run_task params               +------------------+-------------------+
        |                                                  |
 operator: bolt plan run peadm::install / upgrade / backup  |  executes
        |                                                   v
        v                                     +--------------------------------+
 +-------------+  run_task   +--------------->| target node: shell task        |
 | Bolt plan   |------------>| pe_install.sh  | source files/task_helper.sh    |
 | (controller)|             | wait_until_... | source files/failure_report.sh |
 |             |<------------| code_manager.sh|   peadm_redact | tail -n N     |
 | decides     | JSON result +----------------+   systemctl failed pe-* units  |
 | fail / warn | (_output has redacted report)  |   exit code preserved          |
 +------+------+                                +--------------------------------+
        |  run_task peadm::validate_cert         +--------------------------------+
        +--------------------------------------->| target node: Ruby task         |
                                                 |  require_relative '../files/   |
                                                 |   cert_check' -> findings      |
                                                 |  [{severity, code, message}]   |
                                                 +--------------------------------+

 CI lanes:  Puppet 8 / Ruby 3.2 (gate)  |  Puppet 9 / Ruby 4.0 (continue-on-error)  |
            Bolt 5.2 + Puppet 9 (only when token present, continue-on-error)
 Manual:    acceptance slice on operator VMs (install -> upgrade -> injected failure -> resume)
```

### Recommended Project Structure
```
files/
├── task_helper.sh            # existing; leave as is (side effects on source: fd redirect, EXIT trap)
├── failure_report.sh         # NEW: functions only (peadm_redact, peadm_failure_report); no traps, no redirects
└── cert_check.rb             # NEW: PeadmCertCheck module (stdlib OpenSSL only)
tasks/
├── validate_cert.rb / .json  # NEW thin wrapper: files: ["peadm/files/cert_check.rb"]
└── wait_until_service_ready.json   # gains timeout/interval params and "files"
types/
└── adddatabasesteps.pp       # NEW: replaces the inline Enum in plans/add_database.pp
spec/
├── support/shell_task_harness.rb   # NEW (loaded from spec_helper_local.rb)
├── unit/shell_tasks/*_spec.rb      # NEW
├── unit/task/validate_cert_spec.rb # NEW
└── unit/step_names_spec.rb         # NEW: plan_step names vs begin_at_step types
```

### Pattern 1: Stub-PATH shell-task harness (TST-05, D-10)
**What:** Build `<tmp>/modules/peadm/{tasks,files}`, copy the task and `task_helper.sh` into it, put stub executables in `<tmp>/stubs`, run with `PATH=<tmp>/stubs:$PATH` and `PT_*` env, parse the JSON on stdout, assert on `_output` and exit status.
**When to use:** Every shell task spec (pe_install, verify_tarball, read_file, mkdir_p_file, wait_until_service_ready, code_manager).
**Why the copy:** tasks source `"$(dirname $0)/../../peadm/files/task_helper.sh"` (`tasks/pe_install.sh` line 2). That path only resolves when the module directory is literally named `peadm`. A `spec/fixtures/modules/peadm` symlink does not help: the kernel resolves `..` physically after following the symlink, so `.../peadm/tasks/../../peadm/files` lands outside the repo. An existing spec documents the same trap for Ruby (`spec/unit/task/get_psql_version_spec.rb` header comment). Copying into a real `modules/peadm/` temp tree works [VERIFIED: prototype ran].
**Rules learned from the prototype:**
- Use real `tar` and a real tarball. The fake tarball must list the installer as the **first entry as a file path**, built with `tar -C src -czf out.tar.gz puppet-enterprise-X/puppet-enterprise-installer`. If `tar` also records the directory entry, `pedir=$(tar -tf ... | head -n 1 | xargs dirname)` yields `.` and the task exits 1 with "installer not found" [VERIFIED: failed once, fixed].
- Stub `systemctl` (and `curl`, `sleep`, `localectl` where used). Stub `sleep` to a no-op so `wait_until_service_ready` specs take milliseconds.
- Task stdout is **JSON**, because `task_helper.sh` redirects fds 1 and 2 to a tempfile and prints `{"_output": "..."}` on exit. Parse it; do not regex raw stdout.
- Exit status is passed through (`exit "$exit_code"`), so `status.exitstatus` is the task's exit code.
- `pe_install.sh` writes `/etc/systemd/system/pe-puppetdb.service.d/10-shortcircuit.conf` by absolute path when `install_extra_large=true`. A harness run as non-root cannot cover that branch. Add an env seam (for example `PE_SYSTEMD_DROPIN_DIR`, default the real path) in the same change that lifts the helper out, mirroring the existing `PE_INSTALLER_LOG_DIR` seam.
- `file` and `tar` exist on `ubuntu-latest` runners and locally [VERIFIED: `command -v` locally]; stub `file` if a spec needs to force the gzip branch.
**Example:** see Code Examples, "Harness core".

### Pattern 2: Shared failure report with redact-then-tail (FND-01, FND-05, D-01 to D-04)
**What:** A sibling file `files/failure_report.sh` that defines functions only. Recommendation over editing `task_helper.sh`: sourcing `task_helper.sh` has global side effects (redirects fds 6/7, installs an EXIT trap, turns every `PT_*` variable into a plain variable). `wait_until_service_ready.sh` and `code_manager.sh` do **not** source it today and print plain text; making them source it would change their output contract. D-01 explicitly allows "a sibling file sourced the same way".
**Behaviour:**
1. Locate the newest log (`ls -t $dir/*.install.log`, as P0-6 does) and for service-wait failures the service log.
2. `sed` redact the **whole file**, then `tail -n ${PEADM_REPORT_LOG_LINES:-40}`. Redacting after `tail` can leak the body of a private-key block whose `BEGIN` line fell outside the window.
3. For each failed `pe-*` unit: `systemctl status "$unit" --no-pager -l -n ${PEADM_REPORT_UNIT_LINES:-15}` piped through redaction (`systemctl status` shows `ExecStart` command lines, which can carry `--password=`).
4. Print the exit code and keep it as the task's exit code.
5. Make the line counts overridable by env var (`PEADM_REPORT_LOG_LINES`, `PEADM_REPORT_UNIT_LINES`) and by an optional task parameter that maps to the env var; D-03 allows either.
**Adoption (D-04):** `pe_install.sh`; `wait_until_service_ready.sh` (on timeout print the last HTTP status/body, failed `pe-*` units and the service log tail, then exit 1); `code_manager.sh` (see Pitfall 7). Each task's `.json` needs `"files": ["peadm/files/failure_report.sh"]`, and the source line follows the existing convention `source "$(dirname $0)/../../peadm/files/failure_report.sh"`. Note `pe_install.json` already lists `peadm/files/task_helper.sh`; add the new file next to it.

### Pattern 3: Shared certificate checker with structured findings (FND-03, D-05 to D-07)
**What:** `files/cert_check.rb` defines `PeadmCertCheck` (stdlib `openssl`, `json`, `time` only). Every check returns findings `{ 'severity' => 'error'|'warn', 'code' => 'cert_expired', 'message' => '...' }`; the caller decides. Shape matches the BLOCK/WARN contract Phase 2 will use (D-06).
**Load path:** `require_relative '../files/cert_check'` from `tasks/validate_cert.rb`. Bolt installs shared files as `<installdir>/peadm/files/...` beside `<installdir>/peadm/tasks/...`, so the same relative path works in the repo and on a node (the module sits at the same depth in both layouts) [ASSUMED: Bolt `_installdir` layout; confirm in the first unit run on a real task]. Do not use the cross-module form `../../peadm/files/...` for Ruby; it fails in a checkout for the reason in Pattern 1.
**Probed behaviour (Ruby 3.2.3, openssl gem 3.1.0, OpenSSL 3.0.13)** [VERIFIED: probe script run this session]:
- `OpenSSL::PKey.read` loads RSA, EC (PKCS8 `BEGIN PRIVATE KEY` and SEC1 `BEGIN EC PRIVATE KEY`) and Ed25519, and DER of each.
- `OpenSSL::PKey::RSA.new(ec_pem)` raises `OpenSSL::PKey::RSAError: incorrect pkey type: id-ecPublicKey` (the current RSA-only failure).
- Ed25519 returns a generic `OpenSSL::PKey::PKey` with no `private?` method. Determine "has private part" with `key.private_to_der` inside `begin/rescue`, or by class (`RSA#private?`, `EC#private_key?`).
- Encrypted PEM without a passphrase raises `OpenSSL::PKey::PKeyError: Could not parse PKey: pkcs12 cipherfinal error`.
- `OpenSSL::X509::Certificate.new` and `OpenSSL::X509::CRL.new` accept both PEM and DER.
- A CRL with the header `BEGIN CRL` is rejected: `OpenSSL::X509::CRLError: PEM_read_bio_X509_CRL: no start line`; only `BEGIN X509 CRL` parses. A certificate fed to the CRL parser fails the same way. The checker should detect a wrong header and say so (CASE-013 class).
- Empty subject: `cert.subject.to_a.empty?` is true and `to_s` is `""`.
- Expiry through a store: `store.verify(cert)` returns false with `store.error_string == "certificate has expired"`. Check `not_after` directly as well, so the warn window (for example 30 days) is available.
- `cert.check_private_key(key)` works for EC and RSA and returns false for a mismatch.
- A bundle file splits with `scan(%r{-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----}m)`; build the chain with `store.verify(leaf)` after adding the intermediates/root.
- Ruby 4.0 / OpenSSL 3.5 (Puppet 9) could not be run here; keep the unit spec free of Ruby-version-specific behaviour and let the Puppet 9 lane confirm.
**Adoption (D-07):** replace the RSA-only call at the named site and add the checker task. See Open Question 1 about scope: there are 16 sites.

### Pattern 4: `default` PE version from data (TST-06, D-11)
Add `default: '2025.12.1'` to `data/pe_versions.yaml`; extend `peadm::supported_pe_versions` to return `Struct[{oldest => String, newest => String, default => String}]` and update its return-type and spec (`spec/functions/supported_pe_versions_spec.rb` asserts `contain_exactly('oldest', 'newest')` and the exact hash today, so it must change). In `plans/install.pp:61` the default becomes an expression, `Peadm::Pe_version $version = peadm::supported_pe_versions()['default']`; plan defaults may call functions (`peadm::get_node_group_environment($primary_host)` is already used that way). Range check in the spec must use the same semantics as the plan: `SemanticPuppet::VersionRange.parse(">= 2019.7 <= 2026.0")` includes `2026.0.1` and excludes `2026.1.0` [VERIFIED: run in this session]. The value must also match `Peadm::Pe_version` (`^\d+\.\d+\.\d+(-.+)?$`), so a full x.y.z. Regenerate `REFERENCE.md` (it records `Default value: '2025.12.1'` at line 2538).

### Pattern 5: Non-`production` environment (FND-02, discretion)
Concrete defects found by reading the code (the tickets themselves, PE-39789 Closed and PE-46598 In Review, carry no detail in `peadm.csv`):
1. `plans/restore.pp` calls `puppet-backup restore` four times (lines 152, 213, 224, 235) with no `--pe-environment`; PE documents `--pe-environment` as "Specify an environment to restore. The default value is `production`." [CITED: help.puppet.com/pe/current/topics/restore_pe_infrastructure.htm]. Same for `plans/restore_ca.pp:10`. `puppet-backup create` options for environment were not found in the docs; verify with `puppet-backup create --help` on a node.
2. `plans/subplans/install.pp` (around lines 490-497) always stubs `/etc/puppetlabs/code-staging/environments/production/manifests/site.pp` and commits it, regardless of the configured environment.
3. `plans/subplans/configure.pp` (lines 108-118) applies `peadm::setup::node_manager` without `node_group_environment`, so its default `'production'` (`manifests/setup/node_manager.pp:51`) wins on install even if `pe_conf_data` sets `pe_install::install::classification::pe_node_group_environment`.
4. `plans/install.pp`, `backup.pp`, `restore.pp`, `migrate.pp` have no `node_group_environment` parameter and do not call `peadm::get_node_group_environment`, which exists and reads both pe.conf keys.
**Recommendation:** resolve the environment once. For install, derive it from `pe_conf_data` (same two keys, same equality rule as `get_node_group_environment`) and pass it to the stub path and to `node_manager`. For backup/restore/migrate, read it with `peadm::get_node_group_environment($primary)` (or from the backed-up `peadm_config.json` when the primary is gone) and pass `--pe-environment`. Add specs that run each plan with `dev` and assert the environment reaches the command and the `node_group_environment` param. This is [ASSUMED] to clear the tickets; the acceptance scenario is I-02 (`spec/acceptance/scenarios.yaml`: "install with node_group_environment=dev and no production environment on disk") and M-02.

### Pattern 6: `begin_at_step` validation (FND-04, discretion)
Current behaviour [VERIFIED: probe spec run this session]: `peadm::upgrade` with `begin_at_step=bogus` fails with `parameter 'begin_at_step' expects a match for Peadm::UpgradeSteps = Enum['finalize', 'preparation', ...], got 'bogus'`; `peadm::convert` likewise names `Peadm::ConvertSteps`. So unknown names are already rejected **when a typed parameter exists**. What still goes wrong:
- The type and the `plan_step('name')` calls can drift (this is exactly P0-1: type had `modify-primary-certs`, the plan used another name, every step was skipped). Nothing in CI checks it.
- `plans/add_database.pp` declares an inline `Enum` instead of a type in `types/`.
- The plan parameter default `String[1] $node_group_environment = peadm::get_node_group_environment($primary_host)` is evaluated before the type error is raised, so an invalid step name first triggers a remote `run_task('peadm::read_file', ...)` on the primary (the probe failed with "Unexpected call to run_task(peadm::read_file ...)" until stubbed). That is wasteful, not harmful.
**Recommendation:** (a) a static spec that parses `plans/*.pp` for `peadm::plan_step('...')` calls and the matching `Peadm::*Steps` type and asserts set equality per plan (upgrade, convert, add_database); (b) move the add_database enum to `types/adddatabasesteps.pp` as `Peadm::AddDatabaseSteps`; (c) keep the type error as the operator message (it lists the valid names) and, if the planner wants a friendlier message, add a `fail_plan` heredoc only where a plan has no typed parameter. Do not try to detect "no step matched" inside `plan_step` itself: it cannot know the full step list.

### Pattern 7: Overridable readiness deadlines (FND-07, discretion)
`tasks/wait_until_service_ready.sh` loops 20 times with `sleep 3` (60 s) and `exit 1` with no output; `tasks/wait_until_service_ready.json` describes it as "timeout after 15 seconds", which is wrong. Add task parameters `timeout` (`Optional[Integer[1]]`, seconds, default 60 to preserve today's behaviour) and `interval` (`Optional[Integer[1]]`, default 3), compute attempts as `timeout / interval`, and on expiry print what was awaited, the last HTTP result and the redacted log tail via the Pattern 2 helper. Extend `peadm::wait_until_service_ready(String $service, TargetSpec $target, Integer[1] $timeout = 60)` and pass it through. The task's `service` enum already includes `ca`, so "the CA timeout" in FND-07 is read here as the `ca` service wait (and the 60 s wait in `plans/add_replica.pp`, comment at line 140) [ASSUMED]. Expose the value on the plans that wait (`add_replica`, `upgrade`, `restore`, `convert`, `install`) with one optional parameter each, and add a forwarding spec per plan (project convention for new parameters). `tasks/puppet_runonce.sh` already has `PT_in_progress_timeout`; leave it.

### Pattern 8: Secret-file modes and `/tmp/pe.conf` (FND-06, discretion)
- `plans/util/copy_file.pp:19` hard-codes `mode => '0644'` and `owner/group => 'root'` for every path, including the three `.../secrets/keys.json` files copied by `plans/subplans/configure.pp` and `plans/add_replica.pp`. Add optional `mode`, `owner`, `group` parameters to `copy_file`; default to `0600` for any path matching `/secrets/`; leave `0644` for non-secret files (`hiera.yaml`, `ad_ca_chain.pem`). Preserve the source file's owner and mode if a stat is available: extend `peadm::read_file` to also return `mode`, `owner`, `group` (it already returns JSON with `content`).
- `tasks/mkdir_p_file.sh` already applies `chown`/`chmod` **before** writing content (it `touch`es, sets owner/group/mode, then `cat >`), so passing `mode => '0600'` is sufficient and leaves no world-readable window [VERIFIED: read of the script].
- `/tmp/pe.conf`: uploaded by `peadm::file_content_upload` (Bolt `upload_file` from a `Tempfile`); nothing removes it. Add a `chmod 0600` run right after the upload and `rm -f /tmp/pe.conf` after the last `peadm::pe_install` that consumes it, or at plan end. Resume interaction: Phase 2 owns "keep until installer exits 0"; for Phase 1 delete in the existing "Cleanup temp bootstrapping config" step (`plans/subplans/install.pp` around line 633). Whether Bolt's upload already lands as 0600 is [ASSUMED]; check with `stat -c %a /tmp/pe.conf` in the acceptance run.
- Token file: `tasks/rbac_token.rb:69` does `File.open('/root/.puppetlabs/token', 'w')`, which is subject to the process umask (typically 0644). Use `File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600)` and `File.chmod(0o600, path)` for the pre-existing file case; `FileUtils.mkdir_p('/root/.puppetlabs')` should pass `mode: 0o700`. Add a unit spec with a temp dir (the task hard-codes `/root`; introduce a constructor/param seam for the path).

### Anti-Patterns to Avoid
- **Redact after `tail`:** a key block split by the window leaks its body. Redact the whole file first.
- **Editing `task_helper.sh` to add the failure report:** it has global side effects on source; use a sibling functions-only file.
- **Bumping `rspec-puppet-facts`/`facterdb` to 6.x/4.x for "EL10 facts":** drags in `openfact`; nothing in Phase 1 needs it.
- **Putting Bolt 5 and Puppet 9 behind `secrets.*` in a job `if:`:** the `secrets` context is not available there (Pitfall 3).
- **A test-only knob in `peadm::upgrade`:** violates D-14; the injected fault belongs in `spec/acceptance/peadm_spec/plans/`.
- **Mirroring the redaction pattern list in Ruby and bash:** two lists drift. Phase 1 needs the shell one only; if a plan-side redactor is later needed, generate both from one fixture file of planted secrets.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Parsing PEM/DER certs, keys, CRLs | Manual base64/ASN.1 or header regexes | `OpenSSL::X509::Certificate.new`, `OpenSSL::X509::CRL.new`, `OpenSSL::PKey.read` | They accept both encodings and every key type; probed in this session |
| Chain verification and expiry | Date arithmetic over `not_after` only | `OpenSSL::X509::Store#verify` plus `error_string`, and `not_after` for the warn window | Store gives the exact OpenSSL reason ("certificate has expired") |
| JSON task output in shell | printf-built JSON | `task_helper.sh` (`task-output`, `_output`) | Already escapes control characters; the harness parses its output |
| Test stub for processes | A mock library | A temp dir of tiny bash stubs on PATH | Exercises the real shell script, including `set -e` and pipes |
| Gem source switching | A second Gemfile | The existing `location_for` + `source ... do` block keyed on `PUPPET_FORGE_TOKEN` | Already in the Gemfile; add `BOLT_GEM_VERSION` beside `PUPPET_GEM_VERSION` |
| Capturing plan output in a spec | Reading stdout | `allow(executor).to receive(:publish_event).and_wrap_original` | Proven to capture every `out::message` (Code Examples) |
| Semver range test for the default PE version | String comparison | `SemanticPuppet::VersionRange.parse(">= #{oldest} <= #{newest}")` | Same semantics as `assert_supported_pe_version`'s `SemVerRange` |

**Key insight:** every item here already has a standard-library or in-repo answer; the phase risk is in wiring (paths, layouts, ordering), not in algorithms.

## Runtime State Inventory

Not a rename/refactor/migration phase; omitted. (The ledger and fix-log are documentation, not runtime state.)

## Common Pitfalls

### Pitfall 1: Helper 9 needs Ruby 3.2, but the repo and CI pin Ruby 3.1
**What goes wrong:** `bundle install` fails on any lane still using Ruby 3.1. **Where:** `.ruby-version` (`3.1.0`), `.github/workflows/spec.yml` (`setup_matrix` and `Coverage` jobs use `ruby-version: '3.1'`), and 22 other workflow files (`grep -c "ruby-version: '3.1'"`: test-add-compiler, test-backup-restore, test-install*, test-upgrade*, test-failover, test-migration, test-legacy-*, test-replace-failed-postgresql, test-fips-install-matrix, and others). The Puppet 8 spec matrix is not affected: `matrix_from_metadata_v2` maps Puppet 8 to Ruby 3.2 [VERIFIED: `puppet_litmus-2.8.1/exe/matrix_from_metadata_v2` COLLECTION_TABLE].
**Why:** `puppetlabs_spec_helper` 9.0.0 declares `ruby >= 3.2`; `voxpupuli-puppet-lint-plugins` 7.0.0 declares `>= 3.2.0` [VERIFIED: rubygems.org API v2].
**How to avoid:** Change all `ruby-version: '3.1'` to `'3.2'` (or `'3.3'`), `.ruby-version` to match, and update `CLAUDE.md`/stack docs that say 3.1.0. The acceptance workflows only need Bolt + litmus (Ruby >= 3.1) but share the Gemfile, so they must move too. Record in the ledger that D-08's "Ruby 3.1" wording was superseded. The Gemfile pins `i18n < 1.15.0 if Ruby < 3.2` becomes dead code; leave or remove.
**Warning signs:** "Could not find compatible versions ... required_ruby_version" in CI.

### Pitfall 2: Rakefile and `.sync.yml` still name `puppet-syntax`
**What goes wrong:** after the bump `rake spec_prep` aborts: `LoadError: cannot load such file -- puppet-syntax/tasks/puppet-syntax` [VERIFIED: reproduced in scratch].
**How to avoid:** delete `require 'puppet-syntax/tasks/puppet-syntax'` (Rakefile line 6; helper 9's `rake_tasks.rb` already requires `puppetlabs-syntax/tasks/puppetlabs-syntax`) and change the last line to `PuppetlabsSyntax.exclude_paths.concat(["plans/**/*.pp", "spec/acceptance/**/plans/**/*.pp", "vendor/**/*"])`. Use `concat`, not `=`: the helper pre-seeds `spec/fixtures/**/*`, `pkg/**/*` and `vendor/**/*`, and `=` discards them. Update the matching `extras:` entry in `.sync.yml` so a `pdk update` does not regenerate the old line. Verified after the fix: `rake validate` exit 0, `rake rubocop` 111 files no offenses.

### Pitfall 3: `secrets.*` cannot gate a job
**What goes wrong:** `if: ${{ secrets.PUPPET_FORGE_TOKEN != '' }}` is invalid at job level. The `secrets` context is not available in `jobs.<job_id>.if` or in `jobs.<job_id>.steps.if` [CITED: docs.github.com/en/actions/reference/workflows-and-actions/contexts].
**How to avoid:** a small preceding job exposes `has_token` as an output computed in a step whose `env` maps the secret, and the Bolt 5 job uses `needs: check_token` plus `if: needs.check_token.outputs.has_token == 'true'`. The existing Puppet 9 job already maps `secrets.PUPPET_FORGE_TOKEN || secrets.PUPPET_FORGE_TOKEN_PUBLIC` inside a step; reuse that expression. Fork PRs receive empty secrets, so the lane silently skips there (desired by D-09).

### Pitfall 4: Widening `metadata.json` adds a blocking Puppet 9 job to the shared `ci.yml`
**What goes wrong:** TST-03 changes `metadata.json` `puppet` from `>= 8.0.0 < 9.0.0` (line 87) to admit Puppet 9. `ci.yml` calls `puppetlabs/cat-github-actions/.github/workflows/module_ci.yml@main`, which builds its matrix with `matrix_from_metadata_v3`; that tool's table contains `{puppet: 9.0, ruby: 4.0}` and adds a spec include for every collection the metadata admits, regardless of token [VERIFIED: `puppet_litmus-2.8.1/exe/matrix.json` and `matrix_from_metadata_v3` lines ~300-330; CITED: raw `module_ci.yml` shows `matrix_from_metadata_v3`, "Twingate setup runs only on the Puppet 9 lane", `rake parallel_spec`]. On a run without the token that job cannot install Puppet 9. This conflicts with D-09 ("Puppet 8 stays the merge gate").
**How to avoid:** make the Puppet 9 spec job non-required in branch protection (user action) or keep the metadata widening in the same PR as the lane change so the effect is deliberate. Because `ci.yml` is `unmanaged: false` in `.sync.yml` it may be overwritten by a template sync. Raise this with the user (Open Question 3). The `metadata.json` `puppet` range recommended by research is `>= 8.0.0 < 10.0.0`.

### Pitfall 5: `rspec-puppet-facts` 6.x pulls in OpenFact
**What goes wrong:** bumping it to `~> 6.3` (as `research/STACK.md` proposed) resolves `facter 4.10.0` and `openfact 5.7.3` together [VERIFIED: scratch `bundle lock`]; both define `Facter`. **How to avoid:** leave `rspec-puppet-facts ~> 2.0` and `facterdb ~> 1.18` (resolved 2.0.5 and 1.27.0 and passing).

### Pitfall 6: The acceptance "resume" test can only prove what the code already supports
**What goes wrong:** `tasks/pe_install.sh` runs `rm -f "$PT_tarball"` **before** invoking the installer, and the `preparation` step is where the tarball is staged. If the injected fault makes the **installer** fail (the U-01 recipe: a `pe-puppetdb` `ExecReload` drop-in that fails once), a resume at `upgrade-primary` has no tarball; fixing that is UPG-04 in Phase 2.
**How to avoid:** run the slice as two recorded outcomes. (A) a fault after the installer exits 0, then resume at `upgrade-node-groups`: expected to pass today and is the Phase 1 gate. One candidate that needs no new knob: place `fail('injected')` in `/etc/puppetlabs/code/environments/production/manifests/site.pp` so the post-install `peadm::puppet_runonce` fails, then remove it and resume [ASSUMED: confirm `puppet_runonce` fails the task on a compile error]. (B) the U-01 installer fault with resume at `upgrade-primary`: record the failure as the UPG-04 baseline; do not treat it as a Phase 1 defect. For a standard architecture the steps `upgrade-primary-compilers`, `upgrade-replica`, `upgrade-replica-compilers` do nothing, so choose faults in `upgrade-primary` or `upgrade-node-groups`.

### Pitfall 7: `code_manager.sh` reports success when curl fails
**What goes wrong:** `curl_wrapper` does `output=$(curl "$@"); exitcode=$?` and ends with an `if [ "$g_verbose" = 'true' ]; then ... fi` that returns 0; `fs_commit`, `fs_force_sync` and `flush_environment_cache` therefore always succeed, and `-ks` has no `-f`, so HTTP errors are also ignored [VERIFIED: read of `tasks/code_manager.sh`]. Adopting the failure helper means deciding to propagate the status (fail on non-2xx) and print the redacted body. That is a behaviour change: callers that currently "succeed" while the service is restarting will start failing. **How to avoid:** pin current behaviour with a harness spec (stub `curl`), then change it deliberately, log it in the ledger as a fix with a fix-log entry, and check `plans/subplans/configure.pp` and `plans/subplans/install.pp` call sites for tolerance (`peadm::code_manager` is called in the install path right after services restart).

### Pitfall 8: Over-redaction and sed portability
The tested rule set also redacts `token_lifetime: 1y` and swallows the rest of a query string after a `...Credential=` match, because the generic `key=value` rule is greedy. That is the safe direction; do not "fix" it by loosening patterns. The `c\` range form used for private-key blocks is GNU sed behaviour verified on Linux; the targets and CI are Linux. If macOS developers run the harness, BSD sed range-`c` semantics may differ [ASSUMED]; add a `sed --version`-independent fallback or document Linux-only.

### Pitfall 9: `rake lint` regresses with plugins 7.0
**What goes wrong:** new lint exit code 1 from `manifests/setup/node_manager.pp:77` (`missing trailing comma after last element ... check: trailing_comma`) after the bump; baseline is exit 0 with one unrelated warning [VERIFIED: ran both]. **How to avoid:** add the trailing comma after `['~', ['fact', 'pe_server_version'], '.+']` (line 77); no other new warnings appeared. `rake check` fails in a non-git scratch copy only (`git ls-files failed`); run it in the real repo.

### Pitfall 10: Fixture pinning gaps
`container_inventory` (gitlab.com/nwops/bolt-container_inventory) has no tags; pin it to a commit (`d7b89b8` was HEAD at research time). `stdlib` fixture currently floats on `main`; pin to the version `Puppetfile` ships (`v9.5.0`) since that is what Bolt installs for operators; the full suite passed with stdlib v9.5.0, node_manager v1.0.1 (the Puppetfile pin, the floating fixture was v1.1.0) and format v1.1.1 [VERIFIED: run this session]. `.fixtures.yml` forge modules float too (`service` and `package` resolved 4.0.0, `reboot` 6.1.0, `inifile` 6.6.0, `ruby_task_helper`); pin each with `repo:`/`ref:` hashes (worked).

## Code Examples

### Harness core
```ruby
# spec/support/shell_task_harness.rb -- prototype ran green against tasks/pe_install.sh
require 'open3'; require 'json'; require 'tmpdir'; require 'fileutils'

class ShellTaskHarness
  REPO = File.expand_path('../..', __dir__)
  attr_reader :root, :stubs

  def initialize
    @root  = Dir.mktmpdir('peadm-shelltask')
    @stubs = File.join(@root, 'stubs')
    @mod   = File.join(@root, 'modules', 'peadm')   # name must be "peadm": tasks source ../../peadm/files/...
    FileUtils.mkdir_p([@stubs, File.join(@mod, 'tasks'), File.join(@mod, 'files')])
    FileUtils.cp(Dir[File.join(REPO, 'files', '*.sh')], File.join(@mod, 'files'))
  end

  def stub(name, body)
    path = File.join(stubs, name)
    File.write(path, "#!/bin/bash\necho \"$0 $*\" >> #{File.join(root, name)}.calls\n#{body}\n")
    File.chmod(0o755, path)
  end

  def calls(name)
    f = File.join(root, "#{name}.calls")
    File.exist?(f) ? File.readlines(f, chomp: true) : []
  end

  def run(task, params = {}, env = {})
    dest = File.join(@mod, 'tasks', task)
    FileUtils.cp(File.join(REPO, 'tasks', task), dest)
    pt  = params.to_h { |k, v| ["PT_#{k}", v.to_s] }
    out, err, st = Open3.capture3({ 'PATH' => "#{stubs}:#{ENV['PATH']}", 'LANG' => 'C' }.merge(pt, env), '/bin/bash', dest)
    { stdout: out, stderr: err, status: st.exitstatus, json: (JSON.parse(out) rescue nil) }
  end

  def cleanup = FileUtils.rm_rf(root)
end
```
Spec shape (prototype, passed): build a real tarball whose first entry is the installer file, set `PE_INSTALLER_LOG_DIR` to a temp dir with a 60-line log, stub `systemctl` for `list-units` and `status`, run `pe_install.sh` with installer exit 6, and assert `status == 6` and `json['_output']` includes `installer failed with exit code 6`, the last log line and the failed unit.

### Redaction (tested against planted secrets)
```bash
# files/failure_report.sh -- sed -E, GNU sed on Linux; redact the WHOLE file, then tail
peadm_redact() {
  sed -E \
    -e '/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/,/-----END [A-Z0-9 ]*PRIVATE KEY-----/c\
[REDACTED PRIVATE KEY]' \
    -e 's#(://[^/@[:space:]:]+):[^/@[:space:]]+@#\1:[REDACTED]@#g' \
    -e 's/([?&;](X-Amz-Signature|X-Amz-Credential|X-Amz-Security-Token|Signature|sig|token|access_token|api[_-]?key|key)=)[^&[:space:]"'"'"']+/\1[REDACTED]/Ig' \
    -e 's/((Authorization|X-Authentication|Proxy-Authorization)[[:space:]]*:[[:space:]]*(Bearer |Basic |Token )?)[^[:space:]"]+/\1[REDACTED]/Ig' \
    -e 's/("?[A-Za-z0-9_:.-]*(password|passwd|passphrase|secret|token|api[_-]?key|private[_-]?key|credential)[A-Za-z0-9_:.-]*"?[[:space:]]*[=:][[:space:]]*)("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:],}]+)/\1[REDACTED]/Ig'
}
# usage: peadm_redact < "$latest_log" | tail -n "${PEADM_REPORT_LOG_LINES:-40}"
```
Result on the sample (verified): `console_admin_password: [REDACTED]`, `"console_admin_password": [REDACTED],`, `password=[REDACTED] next=ok`, `https://user:[REDACTED]@host/...`, `sig=[REDACTED]`, `X-Authentication: [REDACTED]`, `Authorization: Bearer [REDACTED]`, PEM private key block collapsed to one line, certificate blocks and normal lines untouched.

### Capture every plan message for the FND-05 negative assertion
```ruby
# proven in a scratch spec against peadm::install
messages = []
allow(executor).to receive(:publish_event).and_wrap_original do |orig, event|
  messages << event[:message] if event[:type] == :message
  orig.call(event)
end
allow_out_message
# ... run_plan(..., 'console_password' => 'FAKE-SECRET-pw1') ...
expect(messages).not_to be_empty
expect(messages.join("\n")).not_to include('FAKE-SECRET-pw1')
```

### Certificate findings (shape and key calls)
```ruby
# files/cert_check.rb (sketch; every call below was exercised in the probe)
module PeadmCertCheck
  Finding = Struct.new(:severity, :code, :message) { def to_h = { 'severity' => severity, 'code' => code, 'message' => message } }

  def self.load_key(data, passphrase = nil) = OpenSSL::PKey.read(data, passphrase)     # RSA, EC, Ed25519, PEM or DER
  def self.empty_subject?(cert) = cert.subject.to_a.empty?
  def self.expired?(cert, now = Time.now) = cert.not_after < now
  def self.expires_within?(cert, days, now = Time.now) = cert.not_after < now + (days * 86_400)
  def self.key_matches?(cert, key) = cert.check_private_key(key)
  def self.crl_stale?(crl, now = Time.now) = crl.next_update && crl.next_update < now
  # chain: store = OpenSSL::X509::Store.new; roots.each { store.add_cert(_1) }; store.verify(leaf, intermediates) / store.error_string
  # CRL header: reject text containing "BEGIN CRL" with code crl_bad_header; OpenSSL::X509::CRL.new needs "BEGIN X509 CRL"
end
```

### Gemfile switch for the credentialed Bolt 5 lane (resolution tested without a token)
```ruby
# in group :development
gem "bolt", '>= 4.0.0', require: false unless ENV['BOLT_GEM_VERSION']
# beside gems['puppet'] = location_for(puppet_version)
gems['bolt'] = location_for(ENV['BOLT_GEM_VERSION']) if ENV['BOLT_GEM_VERSION']
# With PUPPET_FORGE_TOKEN set, the existing `source 'https://rubygems-puppetcore.puppet.com' do ... gems.each ... end`
# block pulls bolt from puppetcore. CI sets BOLT_GEM_VERSION='~> 5.2.1' and PUPPET_GEM_VERSION='~> 9.1'.
```
Both paths resolved (`bolt (4.0.0)` with and without `BOLT_GEM_VERSION='~> 4.0'`); the puppetcore path needs a token and is the spike. puppetlabs-puppet_agent uses the same idea (`gem "bolt", *location_for(bolt_gem_version, nil, {source: gemsource_puppetcore}) if ENV["GEM_BOLT"]`) [VERIFIED: `spec/fixtures/modules/puppet_agent/Gemfile`].

### CI gating for the Bolt 5 lane
```yaml
  check_token:
    runs-on: ubuntu-latest
    outputs:
      has_token: ${{ steps.t.outputs.has_token }}
    steps:
      - id: t
        env:
          FORGE_TOKEN: ${{ secrets.PUPPET_FORGE_TOKEN }}
        run: echo "has_token=$([ -n "$FORGE_TOKEN" ] && echo true || echo false)" >> "$GITHUB_OUTPUT"
  Bolt5Puppet9:
    needs: check_token
    if: ${{ needs.check_token.outputs.has_token == 'true' && github.repository_owner == 'puppetlabs' }}
    continue-on-error: true
    # env: PUPPET_GEM_VERSION '~> 9.1', BOLT_GEM_VERSION '~> 5.2.1', PUPPET_FORGE_TOKEN, BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM=forge-key:$TOKEN
    # steps: checkout, ruby 4.0, bundle exec rake parallel_spec, bundle exec bolt --version
```
Bolt's documented bundler config for the gem path is `bundle config set --global https://rubygems-puppetcore.puppet.com "forge-key:${PUPPET_FORGE_TOKEN}"` [CITED: help.puppet.com/bolt/current/topics/bolt_installing.htm]; `spec.yml` already uses the equivalent `BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM=forge-key:...`.

### Rakefile fix (verified)
```ruby
# delete: require 'puppet-syntax/tasks/puppet-syntax'
PuppetlabsSyntax.exclude_paths.concat(["plans/**/*.pp", "spec/acceptance/**/plans/**/*.pp", "vendor/**/*"])
```

### Fixture pins (all cloned and the full suite passed)
```yaml
fixtures:
  forge_modules:
    ruby_task_helper: { repo: puppetlabs/ruby_task_helper, ref: 1.1.0 }
    service:  { repo: puppetlabs/service,  ref: 4.0.0 }
    package:  { repo: puppetlabs/package,  ref: 4.0.0 }
    reboot:   { repo: puppetlabs/reboot,   ref: 6.1.0 }
    inifile:  { repo: puppetlabs/inifile,  ref: 6.6.0 }
  repositories:
    facts:        { repo: https://github.com/puppetlabs/puppetlabs-facts.git,        ref: v1.8.1 }
    puppet_agent: { repo: https://github.com/puppetlabs/puppetlabs-puppet_agent.git, ref: v4.28.0 }
    provision:    { repo: https://github.com/puppetlabs/provision.git,               ref: v3.2.0 }
    stdlib:       { repo: https://github.com/puppetlabs/puppetlabs-stdlib.git,       ref: v9.5.0 }
    apply_helpers: { repo: https://github.com/puppetlabs/puppetlabs-apply_helpers,   ref: 0.3.0 }
    bolt_shim:    { repo: https://github.com/puppetlabs/puppetlabs-bolt_shim,        ref: 0.4.0 }
    format:       { repo: https://github.com/voxpupuli/puppet-format,                ref: v1.1.1 }
    container_inventory: { repo: https://gitlab.com/nwops/bolt-container_inventory.git, ref: d7b89b8 }
    node_manager: { repo: https://github.com/puppetlabs/puppetlabs-node_manager.git, ref: v1.0.1 }
  symlinks: { peadm: '#{source_dir}', peadm_spec: '#{source_dir}/spec/acceptance/peadm_spec' }
```
Tags confirmed with `git ls-remote --tags` (latest at research time: facts v1.8.1, puppet_agent v4.28.0, stdlib v10.1.1, apply_helpers 0.3.0, bolt_shim 0.4.0, format v1.1.1 / v2.2.0, node_manager v1.1.0 / v1.0.1). Keep it expanded (not flow style) to match the existing file.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `puppet-syntax` gem, `PuppetSyntax` constant | `puppetlabs-syntax` gem, `PuppetlabsSyntax` constant | helper 9.0.0, 2026-08-20 [CITED: puppetlabs_spec_helper CHANGELOG] | Rakefile and `.sync.yml` edits |
| Bolt as gem from rubygems.org | Bolt 5.x licence-gated; documented gem path from puppetcore with `PUPPET_FORGE_TOKEN` | 5.0.0 (2025-09-23); gem path on the current install page [CITED] | Public gem stops at 4.0.0; credentialed lane for 5.2.1 |
| Puppet 8 bundles Ruby 3 | Bolt 5.2.0 ships Puppet 8 (Ruby 3) and Puppet Core 9 (Ruby 4); Puppet Core 9 needs Ruby 4.0 compatibility, JDK 21 | 5.2.0, 2026-09-18 [CITED: Bolt changelog; Puppet 8 to 9 upgrade guide] | Puppet 9 lane on Ruby 4.0 |
| `/status/v1/services` open | requires an authenticated client in Puppet 9 / PE 2026; `/status/v1/simple` stays open [CITED: Puppet 8 to 9 upgrade guide] | PE 2026.0 | `wait_until_service_ready.sh` uses `/status/v1/simple`: unaffected |
| PE file-system CA | Database-backed CA default on new 2026 installs; upgrades keep their backend; selected by `puppet_enterprise::ca_storage_backend` [CITED: help.puppet.com/pe/current/topics/database-backed-certificate-authority.htm] | PE 2026.0 | `bootstrap.cfg` grep detection needs on-node confirmation (Open Question 4) |

**Deprecated/outdated:**
- `matrix_from_metadata_v2`: litmus 2.8.1 prints "deprecated and will be removed in puppet_litmus v3"; `spec.yml` still calls it in `setup_matrix`. Not a Phase 1 requirement; note it for Phase 2 CI work.
- `Ruby 3.1` anywhere in CI (see Pitfall 1).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Ruby 3.1 is end-of-life, so dropping it is acceptable | Standard Stack, Pitfall 1 | Low: user may still want a 3.1 lane; fall back to the puppet_agent dual-Gemfile pattern |
| A2 | Bolt installs a task's shared files as `<installdir>/peadm/files` beside `<installdir>/peadm/tasks`, making `require_relative '../files/cert_check'` valid on nodes | Pattern 3 | Medium: `validate_cert` fails at runtime; a first acceptance run or a Bolt `--debug` run catches it. Fallback: the existing cross-module form plus a `$LOAD_PATH` shim |
| A3 | Resolving the environment once and passing `--pe-environment` / `node_group_environment` clears PE-39789 and PE-46598 | Pattern 5 | Medium: tickets carry no detail; the real failure may be elsewhere (classifier import, code-staging path). Verify with scenarios I-02 and M-02 |
| A4 | "The CA timeout" in FND-07 means the `ca` service readiness wait | Pattern 7 | Low to medium: if it means a PE-core `puppet infrastructure` CA-query timeout (GJira-11), a different parameter is needed |
| A5 | Bolt's `upload_file` may leave `/tmp/pe.conf` world-readable | Pattern 8 | Low: `chmod 0600` is harmless either way |
| A6 | A `fail('injected')` in the production `site.pp` makes `peadm::puppet_runonce` fail after the installer exits 0 | Pitfall 6 | Medium: the injected fault may not trigger; try on the VMs and fall back to a drop-in on another service |
| A7 | BSD sed range-`c` may differ from GNU sed | Pitfall 8 | Low: Linux CI; document Linux-only harness runs if needed |
| A8 | Bolt 5.2.1 gem installs from the puppetcore source with only `PUPPET_FORGE_TOKEN` and `peadm` unit specs pass under it | Standard Stack, Code Examples | High for TST-02's answer: this is exactly the spike; the lane's first run produces the result |
| A9 | PE 2026 CA backend can still be detected with the `bootstrap.cfg` grep that `backup.pp` and `restore.pp` use | TST-03 | High: a wrong detection skips the `pe-ca` dump or restore; confirm on a PE 2026.0.1 node (Open Question 4) |
| A10 | The shared `module_ci.yml` job names a Puppet 9 spec job only if `metadata.json` admits Puppet 9 | Pitfall 4 | Medium: derived from `matrix_from_metadata_v3` source read here; confirm by pushing the metadata change on a branch |

## Open Questions (RESOLVED)

1. **How wide is the RSA-only fix (D-07 vs reality)?**
   - Known: there is no `PKey.read` call in the repo; `OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))` appears 16 times in 15 tasks (`code_sync_status.rb:25`, `get_peadm_config.rb:140`, `rbac_token.rb:54`, `backup_classification.rb:26`, and others) and 14 unit specs stub `OpenSSL::PKey::RSA`. `research/STACK.md` named only `tasks/code_sync_status.rb`.
   - Unclear: whether D-07's "the RSA-only site" means `code_sync_status.rb` alone. TST-03 says "RSA-only key parsing (`PKey.read`)".
   - Recommendation: honour D-07 literally (replace `code_sync_status.rb`, adopt the checker's `load_key`), and list the other 15 in the ledger as follow-ups. The host key is the node's own Puppet key; whether PE 2026 can generate non-RSA host keys is unverified [ASSUMED]. Ask the user if a mechanical swap of all 16 (one-line change each plus spec updates) is wanted now.
   - **RESOLVED:** D-07 is limited to tasks/code_sync_status.rb (user decision); the other 15 RSA-only sites are ledger follow-ups (plan 01-07).
2. **Ruby floor wording in D-08.** The helper bump forces Ruby >= 3.2. Confirm Ruby 3.2 (or 3.3) as the new floor and the edits to `.ruby-version`, the 23 workflow files that pin Ruby 3.1 (`spec.yml` plus 22 acceptance workflows) and `CLAUDE.md`.
   - **RESOLVED:** Ruby floor is 3.3 (user decision): .ruby-version, spec.yml, the 22 acceptance workflows and the CLAUDE.md Ruby mentions (plans 01-01 and 01-02); a local Ruby 3.2.x is the accepted fallback.
3. **Branch protection and the shared `ci.yml`.** Widening `metadata.json` adds a Puppet 9 / Ruby 4.0 spec job to `ci.yml` (Pitfall 4). Which checks are required is a repository setting this environment cannot see.
   - **RESOLVED:** The metadata.json widening is deferred (user decision): metadata.json keeps `>= 8.0.0 < 9.0.0`, so ci.yml gains no Puppet 9 job and needs no change; the Puppet 9 signal comes from the continue-on-error job in spec.yml (plan 01-03), and the widening is a recorded deferred follow-up.
4. **PE 2026 CA-backend detection (TST-03 `bootstrap.cfg`).** The Puppet 9 upgrade guide says an upgrade "adds a new `bootstrap.cfg` with no customizations ... The old file will remain in place and will not be overwritten" [CITED: help.puppet.com/core/.../upgrading-from-puppet8-to-puppet9.htm]. The PE docs name `puppet_enterprise::ca_storage_backend` as the selector but say nothing about where to read it. `plans/backup.pp:62` and `plans/restore.pp:108` grep `/etc/puppetlabs/puppetserver/bootstrap.cfg` for `database-storage-service`. Run on a new PE 2026.0.1 install and on an upgraded one: `grep -rn database-storage-service /etc/puppetlabs/puppetserver /opt/puppetlabs/server/apps/puppetserver/config` and `puppet lookup puppet_enterprise::ca_storage_backend`; then move detection into one shared task used by both plans (it is duplicated inline today).
   - **RESOLVED:** Carried to plan 01-13: the shared peadm::ca_storage_backend task (plan 01-11) is checked against the grep and `puppet lookup` on 2025.12.1 and 2026.0.1 nodes by peadm_spec::foundation_node_checks in the Task 2 human-action checkpoint; plan 01-14 corrects the location list if the node disagrees.
5. **Does peadm run unchanged on Bolt 5.2 / Puppet Core 9?** Needs a Puppet Core key. First run of the new lane answers unit-level compatibility (`assert_supported_bolt_version` accepts `>= 3.17.0 < 6.0.0`, so 5.2.1 passes the gate); `peadm::status` and an upgrade on PE 2026.0.1 answer the rest. Record the result in the fix-log or a research note; this is the STATE.md blocker.
   - **RESOLVED:** Carried to plan 01-13: the token-gated Bolt5Puppet9 and Puppet 9 lanes (plan 01-03) report in the Task 2 human-action checkpoint, together with the Bolt version used for the acceptance run; the answer is recorded in ledger row P1-03.
6. **Ticket keys for commit subjects.** CLAUDE.md and the ledger require commit subjects to start with a ticket ID. Phase 1 changes mostly have none until TRC-03 files P0-1..P0-3. Decide which keys (or placeholder convention) Phase 1 commits use.
   - **RESOLVED:** Placeholder keys: changes without a ticket start their commit subject with their ledger ID (P1-nn); work extending the Phase 0 defects uses P0-1, P0-2 or P0-3 until TRC-03 files them (user decision, convention kept). Refined in plan revision round 2: every commit also carries a `Ledger-ID: P1-nn` trailer, and plan 01-14 matches ledger rows to commits by that trailer; where this differs from the subject convention, the trailer rule wins.
7. **Acceptance PE version pair.** Catalog U-01 uses `ci_from: 2023.8.13` and `ci_to: 2025.12.1`; the stack research lists test lines 2023.8.13, 2025.12.1 and 2026.0.1. Pick one n to n+1 pair (suggest 2025.12.1 to 2026.0.1 for the Puppet 9 signal, plus the existing 2023.8.13 to 2025.12.1 as the skip-line comparison) and a new scenario id (the catalog's last upgrade id is U-12; `scenarios.rb --validate` and the doc-sync spec will need `ruby spec/acceptance/scenarios.rb --format markdown --write` after adding it).
   - **RESOLVED:** Scenario U-13, standard architecture, 2025.12.1 to 2026.0.1 (plan 01-13); both versions are plan parameters.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ruby | all specs | yes | 3.2.3 | none needed (3.2 is the new floor) |
| Bundler | all specs | yes (user gem dir, `bundle` not on PATH by default) | 4.0.24 | `export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"` |
| git, network to rubygems.org / github.com | gems, fixtures | yes | - | - |
| `file`, `tar`, `systemctl`, `localectl`, `xargs` | harness, `pe_install.sh` | yes | - | stub per spec |
| Puppet Core token (`PUPPET_FORGE_TOKEN`) | Puppet 9, Bolt 5 | no (anonymous puppetcore returns 401) | - | CI secret only; local runs cannot exercise Puppet 9 / Bolt 5 |
| Ruby 4.0 | Puppet 9 lane | no | - | CI lane only |
| Bolt CLI | acceptance | no (only the Bolt 4.0.0 gem via bundle) | - | `bundle exec bolt` |
| docker, shellcheck, pdk | optional | no | - | not required; shared `module_ci.yml` runs shellcheck only for Ruby 3.1 matrix entries |
| Operator VMs with PE, SSH inventory (`pedev_inventory.yaml` pattern: `role` var per host) | TST-04 (manual, D-13) | not probed (user-owned) | - | none: required for success criterion 5 |
| Jira access | TRC-03 | no tooling here | - | user files tickets by hand using the ledger's "Tickets that need filing" text |

**Missing dependencies with no fallback:** operator VMs for the acceptance slice; a Puppet Core key for definitive Puppet 9 / Bolt 5 results.
**Missing dependencies with fallback:** all others.

## Security Domain

`security_enforcement` is enabled (config.json, ASVS level 1, block on high).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no (RBAC token request exists but is unchanged) | - |
| V3 Session Management | no | - |
| V4 Access Control | yes (file modes on secret copies, token file, `/tmp/pe.conf`) | explicit `0600`/`0700` modes applied before content is written |
| V5 Input Validation | yes | Puppet parameter types; `shellquote` in plans; avoid interpolating params into code (`tasks/read_file.sh` embeds `$PT_path` in Python source: `open('$PT_path','r')`; low risk since the path comes from a typed plan param, but pass it as `sys.argv` if the task is touched) |
| V6 Cryptography | yes | stdlib OpenSSL for parse/verify; no custom crypto; do not weaken `VERIFY_PEER` (note `tasks/check_legacy_compilers.rb:53` uses `VERIFY_NONE`; out of scope, record it) |
| V7 Error handling and logging | yes (core of FND-01, FND-05) | redact-then-tail helper; no secrets in plan messages; `peadm::log_plan_parameters` already omits `console_password` (install) and logs only the tarball basename (upgrade) |
| V8 Data protection | yes | modes above; remove `/tmp/pe.conf`; secrets travel as task parameters and `read_file` output in `copy_file` (known, recorded in CONCERNS.md) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Secrets echoed in installer/service logs surfaced in Bolt output | Information disclosure | `peadm_redact` over the full file before `tail`; spec with planted secrets for task output and plan messages |
| World-readable secret files (`copy_file` 0644, `/tmp/pe.conf`, token file) | Information disclosure | per-path modes, delete after use |
| Private-key block cut by a log window | Information disclosure | redact whole file, then tail |
| Signed URL credentials in logs (`X-Amz-Signature`, `sig=`) | Information disclosure | query-string rules; log basenames only in plans |
| Shell injection through task params | Tampering / elevation | keep params quoted; never `eval`; stub specs use fixed values |
| Secrets in CI logs for the credentialed lane | Information disclosure | token only via `secrets.*` mapped to env; GitHub masks it; do not `echo` it; lane skipped on forks |
| Over-trusting a new transitive gem | Tampering (supply chain) | `puppetlabs-syntax` noted in the ledger; lock resolves from rubygems.org only |

## Sources

### Primary (HIGH confidence)
- Local repo files read this session: `Gemfile`, `Rakefile`, `.fixtures.yml`, `.sync.yml`, `metadata.json`, `data/pe_versions.yaml`, `plans/install.pp`, `plans/upgrade.pp`, `plans/restore.pp`, `plans/backup.pp`, `plans/util/copy_file.pp`, `plans/subplans/install.pp`, `plans/subplans/configure.pp`, `tasks/pe_install.sh`, `tasks/wait_until_service_ready.sh`, `tasks/code_manager.sh`, `tasks/mkdir_p_file.sh`, `tasks/rbac_token.rb`, `files/task_helper.sh`, `.github/workflows/spec.yml`, `spec/spec_helper*.rb`, `documentation/change-ledger.md`, `documentation/fix-log.md`, `spec/acceptance/scenarios.yaml`.
- Executed in a scratch copy of the repo (Ruby 3.2.3, bundler 4.0.24): gem bump resolution, `rake spec_prep`, `rspec spec/plans spec/functions spec/unit spec/classes` (534 examples, 0 failures, with floating and with tag-pinned fixtures), `rake parallel_spec` (534, 0 failures, 2m13s), `rake spec:simplecov` (83.0% line coverage), `rake lint validate rubocop` before and after; harness, redaction, OpenSSL and plan-message-capture prototypes.
- RubyGems API v1/v2 (queried 2026-11-10): required Ruby versions and dependencies for helper 9.0.0, rspec-puppet 5.0.0/6.0.0, rspec-puppet-facts 6.3.1, facterdb 4.5.0, plugins 7.0.0, litmus 2.8.1, bolt 4.0.0, openfact.
- Installed gem sources: `puppet_litmus-2.8.1/exe/matrix_from_metadata_v2`, `matrix_from_metadata_v3`, `matrix.json`; `puppetlabs-syntax-7.2.1`; `puppetlabs_spec_helper-9.0.0/lib/puppetlabs_spec_helper/rake_tasks.rb`; `bolt-4.0.0/lib/bolt_spec/plans/mock_executor.rb`.

### Secondary (MEDIUM confidence)
- Bolt install page: https://help.puppet.com/bolt/current/topics/bolt_installing.htm (gem install from puppetcore, credentials, `PUPPET_FORGE_TOKEN`)
- Bolt changelog: https://help.puppet.com/bolt/current/topics/changelog.htm (5.0.0 to 5.2.1; only the first 100k characters read)
- Puppet 8 to 9 upgrade guide: https://help.puppet.com/core/current/Content/PuppetCore/upgrading-from-puppet8-to-puppet9.htm (bootstrap.cfg, `/status/v1/services`, Ruby 4)
- PE restore docs: https://help.puppet.com/pe/current/topics/restore_pe_infrastructure.htm (`--pe-environment`, default production)
- PE database-backed CA: https://help.puppet.com/pe/current/topics/database-backed-certificate-authority.htm; PE 2026.0 release notes: https://help.puppet.com/pe/current/topics/release-notes-pe-x-0.htm (does not mention `bootstrap.cfg`)
- GitHub contexts: https://docs.github.com/en/actions/reference/workflows-and-actions/contexts (`secrets` unavailable in `if:`)
- puppetlabs_spec_helper changelog: https://raw.githubusercontent.com/puppetlabs/puppetlabs_spec_helper/main/CHANGELOG.md
- Shared workflow: https://raw.githubusercontent.com/puppetlabs/cat-github-actions/main/.github/workflows/module_ci.yml

### Tertiary (LOW confidence)
- Web search results for `bootstrap.cfg` services.d history (Puppet Server 2.x to 5.x docs); not PE 2026 behaviour, used only to frame Open Question 4.
- Bolt 5.2.1 puppetcore gem availability and `puppet` dependency: documented, not executable here (HTTP 401 anonymous).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH for the Puppet 8 / helper 9 bump (executed end to end); MEDIUM for Puppet 9 / Bolt 5 (documentation only)
- Architecture: HIGH for the harness, redaction, cert probes (prototyped); MEDIUM for FND-02 (tickets give no detail) and the acceptance fault placement
- Pitfalls: HIGH for the toolchain and CI items (reproduced or read from source); MEDIUM for on-node PE 2026 behaviour

**Research date:** 2026-11-10
**Valid until:** 2026-12-10 for gem and CI facts (fast-moving: Puppet 9 / Bolt 5 / helper 9 are weeks old); the in-repo findings stay valid until the files change

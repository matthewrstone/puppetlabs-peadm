# Fix log

Which fix addresses which complaint, and how to see the difference yourself.
The complaints come from the peadm feedback file (support cases `CASE-nnn` and Jira tickets).
The [change ledger](change-ledger.md) lists every change and its files; this log is the
reader's view: the complaint, the fix, and a way to reproduce before and after.

**Keeping it current.** Add an entry in the same commit as the fix, using the template at the
bottom. If a fix cannot be shown without a real cluster, say so in "Demonstrate" and record
what was done instead. Do not mark a fix as demonstrated unless someone ran the steps.

## Showing before and after for a spec-covered fix

A fix that ships with a spec can be shown in a scratch worktree. The spec fails on the code
before the fix and passes on the code after it.

```bash
export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"
FIX=<fix commit>                      # from the entry
REPO=$PWD
git worktree add /tmp/peadm-before "$FIX^"
cd /tmp/peadm-before
cp -r "$REPO/.bundle" . && cp -r "$REPO/spec/fixtures" spec/   # local bundle config and fixture modules
git checkout "$FIX" -- spec/         # new specs only, old code
bundle exec rspec <spec file> -e '<example name>'    # fails: the complaint
git checkout "$FIX" -- .             # now apply the fix
bundle exec rspec <spec file> -e '<example name>'    # passes
cd "$REPO" && git worktree remove --force /tmp/peadm-before
```

Fixes whose entry says "needs a cluster" cannot be shown this way. Use the scenario ID, which
points to the acceptance scenario in [test-scenarios.md](test-scenarios.md).

## Phase 0

### P0-1 `begin_at_step=modify-primary-certs` skips every convert step

- **Complaint:** resuming `peadm::convert` at a named step does nothing. Related: PE-44017, PE-41637 (convert failures). No ticket filed for the mismatch itself.
- **Fix:** `da4c13a`. The step is now named `modify-primary-certs`, matching `Peadm::ConvertSteps`.
- **Reproduce (before):** `bolt plan run peadm::convert ... begin_at_step=modify-primary-certs` on `da4c13a^`. Every step prints `SKIPPING`, including the A/B pin sanity check.
- **Demonstrate (after):** the same command on `da4c13a` runs from that step onward.
- **Status:** needs a cluster or an existing PE to convert. No new spec yet. Not yet demonstrated.

### P0-2 `peadm::upgrade` cannot resume at `preparation`, and resumed runs leave Puppet running

- **Complaint:** CASE-002, CASE-011. A run resumed after a failure skipped `preparation`, the only place Puppet was stopped on the infrastructure nodes. Related: PE-37220 (upgrade reports complete after a failed step).
- **Fix:** `56a345c`. `preparation` is an allowed `begin_at_step`, and resumed runs keep Puppet stopped.
- **Reproduce (before):** `bolt plan run peadm::upgrade ... begin_at_step=upgrade-primary` on `56a345c^`, then check `puppet agent --disable` state on the nodes: Puppet is still running.
- **Demonstrate (after):** the same command on `56a345c` and `begin_at_step=preparation` is accepted.
- **Status:** needs a cluster (scenario U-01 is the closest). No new spec for the resume path. Not yet demonstrated.

### P0-3 No early check when the target version is older

- **Complaint:** CASE-009. A downgrade through `peadm::upgrade` stopped services first and the installer refused it afterwards. No Jira ticket.
- **Fix:** `3d16bb3`. The plan fails right after reading the installed version, before anything is stopped, and points at restoring from a backup. It does not catch the installer's release-date rule when the version number is higher.
- **Reproduce (before):** run the spec below on `3d16bb3^` with the new spec copied in. It fails because the plan carries on.
- **Demonstrate (after):** `bundle exec rspec spec/plans/upgrade_spec.rb -e 'does not support downgrades'` passes on `3d16bb3`.
- **Scenario:** D-01. **Status:** spec shows it. Not run against a real cluster.

### P0-4 A corrupt or truncated installer tarball is found after services are stopped

- **Complaint:** PE-42686 (related: PE-43373), CASE-049. The extraction step failed partway, after Puppet and PE services were already stopped.
- **Fix:** `d1fc01c`. New private task `peadm::verify_tarball` runs in `preparation` before anything is stopped. It checks the file exists, is not empty, passes `gzip -t`, lists fully with `tar -tf`, and contains `puppet-enterprise-installer`.
- **Reproduce (before):** stage a truncated installer, for example `head -c 1000000 puppet-enterprise-*.tar.gz > bad.tar.gz`, and run the upgrade on `d1fc01c^`. Services stop, then extraction fails.
- **Demonstrate (after):** `bundle exec rspec spec/unit/shell_tasks/verify_tarball_spec.rb` runs the task against good, truncated, empty, wrong-layout and missing archives. The plan-level check is `bundle exec rspec spec/plans/upgrade_spec.rb -e 'tarball'`.
- **Scenario:** U-03. **Status:** spec shows it (the hand-run archive checks became `spec/unit/shell_tasks/verify_tarball_spec.rb` in P1-04). Not run in an acceptance upgrade.

### P0-5 Legacy compiler OID check blocks upgrades for nodes that are not legacy

- **Complaint:** CASE-050, GJira-17. Nodes whose extension is `false` were counted as legacy compilers, so the upgrade stopped with a bare "run the Convert plan".
- **Fix:** `5bd02ea` (fixes GJira-17). `false` is ignored and listed as `ignored_nodes`. The failure message names the nodes and says to run `peadm::convert`.
- **Reproduce (before):** run `bundle exec rspec spec/unit/task/check_pe_master_rules_spec.rb` on `5bd02ea^` with the new spec copied in. The `false`-extension example fails.
- **Demonstrate (after):** the same spec passes on `5bd02ea`. It covers false is ignored, true blocks, and the message names the nodes.
- **Scenario:** U-09. **Status:** demonstrated with the recipe above on 2026-11-10: 5 examples fail on `5bd02ea^` with the new spec, all 26 pass on `5bd02ea`. Not run on a cluster with legacy compilers.

### P0-6 Installer failures show only an exit code

- **Complaint:** CASE-002, CASE-011. `pe-puppetdb` reload failures during upgrade appeared in Bolt as `returned: 6` and a pointer to a log on the node.
- **Fix:** `547e469` (mitigates GJira-1). `pe_install` prints the last 40 lines of the newest installer log and the status of failed `pe-*` units. It does not fix the reload failure.
- **Reproduce (before):** make the installer fail and look at the Bolt output on `547e469^`: exit code and log path only. Or run `bundle exec rspec spec/unit/shell_tasks/pe_install_spec.rb` on `547e469^` with the spec and harness copied in: the report examples fail.
- **Demonstrate (after):** `bundle exec rspec spec/unit/shell_tasks/pe_install_spec.rb` builds a tarball with a fake installer that writes a log and exits 6, stubs `systemctl` to report a failed unit, and asserts the output carries the log tail and the unit status.
- **Scenario:** U-01. **Status:** spec shows it (the hand run became `spec/unit/shell_tasks/pe_install_spec.rb` in P1-04). The report format has since been redacted, see P1-05.

### P0-7 Unsupported-version error does not say what to do

- **Complaint:** PE-47850, CASE-003. Upgrading to a PE release newer than the module knew failed with an unhelpful message, and the range was hardcoded.
- **Fix:** `7f4e82a` (mitigates PE-47850). The range lives in `data/pe_versions.yaml`. The error names the installed peadm version, the supported range, and `permit_unsafe_versions=true`. A release is still needed for each new PE line.
- **Reproduce (before):** `bundle exec rspec spec/functions/assert_supported_pe_version_spec.rb -e 'names the supported range'` on `7f4e82a^` with the new spec copied in fails.
- **Demonstrate (after):** the same spec passes on `7f4e82a`. `spec/functions/supported_pe_versions_spec.rb` covers the data read.
- **Scenario:** U-12. **Status:** spec shows it.

## Phase 1

### P1-05 Installer failure report printed secrets from the installer log

- **Complaint:** found in research while following CASE-002 and CASE-011 (mitigates GJira-1). The P0-6 report printed the last lines of the installer log verbatim, and that log can hold the console admin password, signed-URL signatures, URL userinfo passwords and private keys. Bolt prints task output unredacted, to the operator and to CI logs. No ticket filed.
- **Fix:** the P1-05 commit, extended to `pe_reinstall` by the P1-06 commit and to `reinstall_pe` by the later P1-06 commit of plan 01-05 (one complaint, three installer tasks; ledger rows P1-05 and P1-06). New `files/failure_report.sh` redacts the whole log and then tails it, and `pe_install`, `pe_reinstall` and `reinstall_pe` all use it. `pe_reinstall` is the installer re-run on split-database installs; `reinstall_pe` is the operator's restore helper (documentation/backup_restore.md, test-backup-restore.yaml). Both previously showed only an exit code. Fixes the leak; the underlying reload failure is not touched.
- **Reproduce (before):** run the spec below on the parent of the P1-05 commit with the new spec and harness copied in. The planted-secret example fails because the plain `tail` prints `hunter2-FAKE-SECRET`.
- **Demonstrate (after):** `bundle exec rspec spec/unit/shell_tasks/pe_install_spec.rb spec/unit/shell_tasks/pe_reinstall_spec.rb spec/unit/shell_tasks/reinstall_pe_spec.rb` passes. Each builds a fake installer (`reinstall_pe_spec.rb` packs it in a real tarball behind a stub `curl`), stubs `systemctl`, and asserts the planted values never reach stdout or stderr. For `reinstall_pe`, running its spec on the parent of the plan 01-05 P1-06 commit with the new spec copied in fails 5 of 13 examples (no report, no uninstaller seam).
- **Scenario:** U-01. **Status:** spec shows it. Not run against a real installer failure.

### P1-07 `peadm::code_manager` reported success when the file-sync API call failed

- **Complaint:** found in research (no ticket filed). `code_manager` ran `curl` and threw away its exit code and the HTTP status, so `file-sync commit` returned success even when puppetserver answered HTTP 500 or refused the connection. The install subplan then carried on and DR provisioning failed later with nothing pointing back at the commit.
- **Fix:** the P1-07 commit. `curl_wrapper` now fails the task on a curl error or a non-2xx status and prints the method, URL path, curl exit code, HTTP code, the response body (redacted) and any failed `pe-*` units. Fixes it. Not run on a cluster.
- **Reproduce (before):** run the spec below on the parent of the P1-07 commit with the new spec copied in. The HTTP 500 example `exits non-zero` fails because the old script exits 0 (8 of 18 examples fail there).
- **Demonstrate (after):** `bundle exec rspec spec/unit/shell_tasks/code_manager_spec.rb` passes. The stub `curl` answers HTTP 500 with `{"error":"FAKE"}` and the task exits non-zero naming `POST /file-sync/v1/commit` and `HTTP 500`; a planted `"token":"FAKE-SECRET-tok"` never reaches the output.
- **Scenario:** I-01. **Status:** spec shows it, not run on a cluster. The failing-first run on the unmodified script (8 of 18 examples fail) was done while making the fix.

### P1-08 Readiness waits gave up after a fixed 60 s and printed nothing

- **Complaint:** CASE-029 (cert-loading timeout during a role swap) and the add_replica CI waits documented in `plans/add_replica.pp`. `peadm::wait_until_service_ready` polled 20 times, 3 s apart, with no way to lengthen it, and exited 1 with empty output when the service was still not ready, so a slow node failed on a hard-coded 60 s and the operator saw only "task failed with exit code 1". No Jira ticket filed; related GJira-11 (PE core's own CA query timeouts inside enable) is not fixed here.
- **Fix:** the P1-08 commit (ledger row P1-08). The task takes `timeout` and `interval`, the function takes `$timeout`, and `peadm::add_replica` takes `service_ready_timeout` (default 60, today's behaviour). On expiry the task names the service and URL awaited, the last curl exit code and HTTP code, the redacted response body, any failed `pe-*` units and the redacted tail of the service log. Fixes the silent exit and the fixed deadline for add_replica. The same parameter for `peadm::upgrade` and `peadm::convert` is ledger row P1-09, made in the P1-09 commit: `service_ready_timeout` reaches both orchestrator-service waits in upgrade and all four waits in convert, and the three fixed 120 s `wait_until_available` reconnect waits (two in upgrade, one in convert) become `max(120, $service_ready_timeout)`, so the default keeps 120 s and a larger deadline extends them.
- **Reproduce (before):** on the parent of the P1-08 commit, copy in the new `spec/unit/shell_tasks/wait_until_service_ready_spec.rb` and run it: 11 of its 14 examples fail. By hand with the harness stubs, `curl` answering HTTP 503 makes the old script loop 20 times and exit 1 with empty output.
- **Demonstrate (after):** `bundle exec rspec spec/unit/shell_tasks/wait_until_service_ready_spec.rb spec/plans/add_replica_spec.rb` passes. With `timeout: 9, interval: 3` and a stub `curl` answering 503, the task makes 3 attempts and prints `Timed out after 9s waiting for pe-master on https://localhost:8140/status/v1/simple/pe-master`, `HTTP 503`, the failed unit and the log tail, with a planted `password=FAKE-SECRET-pw` redacted. The add_replica example passes `service_ready_timeout => 300` and sees `timeout => 300` on the `pe-master` wait before the `enable` call. For P1-09, `bundle exec rspec spec/plans/upgrade_spec.rb spec/plans/convert_spec.rb` passes; the new examples pass `service_ready_timeout => 240` with a pcp compiler and see `timeout => 240` on every wait, and a static check confirms every `wait_until_available` uses the `max(120, ...)` form.
- **Scenario:** none yet. **Status:** spec shows it, not run on a cluster.

### P1-11 Tasks failed on nodes whose Puppet host key is not RSA

- **Complaint:** CASE-032 reported RSA-only key parsing in cd4peadm. The same constructor, `OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))`, is in 16 peadm task sites, so on a node whose Puppet host key is EC or Ed25519 each of those tasks fails with `incorrect pkey type`. No Jira ticket filed.
- **Fix:** the P1-11 commit (ledger rows P1-10 and P1-11). `tasks/code_sync_status.rb` now loads the host key through `PeadmCertCheck.load_key` (`OpenSSL::PKey.read`), the shared checker added in P1-10, and its JSON ships the module. Fixes it for `code_sync_status` only; the other 15 sites are listed under "Follow-ups from P1-11" in the change ledger and are not edited.
- **Reproduce (before):** on the parent of the P1-11 commit, copy in the new `spec/unit/task/code_sync_status_spec.rb` and run `bundle exec rspec spec/unit/task/code_sync_status_spec.rb`. The EC-key example raises `incorrect pkey type: id-ecPublicKey` (3 of 13 examples fail there).
- **Demonstrate (after):** `bundle exec rspec spec/unit/task/code_sync_status_spec.rb` passes. The EC example writes a real prime256v1 key to a temp file, points `hostprivkey` at it, and `https_client` builds with that key and `VERIFY_PEER`. To see the checker itself on a real file: `bolt task run peadm::validate_cert cert_path=<cert> key_path=<key> -t <node>` prints `{ok, findings}`.
- **Scenario:** none yet. **Status:** spec shows it for `code_sync_status` only. Not run on a node with an EC host key.

### P1-13 Step names could drift from begin_at_step types, and an invalid step contacted the primary first

- **Complaint:** P0-1 (no ticket filed; related PE-44017, PE-41637): `peadm::convert` named its steps differently from `Peadm::ConvertSteps`, so a resumed run skipped every convert step, and nothing in CI compared the two. Separately, an invalid `begin_at_step` was reported only after the plan had already run a remote `peadm::read_file` on the primary (the default of `node_group_environment`), so an unreachable primary hid the real error.
- **Fix:** the P1-13 and P1-14 commits (ledger rows P1-13 and P1-14). `Peadm::AddDatabaseSteps` replaces the inline `Enum` in `peadm::add_database`, and `spec/unit/step_names_spec.rb` fails when the `peadm::plan_step` names in `upgrade`, `convert` or `add_database` differ from their `Peadm::*Steps` type. `node_group_environment` is resolved in the plan body instead of in the parameter default, so the type error on `begin_at_step` is raised first, listing the valid names. Row P1-13 covers `peadm::add_database` and the drift spec; row P1-14 makes the same change in `peadm::upgrade` and `peadm::convert`. Fixes the invalid-step ordering in all three plans and guards the whole class. Not run on a cluster.
- **Reproduce (before):** on the parent of the P1-13 commit, copy in the new `spec/plans/add_database_spec.rb` and run `bundle exec rspec spec/plans/add_database_spec.rb -e 'rejects an unknown begin_at_step'`. It fails with `Expected peadm::read_file to be called 0 times`, because the old plan read pe.conf from the primary before the step name was checked. For upgrade and convert, on the parent of the P1-14 commit copy in the new `spec/plans/upgrade_spec.rb` and `spec/plans/convert_spec.rb` and run them with `-e 'begin_at_step validation'`: the two bogus-step examples fail with `Unexpected call to 'run_task(peadm::read_file, ["primary"], ...pe.conf)'`.
- **Demonstrate (after):** `bundle exec rspec spec/unit/step_names_spec.rb spec/plans/add_database_spec.rb spec/plans/upgrade_spec.rb spec/plans/convert_spec.rb` passes. To see the guard fire, rename one `peadm::plan_step('...')` in `plans/convert.pp` and run `bundle exec rspec spec/unit/step_names_spec.rb`: the convert example fails showing the two lists. By hand, `bolt plan run peadm::add_database begin_at_step=bogus ...` (likewise `peadm::upgrade` and `peadm::convert`) now ends with `parameter 'begin_at_step' expects a match for Peadm::AddDatabaseSteps = Enum[...]` and no task has run.
- **Scenario:** none yet. **Status:** spec shows it. Not run against a real primary.

### P1-15 peadm::install assumed a production environment

- **Complaint:** PE-39789 and PE-39465 (related PE-46598): peadm assumes a production environment exists. An operator who sets a different environment in `pe_conf_data` (both `pe_install::install::classification::pe_node_group_environment` and `puppet_enterprise::master::recover_configuration::pe_environment`) still got the production `site.pp` stub and file-sync commit from `peadm::install`, so the environment PE classifies into had no committed code.
- **Fix:** the P1-15 commit (ledger row P1-15). `peadm::install` resolves the environment once from `pe_conf_data` (`peadm::get_node_group_environment` now accepts a pe.conf Hash) and passes it to `peadm::subplans::install`, which stubs `environments/<name>/manifests/site.pp`. The new `Peadm::Pe_environment` type rejects a name that is not lowercase letters, digits and underscores before it reaches the path. Fixes the install-path stub. Classifying the PE node groups into that environment is the P1-16 commit.
- **Reproduce (before):** on the parent of the P1-15 commit, copy in the new `spec/plans/subplans/install_spec.rb` and run `bundle exec rspec spec/plans/subplans/install_spec.rb -e 'stubs site.pp in the configured environment'`. The stub path says `environments/production` whatever the operator configured (the parameter does not exist there).
- **Demonstrate (after):** `bundle exec rspec spec/functions/get_node_group_environment_spec.rb spec/plans/subplans/install_spec.rb spec/plans/install_spec.rb` passes. By hand, `bolt plan run peadm::install ... pe_conf_data='{"pe_install::install::classification::pe_node_group_environment":"dev","puppet_enterprise::master::recover_configuration::pe_environment":"dev"}'` stubs `/etc/puppetlabs/code-staging/environments/dev/manifests/site.pp`; the same with `Dev-1` fails at the start naming the name.
- **Scenario:** I-02. **Status:** spec shows it. Cluster run to be recorded by plan 01-13 if done.

### P1-16 Install classified the PE node groups into production even when pe_conf_data named another environment

- **Complaint:** PE-39789 and PE-39465: with `pe_conf_data` naming a non-production environment, `peadm::subplans::configure` still applied `peadm::setup::node_manager` with its default `node_group_environment` of `production`, so the PE node groups that peadm creates at install time were classified into an environment that does not match what PE was installed with. Also related: GJira-11 (readiness waits on slow nodes), which is why `peadm::install` now takes `service_ready_timeout`.
- **Fix:** the P1-16 commit (ledger row P1-16). `peadm::subplans::configure` takes `node_group_environment` and passes it into the `node_manager` class declaration; `peadm::install` forwards the environment it resolved in P1-15. `peadm::install` also takes `service_ready_timeout` (default 60) and passes it to every readiness wait on the install path. Fixes the classification part of PE-39789.
- **Reproduce (before):** on the parent of the P1-16 commit, copy in the new `spec/plans/subplans/configure_spec.rb` and run `bundle exec rspec spec/plans/subplans/configure_spec.rb -e 'is mapped into the peadm::setup::node_manager class declaration'`. It fails because the declaration passes no `node_group_environment`, so the class default applies.
- **Demonstrate (after):** `bundle exec rspec spec/plans/install_spec.rb spec/plans/subplans/configure_spec.rb spec/plans/subplans/install_spec.rb` passes. The static example reads the `node_manager` declaration in `plans/subplans/configure.pp` (BoltSpec cannot see parameters inside an `apply()` block); what the class does with a non-production value is covered by `spec/classes/setup/node_manager_spec.rb`. The install examples pass `service_ready_timeout => 300` and see it, and the environment, reach both subplans.
- **Scenario:** I-02. **Status:** spec shows it, not cluster-verified.

### P1-17 /tmp/pe.conf with the console password stayed on disk after install

- **Complaint:** found in code review (CONCERNS.md; no ticket filed). `peadm::subplans::install` uploaded a `pe.conf` containing `console_admin_password` to `/tmp/pe.conf` on the primary and the PostgreSQL hosts and never removed it, so the password stayed in a shared temp directory after the install, and after a failed install too. `peadm::util::init_db_server` did the same.
- **Fix:** the P1-17 commit (ledger row P1-17). The file is set to mode 0600 right after upload and removed as soon as the last installer run has read it, and also when an installer run fails (the plan then fails with the installer's own error). `peadm::util::init_db_server` does the same and takes a `wait_time` (default 120) for its availability wait. Fixes it. A plan killed mid-run can still leave the file, at mode 0600.
- **Reproduce (before):** after an install on the parent of the P1-17 commit, `ls -l /tmp/pe.conf` on the primary shows the file. Without a cluster, copy the new `spec/plans/subplans/install_spec.rb` and `spec/plans/util/init_db_server_spec.rb` onto the parent and run them with `-e '/tmp/pe.conf'`: the chmod, removal and failing-installer examples fail.
- **Demonstrate (after):** `bundle exec rspec spec/plans/subplans/install_spec.rb spec/plans/util/init_db_server_spec.rb` passes. The examples record every command and installer task in order and assert the chmod comes before the installer, the removal comes after the last one (and before the RBAC token step), and a failing `pe_install` removes the file and fails with Bolt's run-failure. On a cluster, after `peadm::install`, `ls /tmp/pe.conf` on the primary reports no such file (the node check in plan 01-13).
- **Scenario:** I-01. **Status:** spec shows it. Node check pending plan 01-13.

### P1-18 Restore always targeted the production environment

- **Complaint:** PE-46598 (Blocker): backup, restore and migrate need a solution for PE installations whose environment is not production. `puppet-backup restore` defaults to production and takes `--pe-environment` for anything else; `peadm::restore` never passed it, so a cluster classified into another environment was restored as if it were production. Related: PE-39789 and PE-39465 (peadm assumes a production environment).
- **Fix:** the P1-18 commit (ledger row P1-18), then restore_ca and migrate in the P1-19 commit (ledger row P1-19). `peadm::backup` records the environment in `peadm/node_group_environment.json`; `peadm::restore` uses the `node_group_environment` parameter, else that record, else the primary's pe.conf, else production, and adds `--pe-environment=<env>` to every `puppet-backup restore` call when it is not production. `peadm::restore` also takes `service_ready_timeout` (default 60). `peadm::restore_ca` takes the same parameter and falls back to the target's pe.conf (P1-19, ledger row P1-19). `peadm::migrate` reads the old primary's environment, installs the new primary into it (`pe_conf_data` with both environment keys) and restores into it, and takes `service_ready_timeout` (default 60) for install and restore. Fixes the backup, restore, restore_ca and migrate parts of PE-46598.
- **Reproduce (before):** on the parent of the P1-18 commit, copy in the new `spec/plans/restore_spec.rb` and run `bundle exec rspec spec/plans/restore_spec.rb -e 'adds --pe-environment=dev to the recovery restore'`. The plan has no such parameter and ignores the record; the recovery restore command carries no environment. By hand, restore a backup taken on a cluster whose pe.conf sets both environment keys to `dev`: `puppet-backup restore` runs without `--pe-environment` and restores into production.
- **Demonstrate (after):** `bundle exec rspec spec/plans/backup_spec.rb spec/plans/restore_spec.rb spec/plans/restore_ca_spec.rb spec/plans/migrate_spec.rb` passes. The restore examples record every command and show `--force --pe-environment=dev` on the recovery restore and on the ca, code and config restores, no flag for production, and the parameter beating the record; the migrate examples show an old primary on `dev` reaching `peadm::install` as `pe_conf_data` and `peadm::restore` as `node_group_environment`, and production passing neither. By hand, `bolt plan run peadm::restore -t primary input_file=<backup> node_group_environment=staging` prints `# Restoring into the 'staging' environment (from the node_group_environment parameter)` and the `puppet-backup restore` commands carry `--pe-environment=staging`.
- **Scenario:** M-02. **Status:** spec shows it, not run on a cluster. Needs B-01 and M-02 on a non-production cluster.

### P1-20 CA backend detection read only one bootstrap.cfg path

- **Complaint:** GJira-18 shows bootstrap.cfg handling breaking on upgrade (no Jira ticket filed for this change; related PE-47558, the database-backed CA backup and restore). `peadm::backup` and `peadm::restore` each decided whether the CA is database-backed by grepping `/etc/puppetlabs/puppetserver/bootstrap.cfg` alone. PE 2026 / Puppet 9 can lay the service line down in a `services.d` file instead, so a database-backed CA there was taken for a filesystem CA, the pe-ca dump was skipped and a restore left the old CA files next to a different CA database. With no such file the answer was also `filesystem`, silently.
- **Fix:** the P1-20 commit (ledger row P1-20). One private task, `peadm::ca_storage_backend`, checks `bootstrap.cfg` and both `services.d` locations, returns `database`, `filesystem` or `unknown` with the file that matched and the paths checked, and both plans use it. `unknown` (none of the files exists) keeps today's behaviour but prints a WARNING naming the paths. Mitigates: the Puppet 9 layout is covered by what is documented and by specs, and is confirmed on a real PE 2026.0.1 node in plan 01-13.
- **Reproduce (before):** on the parent of the P1-20 commit, a primary whose CA service line is only in `/opt/puppetlabs/server/apps/puppetserver/config/services.d/ca.cfg` is taken for filesystem-backed: `peadm::backup` with only the ca scope runs no pe-ca `pg_dump`. Without a node, run the old inline command on a temp tree: `grep -v '^[[:space:]]*#' /etc/puppetlabs/puppetserver/bootstrap.cfg | grep -q '^[[:space:]]*puppetlabs.services.ca.database-storage-service/' && echo database || echo filesystem` prints `filesystem` when only the `services.d` file has the line.
- **Demonstrate (after):** `bundle exec rspec spec/unit/shell_tasks/ca_storage_backend_spec.rb spec/plans/backup_spec.rb spec/plans/restore_spec.rb` passes. The task spec builds the four layouts under a temp `PEADM_ROOT` and shows `database` with the `services.d` file as `source`. By hand on a primary, `bolt task run peadm::ca_storage_backend -t <primary>` prints the backend, the matched file and the three locations checked.
- **Scenario:** B-01 (backup and restore). **Status:** spec shows it. On-node check on PE 2026.0.1 pending plan 01-13.

### P1-21 Orchestrator and console secret keys were copied world-readable

- **Complaint:** none filed (found in code review, CONCERNS.md). `peadm::util::copy_file` wrote every file it copied with mode 0644, including the orchestration and console encryption key stores under `secrets/` that `peadm::add_replica` and the configure subplan copy to each replica, so any local user on a replica could read them.
- **Fix:** the P1-21 commit (ledger row P1-21). `copy_file` takes an optional `mode`; without one a path with a `/secrets/` directory gets 0600 and anything else 0644, owner and group stay root:root. Fixes the world-readable copies. Whether the replica's PE services can still read the 0600 files before PE's own Puppet run fixes ownership is the open risk, and it is checked, not assumed: plan 01-13's acceptance run adds a replica and verifies the read.
- **Reproduce (before):** on the parent of the P1-21 commit, copy in the new `spec/plans/util/copy_file_spec.rb` and run `bundle exec rspec spec/plans/util/copy_file_spec.rb -e 'copies each secrets/ key store with mode 0600'`. The plan has no mode parameter and passes `mode => '0644'` to `peadm::mkdir_p_file` for the key stores. By hand, after `peadm::add_replica`, `stat -c %a /etc/puppetlabs/console-services/conf.d/secrets/keys.json` on the replica prints `644`.
- **Demonstrate (after):** `bundle exec rspec spec/plans/util/copy_file_spec.rb spec/plans/add_replica_spec.rb spec/plans/subplans/configure_spec.rb` passes. The copy_file examples show `mode => '0600'` for all three key stores, `0644` for `hiera.yaml`, an explicit mode winning, and invalid modes rejected. By hand, the same `stat` on the replica prints `600`, and `systemctl is-active pe-orchestration-services pe-console-services` reports `active` (the replica read check in plan 01-13).
- **Scenario:** P-01. **Status:** spec shows the modes. Replica read check pending plan 01-13; if it fails, plan 01-14 stops at a user decision before any mode change.

### P1-22 The RBAC admin token file followed the umask (often 0644)

- **Complaint:** none filed (found in code review, CONCERNS.md). `peadm::rbac_token` wrote the long-lived admin token to `/root/.puppetlabs/token` with `File.open(path, 'w')`, so its mode followed the umask: world-readable under the usual 022.
- **Fix:** the P1-22 commit (ledger row P1-22). The token file is created 0600, a missing `/root/.puppetlabs` directory 0700, and an existing token file is tightened to 0600 when rewritten. Fixes it.
- **Reproduce (before):** on the parent of the P1-22 commit, `stat -c %a /root/.puppetlabs/token` on a primary after `peadm::install` (or any run of `peadm::rbac_token`) prints `644` under a 022 umask. Without a node, on the parent run `ruby -e 'File.open("/tmp/t", "w") { |f| f.write(1) }; puts File.stat("/tmp/t").mode.to_s(8)' ` under `umask 022`: it prints `100644`, the mode the old open call gave the token file.
- **Demonstrate (after):** `bundle exec rspec spec/unit/task/rbac_token_spec.rb` passes. The examples run the task against a real temp directory and check `File.stat` modes: directory 0700, file 0600 even with umask 000, a pre-existing 0644 file becomes 0600 holding only the new token. By hand on a primary, `stat -c '%a %U' /root/.puppetlabs/token` prints `600 root`.
- **Scenario:** none (covered by the spec; any install scenario shows it on a node). **Status:** spec shows it, not run on a cluster.

### P1-23 A pre-signed installer URL leaked its signature into the upgrade log

- **Complaint:** none filed (found in code review, CONCERNS.md; FND-05 asks for proof that plan output carries no secrets). `peadm::upgrade` logged `pe_installer_source.split('/')[-1]` as the "basename" of the installer URL, which for an S3 pre-signed URL is the file name plus `?X-Amz-Credential=...&X-Amz-Signature=...`. The same split fed the staging and upload paths in `peadm::upgrade` and `peadm::subplans::install`, and the installer directory name derived from it.
- **Fix:** the P1-23 commit (ledger row P1-23). New function `peadm::installer_tarball_name` cuts the URL at `?` and `#` before taking the last path segment; the three derivation sites use it. The download still uses the full URL. Fixes the leak into logs, paths and the directory name. A new spec plants fake secrets and shows none reaches plan output from `peadm::install`, `peadm::subplans::install` or `peadm::upgrade`.
- **Reproduce (before):** on the parent of the P1-23 commit, copy in the new `spec/plans/plan_output_secrets_spec.rb` and run `bundle exec rspec spec/plans/plan_output_secrets_spec.rb -e 'peadm::upgrade'`. The first upgrade example fails with the signature in the `Parameter 'pe_installer_source': [puppet-enterprise-2025.12.1-el-9-x86_64.tar.gz?X-Amz-Credential=FAKE-SECRET-cred&X-Amz-Signature=FAKE-SECRET-sig]` message. By hand, `bolt plan run peadm::upgrade primary_host=<primary> pe_installer_source='https://host/puppet-enterprise-2025.12.1-el-9-x86_64.tar.gz?X-Amz-Signature=abc'` prints that line, signature included.
- **Demonstrate (after):** `bundle exec rspec spec/functions/installer_tarball_name_spec.rb spec/plans/plan_output_secrets_spec.rb spec/plans/upgrade_spec.rb spec/plans/subplans/install_spec.rb spec/plans/install_spec.rb` passes. The upgrade log line reads `Parameter 'pe_installer_source': [puppet-enterprise-2025.12.1-el-9-x86_64.tar.gz]`, the upload path is `/tmp/puppet-enterprise-2025.12.1-el-9-x86_64.tar.gz`, and the download source is still the full signed URL. By hand, the `bolt plan run` above now prints only the file name.
- **Scenario:** U-01. **Status:** spec shows it, not run on a cluster.

## Template

```markdown
### <ID> <one-line complaint>

- **Complaint:** <ticket or case, what the customer saw>
- **Fix:** <commit>, <what changed>. Say whether it fixes or only mitigates.
- **Reproduce (before):** <exact command on <commit>^, and what goes wrong>
- **Demonstrate (after):** <exact command on <commit>, and what you see>
- **Scenario:** <ID in test-scenarios.md, if any>. **Status:** <spec, by hand, or needs a cluster; and whether anyone ran it>
```

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
- **Fix:** the P1-05 commit, extended to `pe_reinstall` by the P1-06 commit (one complaint, two installer tasks; ledger rows P1-05 and P1-06). New `files/failure_report.sh` redacts the whole log and then tails it, and `pe_install` and `pe_reinstall` both use it. `pe_reinstall` is the installer re-run on split-database installs and previously showed only an exit code. Fixes the leak; the underlying reload failure is not touched.
- **Reproduce (before):** run the spec below on the parent of the P1-05 commit with the new spec and harness copied in. The planted-secret example fails because the plain `tail` prints `hunter2-FAKE-SECRET`.
- **Demonstrate (after):** `bundle exec rspec spec/unit/shell_tasks/pe_install_spec.rb spec/unit/shell_tasks/pe_reinstall_spec.rb` passes. It builds a real tarball with a fake installer, stubs `systemctl`, and asserts the planted values never reach stdout or stderr.
- **Scenario:** U-01. **Status:** spec shows it. Not run against a real installer failure.

### P1-07 `peadm::code_manager` reported success when the file-sync API call failed

- **Complaint:** found in research (no ticket filed). `code_manager` ran `curl` and threw away its exit code and the HTTP status, so `file-sync commit` returned success even when puppetserver answered HTTP 500 or refused the connection. The install subplan then carried on and DR provisioning failed later with nothing pointing back at the commit.
- **Fix:** the P1-07 commit. `curl_wrapper` now fails the task on a curl error or a non-2xx status and prints the method, URL path, curl exit code, HTTP code, the response body (redacted) and any failed `pe-*` units. Fixes it. Not run on a cluster.
- **Reproduce (before):** run the spec below on the parent of the P1-07 commit with the new spec copied in. The HTTP 500 example `exits non-zero` fails because the old script exits 0 (8 of 18 examples fail there).
- **Demonstrate (after):** `bundle exec rspec spec/unit/shell_tasks/code_manager_spec.rb` passes. The stub `curl` answers HTTP 500 with `{"error":"FAKE"}` and the task exits non-zero naming `POST /file-sync/v1/commit` and `HTTP 500`; a planted `"token":"FAKE-SECRET-tok"` never reaches the output.
- **Scenario:** I-01. **Status:** spec shows it, not run on a cluster. The failing-first run on the unmodified script (8 of 18 examples fail) was done while making the fix.

## Template

```markdown
### <ID> <one-line complaint>

- **Complaint:** <ticket or case, what the customer saw>
- **Fix:** <commit>, <what changed>. Say whether it fixes or only mitigates.
- **Reproduce (before):** <exact command on <commit>^, and what goes wrong>
- **Demonstrate (after):** <exact command on <commit>, and what you see>
- **Scenario:** <ID in test-scenarios.md, if any>. **Status:** <spec, by hand, or needs a cluster; and whether anyone ran it>
```

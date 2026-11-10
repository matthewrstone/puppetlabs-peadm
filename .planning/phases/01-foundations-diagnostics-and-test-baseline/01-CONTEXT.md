# Phase 1: Foundations, Diagnostics and Test Baseline - Context

**Gathered:** 2026-11-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Operators see why a plan failed; maintainers get the shared helpers (failure report, certificate checker), a current test toolchain, Puppet 9 / Bolt 5 signal lanes, a shell-task test harness and a first acceptance slice that every later phase builds on. Covers FND-01..07, TST-01..06, TRC-01..03. Traceability (ledger, fix log, Jira tickets P0-1..P0-3) is practiced in every later phase too.

</domain>

<decisions>
## Implementation Decisions

### Failure diagnostics and redaction (FND-01, FND-05)
- **D-01:** The failure report (log tail, failed `pe-*` units, exit code) becomes a shared shell helper in `files/task_helper.sh` (or a sibling file sourced the same way). `tasks/pe_install.sh` is refactored onto it, reusing the P0-6 logic.
- **D-02:** Secrets are removed by pattern redaction inside the helper (e.g. `password=`, tokens, `BEGIN ... PRIVATE KEY` blocks, `console_admin_password`, signed-URL query strings). A spec plants fake secrets and asserts none appear in task output or plan output.
- **D-03:** Default output is the last 40 log lines and 15 lines per failed unit, overridable by a task parameter or env var.
- **D-04:** In Phase 1 the helper is adopted by the installer and service-wrapping shell tasks (`pe_install.sh` plus tasks that start, stop or wait on `pe-*` services, such as `wait_until_service_ready.sh` and `code_manager.sh`), not all 19 shell tasks.

### Shared certificate helper (FND-03)
- **D-05:** One Ruby module (stdlib OpenSSL only, under `files/` or `lib/`) does the checks: PEM and DER, RSA and EC keys, chains, expiry, empty subject, CRL. A thin task (`peadm::validate_cert` or similar) wraps it for plans; Ruby tasks require the module directly.
- **D-06:** The checker returns structured findings (severity error/warn, code, message) and the caller decides to fail or warn. This shape is reused as BLOCK/WARN results in Phase 2 preflight and by the Phase 5 CD4PE/SCM plans.
- **D-07:** Adoption in Phase 1 is limited to replacing the RSA-only `PKey.read` site (TST-03). Other cert tasks (`cert_data`, `cert_valid_status`, `sign_csr`, `modify_certificate`) migrate when their phases touch them.

### Test toolchain and CI lanes (TST-01, 02, 03, 05, 06)
- **D-08:** Bump `puppetlabs_spec_helper` to 9, `rspec-puppet` to 5 and pin fixtures to tags in one change on the existing Ruby 3.1 / Puppet 8 lane, fixing fallout in the same plan. Lint baseline must not regress.
- **D-09:** The Puppet 9 lane and the credentialed Bolt 5 lane are informational and non-blocking (continue-on-error). Puppet 8 stays the merge gate. The Bolt 5 lane runs only when the Puppet Core token secret is present.
- **D-10:** The shell-task harness is an RSpec helper that builds a temp dir of stub executables (`systemctl`, `tar`, `puppet-enterprise-installer`, ...), prepends it to PATH, runs the task with `PT_*` env vars and asserts on stdout and exit code. It runs inside `rake spec` and turns the hand-run P0-4 and P0-6 checks into specs.
- **D-11:** `data/pe_versions.yaml` gains a `default` key read via `peadm::supported_pe_versions`; `plans/install.pp` reads it instead of a hardcoded version. A spec asserts `default` lies within `oldest..newest`.

### First acceptance slice (TST-04)
- **D-12:** Topology is a standard architecture, one n to n+1 upgrade on a current pair of PE lines. Large, XL and DR are left to Phases 2 and 4.
- **D-13:** The slice is run manually on the user's own VMs and the results are recorded; no CI wiring in Phase 1. Nightly CI for the newest PE stays in Phase 2 (UPG-07).
- **D-14:** The injected failure for the resume test lives in a test-only plan under `spec/acceptance/peadm_spec/plans/`. No test-only knob is added to `peadm::upgrade`.

### Claude's Discretion
- Environment detection for non-`production` PE environments (FND-02), validation mechanism for `begin_at_step` (FND-04), per-path file modes and the `/tmp/pe.conf` cleanup (FND-06), and the overridable readiness deadline parameter naming and defaults (FND-07). Requirements and codebase maps are clear enough; follow existing conventions (types in `types/`, `fail_plan` heredoc messages).
- Exact scenario IDs and exact PE version pair for the acceptance run; pick from `spec/acceptance/scenarios.yaml` (I-01, U-01 plus a new injected-failure scenario).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project and requirements
- `.planning/ROADMAP.md` — Phase 1 goal and five success criteria
- `.planning/REQUIREMENTS.md` — FND-01..07, TST-01..06, TRC-01..03
- `.planning/STATE.md` — Phase 1 blockers (Bolt 5 binary source, whether peadm runs unchanged on Bolt 5.2 / Puppet Core 9)
- `.planning/research/SUMMARY.md` — Phase 1 rationale and open questions

### Codebase maps
- `.planning/codebase/CONCERNS.md` — secret file modes, `/tmp/pe.conf`, token file mode, duplicated TLS client setup
- `.planning/codebase/TESTING.md` — spec layout, BoltSpec, acceptance setup
- `.planning/codebase/CONVENTIONS.md` — house style for tasks, specs, ledger

### Traceability
- `documentation/change-ledger.md` — add a row per change; tickets to file (P0-1..P0-3)
- `documentation/fix-log.md` — fix entries with reproduce/demonstrate guide
- `documentation/test-scenarios.md` and `spec/acceptance/scenarios.yaml` — scenario catalog for the acceptance slice

### Code touched
- `files/task_helper.sh`, `tasks/pe_install.sh` — failure report helper
- `lib/puppet/functions/peadm/sanitize_log_text.rb` — existing text sanitizer
- `lib/puppet/functions/peadm/supported_pe_versions.rb`, `data/pe_versions.yaml`, `plans/install.pp` — default version
- `spec/acceptance/peadm_spec/plans/` — test-only plans (e.g. `upgrade_test_cluster.pp`)
- `.github/workflows/spec.yml`, `Gemfile`, `.fixtures.yml` — toolchain and CI lanes

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tasks/pe_install.sh` failure report (P0-6): logic to lift into the shared helper
- `peadm::sanitize_log_text`: single-line, length-capped text for plan-side messages
- `peadm::supported_pe_versions`: data-driven version function to extend with `default`
- `spec/unit/task/*_spec.rb` and `RSPEC_UNIT_TEST_MODE` guard pattern for Ruby tasks

### Established Patterns
- Shell tasks source `task_helper.sh` and read `PT_*` params; each task has a `.json` metadata file that must stay in sync
- Every change gets a ledger row and a fix-log entry; commit subjects start with the ticket ID

### Integration Points
- Cert checker connects to the `PKey.read` call site and later to Phase 2 preflight and Phase 5 CD4PE/SCM plans
- Failure helper connects to Phase 2 upgrade resume and cleanup work

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the decisions above; follow existing house conventions.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Wider adoption of the cert helper and failure report is intentionally left to Phases 2 and 5.)

</deferred>

---

*Phase: 1-Foundations, Diagnostics and Test Baseline*
*Context gathered: 2026-11-10*

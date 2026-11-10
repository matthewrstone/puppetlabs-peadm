---
phase: 01-foundations-diagnostics-and-test-baseline
plan: 07
subsystem: testing
tags: [ruby, openssl, certificates, crl, ed25519, ec, bolt-tasks, rspec, change-ledger, fix-log]
status: complete

requires: ["01-06"]
provides:
  - files/cert_check.rb, PeadmCertCheck (stdlib OpenSSL only) with load_key, finding and check; check returns an Array of {severity, code, message, path} findings and never raises on bad input
  - peadm::validate_cert task printing {ok, findings}, exit 0 whenever the checks ran, usage errors as _error of kind peadm/validate_cert-usage with exit 1; key_passphrase is a sensitive parameter
  - tasks/code_sync_status.rb loads the host key through PeadmCertCheck.load_key, so RSA, EC and Ed25519 host keys work
  - SimpleCov tracks files/*.rb (coverage 84.53%, floor 82)
  - Ledger rows P1-10 and P1-11, a "Follow-ups from P1-11" list of the 15 remaining RSA-only sites, fix-log entry P1-11
affects: [01-10, 01-13, 01-14, phase-02-preflight, phase-05-cd4pe-scm]

actuals:
  tokens: 14300
  tasks: 3
  commits: 3
plan_head_before: 194f89e0e94ed8ad452a449f0ce6318f3f576542
plan_head_after: e3c379c371d6ac927170a7f2379686b602348d1e
commits: 3

tech-stack:
  added: []
  patterns:
    - "Shared Ruby library under files/, loaded by tasks with require_relative '../files/cert_check' and shipped by listing peadm/files/cert_check.rb in the task JSON files array"
    - "Checkers return structured findings and the caller decides to fail or warn (D-06); finding codes are stable, new codes are added not renamed"
    - "A String passphrase (empty when none) is always passed to OpenSSL::PKey.read so an encrypted key raises PKeyError instead of Ruby prompting on the TTY"

key-files:
  created:
    - files/cert_check.rb
    - tasks/validate_cert.rb
    - tasks/validate_cert.json
    - spec/unit/task/validate_cert_spec.rb
    - spec/unit/files/cert_check_spec.rb
  modified:
    - tasks/code_sync_status.rb
    - tasks/code_sync_status.json
    - spec/unit/task/code_sync_status_spec.rb
    - spec/spec_helper_local.rb
    - REFERENCE.md
    - documentation/change-ledger.md
    - documentation/fix-log.md

key-decisions:
  - "Three finding codes were added beyond the contract list: chain_unreadable, chain_parse_error and crl_unreadable, so a garbage or missing file in each input yields a matching code (plan behaviour for bad input)"
  - "Chain verification treats self-signed certificates in the chain file as trust anchors and the rest as intermediates; the leaf is verified at a time it is itself valid (clamped to not_after - 1 s), so a leaf's own expiry is reported once by cert_expired, not twice"
  - "cert_revoked is only reported when the CRL issuer equals the certificate issuer; a CRL from another CA gives crl_issuer_mismatch (warn) and no revocation verdict"
  - "A public-only key file is key_parse_error ('holds only a public key'); an encrypted PEM with no or a wrong passphrase is key_encrypted, never echoing the passphrase"
  - "Ed25519 certificates in the spec are signed by an EC issuer: the openssl gem on this Ruby (3.1.0) cannot sign an X509 certificate with an Ed25519 key (nil digest raises TypeError). The Ed25519 subject key is what the checker is tested on"

patterns-established:
  - "A spec file under spec/unit/files/ is named after the file it tests (cert_check_spec.rb), with a rubocop:disable RSpec/SpecFilePathFormat and the reason, as for the task specs"

requirements-completed: [FND-03, TST-03, TRC-01, TRC-02]

coverage:
  - id: D1
    description: "PeadmCertCheck reports structured findings for PEM and DER certificates, RSA/EC/Ed25519 keys, encrypted keys, chains, expiry window, empty subject and CRLs, and never raises on bad input"
    requirement: "FND-03"
    verification:
      - kind: unit
        ref: "bundle exec rspec spec/unit/files/cert_check_spec.rb"
        status: pass
    human_judgment: false
  - id: D2
    description: "peadm::validate_cert prints {ok, findings}, exits 0 when the checks ran, reports usage errors as _error with exit 1, and never prints key material or the passphrase"
    requirement: "FND-03"
    verification:
      - kind: unit
        ref: "bundle exec rspec spec/unit/task/validate_cert_spec.rb"
        status: pass
    human_judgment: false
  - id: D3
    description: "code_sync_status loads RSA, EC and Ed25519 host keys through the shared checker (a real EC key builds the client; the old constructor raised incorrect pkey type)"
    requirement: "TST-03"
    verification:
      - kind: unit
        ref: "bundle exec rspec spec/unit/task/code_sync_status_spec.rb"
        status: pass
    human_judgment: false
  - id: D4
    description: "Bolt ships files/cert_check.rb to a node for validate_cert and code_sync_status, so require_relative '../files/cert_check' resolves there (plan assumption A2)"
    verification: []
    human_judgment: true
    rationale: "Checked only in a checkout and by JSON assertion; needs a real node run, which plan 01-13 does"

duration: 40min
completed: 2026-11-10
---

# Phase 1 Plan 07: Shared certificate, key and CRL checker Summary

**`PeadmCertCheck` (stdlib OpenSSL) returns structured {severity, code, message, path} findings for PEM and DER certificates, RSA/EC/Ed25519 keys, chains, expiry, empty subject and CRLs, is wrapped by the `peadm::validate_cert` task, and replaces the RSA-only host-key load in `code_sync_status` so EC host keys work.**

## Performance

- **Duration:** about 40 min (start time not captured by the executor, estimated)
- **Tasks:** 3 (1 tracer, 2 auto)
- **Files modified:** 12 (5 created)

## Accomplishments

- `files/cert_check.rb`: `load_key` (`OpenSSL::PKey.read`), `finding` and `check`. Findings emitted: `cert_unreadable`, `cert_parse_error`, `cert_expired`, `cert_expires_soon` (warn), `cert_not_yet_valid`, `cert_empty_subject`, `key_unreadable`, `key_parse_error`, `key_encrypted`, `key_mismatch`, `chain_unreadable`, `chain_parse_error`, `chain_unverified` (message carries OpenSSL's error string), `crl_unreadable`, `crl_bad_header` (names `BEGIN X509 CRL`), `crl_parse_error`, `crl_stale` (warn), `crl_issuer_mismatch` (warn), `cert_revoked`.
- `peadm::validate_cert` (`cert_path`, `key_path`, `chain_path`, `crl_path`, `warn_days` default 30, `key_passphrase` sensitive); its JSON ships the module in `files`.
- `code_sync_status` host key now goes through `PeadmCertCheck.load_key`; `VERIFY_PEER`, `ca_file` and memoisation are unchanged; its JSON ships the module.
- Specs use real generated material only (no OpenSSL stubbing): a root, intermediate and leaf, DER and PEM, RSA, EC and Ed25519 keys, encrypted keys, stale and revoked CRLs, garbage and unreadable files per input. 32 examples in `cert_check_spec.rb` (one mutation, replacing the chain verify time with `now`, was confirmed to fail the "expired leaf reported once" example), 9 in `validate_cert_spec.rb`, 2 new in `code_sync_status_spec.rb` (3 of the file's 13 fail with the old RSA constructor, including `incorrect pkey type: id-ecPublicKey`).
- Ledger P1-10 and P1-11, the "Follow-ups from P1-11" list (15 RSA-only sites by file:line, plus the `OpenSSL::PKey::RSAError` rescue at `tasks/list_compiler_icas.rb:122` to widen when migrating, plus the `VERIFY_NONE` at `tasks/check_legacy_compilers.rb:53`), fix-log P1-11. REFERENCE.md regenerated with `rake strings:generate:reference`.

## Task Commits

1. **Task 1 (tracer): validate_cert over a minimal PeadmCertCheck, proven on an EC key and certificate** - `c87e2c7` (P1-10)
2. **Task 2: DER, Ed25519, encrypted keys, chains, expiry window, empty subject and CRLs** - `f27f284` (P1-10)
3. **Task 3: code_sync_status loads the host key through the checker** - `e3c379c` (P1-11)

The tracer gate ran in end-of-phase mode with an automated-only `<verify>`; the verify had passed end to end, then expansion proceeded.

## Verification

- `bundle exec rake parallel_spec`: 686 examples, 0 failures, 6 pending.
- `bundle exec rake spec:simplecov`: Line Coverage 84.53% (1038 / 1228), floor 82, with `files/*.rb` now tracked.
- `bundle exec rake validate lint check rubocop`: exit 0, 123 files, no RuboCop offenses.
- `bundle exec rake strings:validate:reference`: exit 0.
- Task verify commands: all three passed (RuboCop, JSON `files`/`sensitive` assertion, ledger rows, finding-code grep, no `PKey::RSA` left in `code_sync_status.rb`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Ed25519 certificate in the spec is signed by an EC issuer**
- **Found during:** Task 2
- **Issue:** the plan's behaviour list needs an Ed25519 key to load; the spec first built a self-signed Ed25519 certificate, but the openssl gem on this machine (3.1.0, Ruby 3.2.3) cannot sign a certificate with an Ed25519 key (`cert.sign(key, nil)` raises TypeError, an explicit digest raises "invalid digest").
- **Fix:** the Ed25519 certificate has the Ed25519 subject key and is signed by the EC root. The checker code path under test (`load_key`, the `private_to_der` private-part test, `check_private_key`) is unchanged by this.
- **Files modified:** `spec/unit/files/cert_check_spec.rb`
- **Commit:** f27f284

**2. [Rule 1 - Bug] Leaf expiry was reported twice when a chain was supplied**
- **Found during:** Task 2
- **Issue:** with a chain, an expired leaf produced both `cert_expired` and `chain_unverified` ("certificate has expired"). OpenSSL also treats the second of `not_after` itself as expired.
- **Fix:** the chain is verified at `[[now, not_before].max, not_after - 1].min`, a time the leaf is valid, so its own expiry is reported once and `chain_unverified` is about the chain (an expired intermediate is still reported there). The spec's CA certificates start three years back so a leaf that expired last week was issued inside its issuer's window.
- **Files modified:** `files/cert_check.rb`, `spec/unit/files/cert_check_spec.rb`
- **Commit:** f27f284

**3. [Rule 2 - Missing critical functionality] Extra finding codes**
- Added `chain_unreadable`, `chain_parse_error` and `crl_unreadable` so every input (certificate, key, chain, CRL) maps garbage and missing files to a code instead of raising, as the plan's last behaviour line requires; the plan's code list named only some of them. Recorded in the ledger row.

**Total deviations:** 3 auto-fixed (1 blocking, 1 bug, 1 missing functionality). **Impact:** none on scope; contract codes unchanged, three added.

## Authentication Gates

None.

## Known Stubs

None.

## Threat Flags

None. The new task reads operator-chosen file paths and returns findings only (T-01-15, accepted); `key_passphrase` is a sensitive parameter and a spec asserts neither it nor key bytes reach output (T-01-14); chain verification uses `X509::Store#verify` (T-01-13).

## Issues Encountered

- Unit coverage only. `validate_cert` and the `code_sync_status` change were not run through Bolt on a node, so assumption A2 (Bolt installs `peadm/files/cert_check.rb` beside the task so `require_relative '../files/cert_check'` resolves) is still unconfirmed on a real node; plan 01-13 does that.
- `Ruby 3.2.3` is the local interpreter although the repo floor is 3.3; the specs avoid version-specific OpenSSL behaviour except the Ed25519 signing note above.

## Next Phase Readiness

Ready for plan 01-08. Phase 2 preflight and Phase 5 plans can consume `PeadmCertCheck.check` and the findings shape. The 15 RSA-only sites in the change ledger's "Follow-ups from P1-11" list migrate when later phases touch those tasks.

## Self-Check: PASSED

- Created files present: `files/cert_check.rb`, `tasks/validate_cert.rb`, `tasks/validate_cert.json`, `spec/unit/task/validate_cert_spec.rb`, `spec/unit/files/cert_check_spec.rb`.
- Commits `c87e2c7`, `f27f284`, `e3c379c` are ancestors of HEAD; `git rev-list --count` from the recorded base gives 3.

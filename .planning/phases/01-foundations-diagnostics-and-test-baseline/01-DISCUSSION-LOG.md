# Phase 1: Foundations, Diagnostics and Test Baseline - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-10
**Phase:** 1-Foundations, Diagnostics and Test Baseline
**Areas discussed:** Failure diagnostics + redaction, Shared certificate helper, Toolchain + Puppet 9/Bolt 5 lanes, First acceptance slice

---

## Failure diagnostics + redaction

| Question | Options | Selected |
|---|---|---|
| Where diagnostics live | Shared shell helper / Per-task copies / Plan-side collection | Shared shell helper |
| Secret handling | Pattern redaction / Allowlist only / Pattern + unit allowlist | Pattern redaction in helper |
| Output size | 40 lines overridable / 200 lines / You decide | 40 lines, overridable |
| Task scope | Installer + service-wrapping / pe_install only / All shell tasks | Installer and service-wrapping shell tasks |

## Shared certificate helper

| Question | Options | Selected |
|---|---|---|
| Form | Ruby lib + thin task / Task only / Puppet function | Ruby lib + thin task |
| Result shape | Structured findings / Raise on first problem | Structured findings |
| Adoption | Fix PKey.read only / Migrate all cert tasks / Helper only | Fix PKey.read site only |

## Toolchain + Puppet 9/Bolt 5 lanes

| Question | Options | Selected |
|---|---|---|
| Gem bump | One change / Staged | One change, fix fallout |
| CI lanes | Informational / P9 blocking / Both blocking | Informational, non-blocking |
| Shell harness | RSpec stub-PATH helper / bats | RSpec helper |
| Default PE version | `default` key in data file / always newest / You decide | `default` key |

## First acceptance slice

| Question | Options | Selected |
|---|---|---|
| Topology | Standard / Standard + DR / XL | Standard, n to n+1 |
| Where it runs | GitHub workflows manual / Local VMs / Nightly | Local/manual on own VMs (user chose over the recommended option) |
| Failure injection | Test-only plan / Hook in upgrade | Test-only plan |

## Claude's Discretion

Environment detection (FND-02), `begin_at_step` validation (FND-04), file modes (FND-06), readiness deadline naming (FND-07), exact PE version pair and scenario IDs.

## Deferred Ideas

None.

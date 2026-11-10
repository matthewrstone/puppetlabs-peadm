---
last_mapped_commit: e36923acdd0c8f080d9afc874fb38d5ab3a8db97
last_mapped_at: 2026-11-10
---
# Coding Conventions

**Analysis Date:** 2026-11-10

## Naming Patterns

**Files:**
- Puppet plans, functions, classes, types, and tasks use `snake_case.pp` / `snake_case.rb` / `snake_case.json` / `snake_case.sh`. Examples: `plans/install.pp`, `plans/subplans/configure.pp`, `functions/get_targets.pp`, `types/singletargetspec.pp`, `tasks/get_peadm_config.rb`, `tasks/pe_install.sh`.
- Every Bolt task is a pair: `tasks/<name>.json` (metadata/parameters) plus one or more implementations, e.g. `tasks/pe_install.json` with `tasks/pe_install.sh`, or `tasks/get_peadm_config.json` with `tasks/get_peadm_config.rb`. The `json` file is the source of truth for the task's parameter schema.
- Ruby unit specs are named after the file they test, not the class: `tasks/get_peadm_config.rb` -> `spec/unit/task/get_peadm_config_spec.rb`. The `spec/unit/task/sign_csr_spec.rb` and `ssl_clean_spec.rb` files follow the same house rule. Do not "fix" these to RuboCop's derived name; `spec/unit/task/get_peadm_config_spec.rb` carries `# rubocop:disable RSpec/SpecFilePathFormat` for this reason.
- Function spec files: `spec/functions/<function_name>_spec.rb` (e.g. `spec/functions/certname_spec.rb`). Plan spec files: `spec/plans/<plan_name>_spec.rb`, with subplans under `spec/plans/subplans/` and utilities under `spec/plans/util/`.

**Puppet names:**
- Module namespace is `peadm`. Plans are `peadm::install`, subplans `peadm::subplans::install`, utility plans `peadm::util::copy_file`, and internal classes `peadm::setup::node_manager`.
- Puppet functions implemented in Ruby use lowercase namespaced names: `peadm::plan_step` in `lib/puppet/functions/peadm/plan_step.rb` (class registered via `Puppet::Functions.create_function(:'peadm::plan_step')`).
- Puppet-language functions in `functions/*.pp` are `function peadm::<name>(...)`, with the filename matching the function name.
- Types are capitalized and namespaced: `Peadm::SingleTargetSpec` (`types/singletargetspec.pp`), `Peadm::Pe_version` (`types/pe_version.pp`), `Peadm::Ldap_config`, `Peadm::Known_hosts`, `Peadm::Pem`. Type-alias names inside a file use `Peadm::` followed by `Snake_case` segments for multi-word names (`Peadm::Pe_version`), which is the prevailing style; follow the neighbouring file rather than inventing a new casing.
- Plan parameters are `snake_case`. Parameter groups are annotated with comments, e.g. `# Standard`, `# Large`, `# Extra Large`, `# Cloud Database`, `# Code Manager`, `# License Key`, `# Common Configuration` in `plans/install.pp`.
- Ruby classes are `UpperCamelCase` and match the task name (`GetPEAdmConfig` in `tasks/get_peadm_config.rb`), with nested helper classes such as `GetPEAdmConfig::NodeGroup`.
- Ruby methods and locals are `snake_case`. Ruby instance variables used for memoisation are `@groups ||= ...`, `@compilers ||= ...`.
- Classifier node-group names are used verbatim as string keys in Ruby (`'PE Primary A'`, `'PE Certificate Authority'`, `'PE HA Replica'`); do not abbreviate them.
- Certificate extension OIDs live in `functions/oid.pp` and are used through `peadm::oid('peadm_role')` in Puppet. The raw OIDs (`1.3.6.1.4.1.34380.1.1.9812`, `...9813`) appear in Ruby (`tasks/get_peadm_config.rb`) and in specs; prefer `peadm::oid` in Puppet code.

**Variables:**
- Puppet variables are `$snake_case`, always prefixed with `$`. Local variables inside plans are often named after the target they hold: `$primary_target`, `$source_target`, `$replica_target` (`plans/util/copy_file.pp`).
- Puppet `Optional[...]` parameters default to `undef`, and empty-hash parameters default to `{}` (e.g. `Optional[Hash] $pe_conf_data = {}` in `plans/install.pp`).
- Ruby constants are `SCREAMING_SNAKE_CASE` (`CATALOG`, `DOC`, `CONCRETE`, `STATUSES` in `spec/acceptance/scenarios.rb`).

**Functions (Ruby):**
- Plain `snake_case` method names. Helper methods that query the environment are named for what they return: `pe_version`, `groups`, `compilers`, `legacy_compilers`, `pdb_query`, `https(port)`.

**Hash keys and task output:**
- Task JSON output uses string keys, not symbols: `{ 'pe_version' => ..., 'params' => {...} }`. Keys that are human-facing and hyphenated are allowed (`'role-letter'` in `tasks/get_peadm_config.rb`), but that is the exception; prefer `snake_case`.

## Code Style

**Puppet formatting:**
- Two-space indentation. Parameter lists are aligned in columns: type, name, default, with `=` aligned (see `plans/install.pp`).
- Trailing commas are used in multi-line argument and array lists; see the `case` blocks in `functions/certname.pp` and the `Variant[...]` list in `functions/get_targets.pp`.
- Puppet-lint runs with `strict_indent` and `manifest_whitespace_missing_newline_end_of_file` disabled via `.sync.yml` (`default_disabled_lint_checks`). Do not re-enable them as a side effect of editing.
- Long multi-line strings in Puppet use heredoc-style `@("EOL"/L)` ... `| EOL` syntax, with an explicit `# lint:ignore:strict_indent` / `# lint:endignore` wrapper when indentation must be preserved. See `plans/convert.pp` (around lines 137-146) for the canonical example.
- Puppet-lint suppressions use `# lint:ignore:<check>` and `# lint:endignore` pairs and are used deliberately (`unquoted_string_in_case` in `functions/certname.pp`, `strict_indent` in `plans/convert.pp`). Keep suppressions narrow and in place.

**Ruby formatting:**
- RuboCop `1.79.0` with `rubocop-performance`, `rubocop-rspec`, `rubocop-rspec_rails`, `rubocop-factory_bot`, and `rubocop-capybara` plugins, configured in `.rubocop.yml`. `TargetRubyVersion` is `2.7`; the repo's `.ruby-version` is `3.1.0`.
- Max line length is 200 (`Layout/LineLength` in `.rubocop.yml`).
- `Style/FormatString` is `percent` (use `'%s' % x` or `format`), `Style/FormatStringToken` is `template`, `Style/Lambda` is `literal`, `Style/RegexpLiteral` is `percent_r` (use `%r{...}` for regexes containing slashes, as in `spec/acceptance/scenarios.rb`).
- Trailing commas in multi-line argument and array literals are required (`Style/TrailingCommaInArguments`, `Style/TrailingCommaInArrayLiteral` set to `comma`).
- Braces are used for chained blocks (`Style/BlockDelimiters: braces_for_chaining`).
- `Style/ClassAndModuleChildren` is `compact`: write `class Foo::Bar`, not nested `module Foo; class Bar`.
- `Style/SymbolArray` is `brackets`, `Style/WordArray` is `brackets`: write `['a', 'b']` and `[:a, :b]`, not `%w[]`/`%i[]`.
- `frozen_string_literal: true` appears on the top of newer Ruby files (`lib/puppet/functions/peadm/plan_step.rb`, `tasks/get_peadm_config.rb`, all `spec/functions/*_spec.rb` shown). It is not universal across `tasks/`; when editing a file, match its existing header. New files should include it.
- Metrics cops (`Metrics/*`, `Naming/MethodParameterName`, etc.) are disabled, so long methods are acceptable where the work is naturally sequential (e.g. `GetPEAdmConfig#config`).

**Shell task formatting:**
- Shell tasks start with `#!/bin/bash` and source the shared helper with `source "$(dirname $0)/../../peadm/files/task_helper.sh"` (`tasks/pe_install.sh`). Parameters arrive as `PT_<name>` environment variables (`if [ "$PT_install_extra_large" = "true" ]`), per the `input_method: environment` metadata in `tasks/pe_install.json`.
- Tab-indented heredocs (`<<-EOF`) are used for generated config (`tasks/pe_install.sh`).

**Linting:**
- Puppet: `puppet-lint` via `pdk`/Rakefile, with `voxpupuli-puppet-lint-plugins ~> 5.0` and `metadata-json-lint ~> 3.0` in the Gemfile. Plans are excluded from `PuppetSyntax` checks (`.sync.yml` `PuppetSyntax.exclude_paths` includes `plans/**/*.pp`).
- Ruby: RuboCop, configured by `.rubocop.yml`. `.rubocop_todo.yml` is nearly empty (generated 2023-09-05 from RuboCop 1.48.1, and only holds a few residual suppressions).
- Run: `bundle exec rake validate lint check rubocop` (as in `.gitlab-ci.yml`).

## Import Organization

**Ruby `require` order:**
1. `spec_helper` / standard library (`require 'json'`, `require 'uri'`, `require 'net/http'`, `require 'puppet'`) at the top of `tasks/get_peadm_config.rb`.
2. In specs: `require 'spec_helper'` first, then `require_relative` for the code under test (`spec/unit/task/get_peadm_config_spec.rb`).
3. Specs that need the acceptance scenario catalog use `require_relative '../acceptance/scenarios'` (`spec/unit/peadm_scenarios_spec.rb`).

**Puppet:**
- Puppet has no import statement. Dependencies are resolved by module name: `peadm::...`, `out::message`, `run_task`, `run_command`, `get_targets` (Bolt built-in), and stdlib functions. Reference a helper by its full name and do not inline a copy of it.

**Path Aliases:**
- Not used. Puppet references the module as `peadm`; Ruby uses `require_relative` from spec files and relative paths in task files.

## Error Handling

**Puppet plans:**
- Fail a plan with `fail_plan(...)`, not `fail()`, when the failure is an operator-facing condition. 29 `fail_plan` calls exist across `plans/`. The message is usually a heredoc (`@("EOL"/L)`) that explains the situation and the detected values, e.g. `plans/convert.pp` reports the detected PE version and the reason conversion is refused.
- For a task run that may fail but whose failure the plan should handle, pass `_catch_errors => true` (21 occurrences in `plans/`) and inspect the returned `ResultSet` (`$result.ok`, `$result.first.error`). Do not let an expected-failure task abort the plan silently.
- Retry loops use an explicit attempt counter and a `out::message` line per attempt, e.g. `plans/subplans/install.pp` line ~466: `out::message("rbac_token not ready (${rbac_token_prior_error}); retrying (attempt ${attempt}) after ${rbac_token_retry_delay}s...")`.
- Validation of user input happens in the parameter type, not in the body: `Peadm::Pe_version` (`types/pe_version.pp`) is a `Pattern`, `Peadm::SingleTargetSpec` (`types/singletargetspec.pp`) constrains a target to one host, and `Peadm::Known_hosts`, `Peadm::Pem`, `Peadm::Ldap_config`, `Peadm::Recovery_opts` are other examples. Add new constraints to `types/` rather than duplicating checks in plan bodies.

**Ruby tasks:**
- Tasks write machine-readable JSON to STDOUT. Errors are reported as `{ 'error' => '...' }` JSON, not as a raised exception, when the caller is expected to parse the result: `puts({ 'error' => 'This is not a peadm-compatible cluster. Use peadm::convert first.' }.to_json)` in `tasks/get_peadm_config.rb`, and `puts JSON.pretty_generate({ 'error' => ... })` in `tasks/get_group_rules.rb`.
- Specific exceptions are rescued and re-raised with context. Pattern from `tasks/check_pe_master_rules.rb` (lines ~29-55): `raise "Failed to fetch groups: HTTP #{res.code} - #{res.body}"`, `rescue JSON::ParserError => e` then `raise "Invalid JSON response from server: #{e.message}"`, with a final `rescue StandardError => e` as a catch-all.
- Rescue specific classes where they exist (`Puppet::SSL::CertVerifyError`, `Puppet::Error` in `tasks/cert_valid_status.rb`); reserve `StandardError` for the outermost layer.
- Diagnostics to STDERR use `warn`/`STDERR.puts` and are reserved for caller bugs (e.g. an unexpected type for a parameter) that must not look like a valid "no-op" result. See `spec/unit/task/check_legacy_compilers_spec.rb`, which asserts the STDERR diagnostic for a non-String, non-nil parameter.

**Puppet functions (Ruby):**
- Validate with the dispatch signature (`dispatch :plan_step do ... param 'String', :step_name ... end`) rather than manual checks.

**Puppet functions (Puppet language):**
- Use `case` on the input type (`Target`, `String`, `Undef`, `Array[...]`) and `fail('Unexpected input type to peadm::certname function')` in the `default:` arm (`functions/certname.pp`).

## Logging

**Plans:**
- Use `out::message("...")` for all operator-visible progress. 24 plan files use it. Messages are in sentence case and often include the step or the retry count: `out::message('Completing the Certificate Authority database storage migration (puppet_enterprise::ca_storage_import)...')`.
- Gate step-level output with `plan_step('<name>') { ... }` (`lib/puppet/functions/peadm/plan_step.rb`). It prints `# Plan Step: <name>` and supports `begin_at_step` to skip earlier steps during a resumed run.
- Use `out::message` (not `out::verbose`) for information an operator needs to see even when the install is running on a PE version where the step is unusual, as in `plans/subplans/install.pp` around line 610.

**Ruby tasks:**
- Tasks do not log to a framework. Their stdout is JSON that Bolt parses, so do not print diagnostics to STDOUT. Use STDERR for diagnostics.
- Tasks that run during tests must be guarded so they do not auto-execute. Pattern: `unless ENV['RSPEC_UNIT_TEST_MODE']` wraps the bottom-of-file execution (`tasks/get_peadm_config.rb`, `tasks/check_legacy_compilers.rb`, `tasks/cert_data.rb`, `tasks/cert_valid_status.rb`).

## Comments

**When to Comment:**
- Explain *why* a non-obvious workaround exists, and name the ticket or the upstream issue when there is one. Examples: the `# PE-45737` / `# PE-46426` notes in `spec/spec_helper_local.rb`, and the i18n and Ruby 4.0 notes in the `Gemfile` (`# i18n >= 1.15.0 uses Fiber[] ...`).
- Explain the reason for a PuppetDB query shape. `tasks/get_peadm_config.rb` documents why `server()` returns early on an empty candidate list: PuppetDB's PQL parser rejects `certname in []`.
- Puppet-lint and RuboCop suppressions are always accompanied by a reason comment (`spec/unit/task/get_peadm_config_spec.rb`: `# rubocop:disable RSpec/SpecFilePathFormat` is explained immediately above it).

**Puppet doc comments:**
- Every public plan, class, and function starts with a `# @summary` line and, for plans and classes, a `# @param <name>` block for each parameter. Example: `plans/install.pp` documents all parameters, including `cloud_database_host`, in `@param` blocks. 40 files carry `@summary`. Wording of `@param` blocks is indented two spaces under the tag.
- Mark internal-only classes and plans with `# @api private`, as in `plans/util/copy_file.pp` and `manifests/setup/node_manager.pp`.
- Functions use `# @summary` followed by prose describing the accepted inputs and return values (`functions/certname.pp`).

**Ruby doc comments:**
- Use YARD-style `# @return [Type] description` on helper methods that return something non-obvious (`tasks/get_peadm_config.rb`, `pe_version`).
- Document private helper classes with a one-line comment (`# Utility class to aid in retrieving useful information from the node group data`).

**Test comments:**
- Spec `it` blocks often carry a mutation-testing comment in the form `# Catches a mutation that ...`. These explain the regression the example guards against. Keep this style when adding examples to existing specs (see `spec/unit/task/get_peadm_config_spec.rb`).

## Function Design

**Size:** Puppet plans can be long (the top-level `plans/install.pp` is large) but delegate work to `plans/subplans/*.pp` and `plans/util/*.pp`. Keep new logic in a subplan or util plan if it is reused, and inline only when it is used once.

**Parameters:**
- Puppet: typed, named parameters with defaults. Use `Optional[T] $x = undef` for optional values. Use `TargetSpec` for Bolt-accepted target lists and `Peadm::SingleTargetSpec` when exactly one target is required.
- Ruby tasks: a single `params` hash via `initialize(params)`; by design the current task classes take no meaningful task-level params (see the comment in `spec/unit/task/get_peadm_config_spec.rb`).

**Return Values:**
- Plans return `ResultSet`s from `run_task` / `run_command`, or a plain value. Read the result with `.first`, `.ok`, `['key']`, e.g. `run_task('peadm::read_file', ...).first['content']` in `plans/util/copy_file.pp`.
- Ruby tasks print JSON to STDOUT and return nothing meaningful.

**Target handling:**
- Normalise any incoming target spec with `peadm::get_targets($spec, 1)` (`functions/get_targets.pp`) before using it. Obtain a certname with `$target.peadm::certname()` (`functions/certname.pp`), not by string-munging.

## Module Design

**Exports:**
- Public surface: plans in `plans/` (`peadm::install`, `peadm::upgrade`, `peadm::convert`, ...), tasks in `tasks/`, functions in `functions/` and `lib/puppet/functions/peadm/`, types in `types/`. Items in `plans/subplans/`, `plans/util/`, and `manifests/setup/` are internal; mark them `@api private`.

**Barrel Files:**
- Not used. Puppet and Bolt discover content by directory and name, so no index file is needed or expected.

**Task metadata:**
- Each task's `.json` lists every parameter with a Puppet type string (`"type": "Optional[Boolean]"`) and a `description`. Keep the JSON in sync with the implementation when parameters change, because Bolt validates inputs against it.

---

*Convention analysis: 2026-11-10*

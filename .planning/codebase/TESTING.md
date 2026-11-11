---
last_mapped_commit: e36923acdd0c8f080d9afc874fb38d5ab3a8db97
last_mapped_at: 2026-11-10
---
# Testing Patterns

**Analysis Date:** 2026-11-10

## Test Framework

**Runner:**
- RSpec (Ruby) with `puppetlabs_spec_helper ~> 6.0`, `rspec-puppet`, and `rspec-puppet-facts ~> 2.0` (`Gemfile`, development group).
- Config: `.rspec` (`--relative`, `--color`, `--format documentation`), `spec/spec_helper.rb`, `spec/spec_helper_local.rb`.
- Plan testing via `bolt_spec` (`BoltSpec::Plans`, initialised in `spec/spec_helper_local.rb` with `BoltSpec::Plans.init`).
- Acceptance: `puppet_litmus ~> 2.0` (`system_tests` Gemfile group), config in `spec/spec_helper_acceptance.rb` and `spec/spec_helper_acceptance_local.rb`.
- Lint/static checks in the same pipeline: RuboCop `1.79.0` (`.rubocop.yml`), `puppet-lint` via `voxpupuli-puppet-lint-plugins ~> 5.0`, `metadata-json-lint`, `puppet-syntax`.

**Assertion Library:**
- RSpec built-in `expect(...).to` matchers. Mocks use `rspec-mocks` (`mock_with :rspec` in `spec/spec_helper.rb`). Doubles use `instance_double(Net::HTTP)` (verified doubles) where possible (e.g. `spec/unit/task/check_legacy_compilers_spec.rb`).
- Puppet-level assertions use rspec-puppet matchers (`is_expected.to compile`, `with_*`, `run.with_params(...).and_return(...)` for functions).
- Plan assertions use BoltSpec matchers: `expect_plan`, `expect_task`, `expect_command`, `expect_out_message`, `allow_out_message`, `run_plan`.

**Run Commands:**
```bash
bundle exec rake spec                 # Run all specs (sequential)
bundle exec rake parallel_spec        # Run all specs in parallel (as CI does)
bundle exec rspec spec/unit/task/get_peadm_config_spec.rb   # Single file
bundle exec rake spec:simplecov       # Run with SimpleCov (SIMPLECOV=yes); writes coverage/index.html
bundle exec rake validate lint check rubocop   # Syntax, lint, metadata and RuboCop checks
bundle exec rake spec_prep            # Fetch fixtures (see .fixtures.yml)
```

Local setup notes (Ruby 3.1 is pinned by `.ruby-version`): the Gemfile pins `json`, `racc`, `i18n` and Ruby-4-era default gems by Ruby version, so use `bundle install` under the matching Ruby rather than a global gem set. `.github/workflows/spec.yml` runs the Spec job and a separate Coverage job gated by path filters.

## Test File Organization

**Location:**
- All tests live under `spec/`, separate from source. Specs are not co-located with the code they test.
- Fixtures are materialised into `spec/fixtures/` by `rake spec_prep` from `.fixtures.yml`. `spec/fixtures/modules/peadm` is a symlink back to the repo root (`peadm: '#{source_dir}'`), and `peadm_spec` symlinks to `spec/acceptance/peadm_spec`. `spec/fixtures/modules/*` is gitignored and holds vendored third-party modules (stdlib, facts, provision, etc.); treat these as dependencies and do not edit them.

**Naming:**
- `*_spec.rb` for everything. File names mirror the implementation: `spec/functions/certname_spec.rb` for `functions/certname.pp`; `spec/plans/install_spec.rb` for `plans/install.pp`; `spec/plans/subplans/configure_spec.rb` for `plans/subplans/configure.pp`; `spec/plans/util/*_spec.rb` for `plans/util/*.pp`.
- Task spec filenames follow the task file name, not the Ruby class name (`spec/unit/task/get_peadm_config_spec.rb` for `tasks/get_peadm_config.rb`). This is a deliberate house convention.

**Structure:**
```
spec/
├── spec_helper.rb                  # Puppet/rspec-puppet setup, resource coverage floor (90)
├── spec_helper_local.rb            # BoltSpec init, SimpleCov floor (82), extra coverage formatters
├── spec_helper_acceptance*.rb      # Litmus acceptance setup
├── default_facts.yml               # Default facts merged into every rspec-puppet example
├── classes/setup/                  # rspec-puppet class specs (node_manager_spec.rb)
├── functions/                      # Puppet and Ruby function specs (22 files)
├── plans/                          # BoltSpec plan specs
│   ├── subplans/                   # Subplan specs
│   ├── util/                       # Util plan specs
│   └── misc/                       # Miscellaneous plan specs
├── unit/
│   ├── peadm_scenarios_spec.rb     # Validates acceptance scenario catalog and docs sync
│   └── task/                       # Ruby task unit specs (23 files)
├── acceptance/                     # Litmus acceptance tests, scenarios.yaml, peadm_spec module
│   └── peadm_spec/                 # Bolt plans/tasks used by acceptance runs
└── fixtures/                       # Gitignored vendored modules (dependencies only)
```

## Test Structure

**Suite Organization (Ruby task spec):**
```ruby
require 'spec_helper'
require_relative '../../../tasks/get_peadm_config'

describe GetPEAdmConfig do
  let(:task) { described_class.new({}) }

  describe GetPEAdmConfig::NodeGroup do
    subject(:node_group) { described_class.new(data) }

    let(:data) do
      [
        { 'name' => 'PE Master', 'rule' => ['and'] },
        # ...
      ]
    end

    describe '#dig' do
      it 'returns nil when no group matches the name' do
        expect(node_group.dig('Nonexistent Group')).to be_nil
      end
    end
  end
end
```
Source: `spec/unit/task/get_peadm_config_spec.rb`.

**Suite Organization (Puppet function spec):**
```ruby
require 'spec_helper'

describe 'peadm::certname' do
  include BoltSpec::BoltContext
  around(:each) do |example|
    in_bolt_context do
      example.run
    end
  end
  let(:target) do
    ['test-vm.puppet.vm']
  end

  it { is_expected.to run.with_params(target).and_return('test-vm.puppet.vm') }
end
```
Source: `spec/functions/certname_spec.rb`.

**Suite Organization (Plan spec):**
```ruby
require 'spec_helper'

describe 'peadm::install' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    it 'runs successfully with the minimum required parameters' do
      allow_out_message
      expect_plan('peadm::subplans::install')
      expect_plan('peadm::subplans::configure')
      expect(run_plan('peadm::install', 'primary_host' => 'primary', 'console_password' => 'puppetLabs123!', 'version' => '2021.7.9')).to be_ok
    end
  end
end
```
Source: `spec/plans/install_spec.rb`.

**Class spec pattern (rspec-puppet):**
- `spec/classes/setup/node_manager_spec.rb` uses `describe 'peadm::setup::node_manager'`, with `let(:params)` defined as a hash of string keys, and `is_expected.to contain_...` / `.with_...` matchers. It needs `before(:each) { Puppet[:tasks] = false }` because `spec_helper_local.rb` puts Puppet into Bolt's task mode globally; restore catalog mode for class specs.

**Patterns:**
- `describe` the public name (plan, function, class, or Ruby class), then nested `describe '#method'` for each Ruby method under test, and `context 'when ...'` for state.
- Use `subject(:name)` when the example group needs a named object, and `let` when the examples stub methods on it. RuboCop's `RSpec/SubjectStub` rule enforces this; `spec/unit/task/get_peadm_config_spec.rb` documents the reason inline.
- Set shared OIDs and cluster fixtures as `let` constants at the top of the group, with a comment about where they come from (`spec/classes/setup/node_manager_spec.rb`).
- Each example tests one behaviour. Multiple expectations per example are allowed (`RSpec/MultipleExpectations` is disabled).
- Mutation-oriented comments: many examples carry a `# Catches a mutation that ...` comment describing the regression they guard against. Keep this when extending a spec.

**Setup and teardown:**
- Global config is in `spec/spec_helper.rb` `c.before :each`: `Puppet.settings[:strict] = :warning` and `Puppet.settings[:strict_variables] = true`. Strict variables are on for all specs, so an undefined variable fails a test.
- Bolt context is set per example via `around(:each) { |example| in_bolt_context { example.run } }` (function specs).
- `after(:suite)` hooks enforce coverage floors (see Coverage below).
- `after(:all)` is excluded from RuboCop only under `spec/acceptance/**/*.rb` (`RSpec/BeforeAfterAll` in `.rubocop.yml`). Avoid it elsewhere.
- Use `RSPEC_UNIT_TEST_MODE` to keep task scripts from auto-executing at load. Specs set `ENV['RSPEC_UNIT_TEST_MODE'] ||= 'TRUE'` in `spec_helper_local.rb`, and tasks wrap their bottom-of-file execution in `unless ENV['RSPEC_UNIT_TEST_MODE']`.

## Mocking

**Framework:** `rspec-mocks` (`allow`, `expect(...).to receive`, `instance_double`), plus BoltSpec for Bolt tasks, commands, and plan steps.

**Patterns (Ruby unit, task HTTP stubbing):**
```ruby
let(:https_dbl) { instance_double(Net::HTTP) }
let(:request_dbl) { instance_double(Net::HTTP::Post) }
# stub the task's network helper rather than the network
allow(task).to receive(:https).and_return(https_dbl)
```
Source: `spec/unit/task/check_legacy_compilers_spec.rb`. Stub the task's own helper methods (`https`, `pdb_query`, `groups`) on the instance under test; do not reach through to the network.

**Patterns (Puppet function, plan_step):**
```ruby
class FakeScope
  def initialize(vars = {})
    @vars = vars
  end

  def bound?(name)
    @vars.key?(name)
  end

  def [](name)
    @vars[name]
  end

  def []=(name, value)
    @vars[name] = value
  end
end
```
Source: `spec/functions/plan_step_spec.rb`. Scope-dependent Puppet functions are tested by calling the raw function instance via `subject.func.<method>` with a hand-written scope double, because the dispatcher cannot easily supply a bound scope. The file carries `# rubocop:disable RSpec/InstanceVariable` around the double.

**Patterns (BoltSpec plan tests):**
```ruby
allow_out_message                                  # swallow out::message output
expect_plan('peadm::subplans::install')            # assert a subplan is invoked
expect_task('peadm::check_pe_master_rules')
  .with_targets(['primary'])
  .always_return({ ... })                          # canned task result
expect_command('...').always_return(...)           # canned command result
expect_out_message.with_params('# Plan Step: any-step')
```
Sources: `spec/plans/install_spec.rb`, `spec/plans/convert_compiler_to_legacy_spec.rb`, `spec/functions/plan_step_spec.rb`. Plan specs run in Bolt's plan mode, so every `run_task`, `run_command`, and `run_plan` call in the plan under test needs a matching `expect_*` stub or the example fails.

**Known limitation:** BoltSpec's `with_params` compares strictly. Hash parameters cannot use `hash_including`. `spec/plans/install_spec.rb` documents this and therefore asserts only that the plan runs to completion when a parameter is passed. Assert on the effect in the class spec instead.

**What to Mock:**
- Network clients (`Net::HTTP`, the classifier and PuppetDB HTTPS helpers) in Ruby task specs.
- Bolt tasks and commands in plan specs (`expect_task`, `expect_command`), always with `always_return` or `return_for_targets`.
- Output (`allow_out_message`) in plan specs to keep the output clean.
- Scope objects for Puppet functions that need a bound scope (`FakeScope`).

**What NOT to Mock:**
- Puppet catalog compilation in class and function specs. rspec-puppet compiles the real catalog; assert on it with `contain_*` matchers.
- The `peadm::` functions a plan or class calls. They are exercised directly, so the spec covers real behaviour.
- The vendored third-party modules in `spec/fixtures/modules/` (stdlib, provision, etc.). Use them as-is.

## Fixtures and Factories

**Test Data:**
- Inline hashes and arrays inside the `let` blocks are the norm. Node-group data is built as arrays of hashes with `'name'`, `'rule'`, `'config_data'` (`spec/unit/task/get_peadm_config_spec.rb`).
- Default facts for rspec-puppet come from `spec/default_facts.yml` (and `spec/default_module_facts.yml` if present), merged in `spec/spec_helper.rb`. Add shared facts there, not in individual specs.
- Acceptance scenarios are data-driven: `spec/acceptance/scenarios.yaml` is the catalog, loaded by `spec/acceptance/scenarios.rb` (`PeadmScenarios`). `spec/unit/peadm_scenarios_spec.rb` validates the catalog and checks that `documentation/test-scenarios.md` matches the generated markdown.
- Static fixture file used by a function spec: `spec/fixtures/modules/...` is vendored; do not add fixtures into it.

**Location:**
- Inline in the spec file for unit tests.
- `spec/default_facts.yml` for global facts.
- `spec/acceptance/scenarios.yaml` for acceptance scenario data.

## Coverage

**Requirements (enforced, not advisory):**
- Ruby line coverage: `SimpleCov.minimum_coverage 82` in `spec/spec_helper_local.rb`, only enforced under `SIMPLECOV=yes`. The coverage tracked set is widened to `{lib/**/*.rb,tasks/*.rb}`.
- Puppet resource coverage: `RSpec::Puppet::Coverage.report!(90)` in `spec/spec_helper.rb` (`after(:suite)`). This is resource-declaration coverage over compiled catalogs, not statement coverage.
- Note: `documentation/test-coverage.md` still describes an older 12% floor. The live value is in `spec/spec_helper_local.rb`; trust the code.

**View Coverage:**
```bash
bundle exec rake spec:simplecov        # console table + coverage/index.html
# Cobertura XML for Puppet manifests is written to coverage/puppet-coverage.xml when SIMPLECOV=yes
```

**Known gaps:**
- `lib/puppet/functions/peadm/*.rb` reports 0% in SimpleCov attribution even where specs exist (for example `spec/functions/plan_step_spec.rb` and the bolt_version spec). `spec_helper_local.rb` documents the attribution issue; do not chase the number in these files.
- `tasks/puppet_infra_upgrade.rb` has a large, pre-existing uncovered area (about 47% per the spec_helper_local comments).

## Test Types

**Unit Tests:**
- Ruby tasks: `spec/unit/task/*_spec.rb`, which load the task file with `require_relative` and exercise its classes directly. This is the most mature layer; 23 task specs exist.
- Puppet functions: `spec/functions/*_spec.rb`, using rspec-puppet function matchers (`is_expected.to run.with_params(...).and_return(...)`) or direct instance calls for functions that need scope.
- Ruby functions: `spec/functions/plan_step_spec.rb`, `spec/functions/sanitize_log_text_spec.rb`, etc.
- Data validation: `spec/unit/peadm_scenarios_spec.rb`.

**Integration Tests:**
- Plan specs (`spec/plans/**`): BoltSpec-driven. They exercise plan logic end-to-end at the orchestration layer but stub every task and command, so they verify sequencing and conditions, not remote behaviour.
- Class specs (`spec/classes/setup/node_manager_spec.rb`): rspec-puppet catalog compilation with assertions on the classified node groups.

**E2E / Acceptance Tests:**
- Litmus-based acceptance tests live in `spec/acceptance/` (`peadm_spec.rb`, `spec_helper_acceptance.rb`). The current `peadm_spec.rb` is a placeholder: its single example does nothing on non-Darwin systems.
- The real end-to-end install, upgrade, failover, and migration coverage is driven by GitHub Actions workflows in `.github/workflows/` (for example `test-install.yaml`, `test-upgrade.yaml`, `test-failover.yaml`, `test-backup-restore.yaml`, `test-legacy-compilers.yaml`, `test-migration.yaml`). Their matrix is generated from `spec/acceptance/scenarios.yaml` by `spec/acceptance/scenarios.rb`.
- Bolt plans for acceptance are in `spec/acceptance/peadm_spec/plans/` (`install_test_cluster.pp`, `perform_failover.pp`, `test_backup.pp`, `test_migration.pp`, and others). They are run by the workflows, not by rspec.
- Scenario catalog and documentation: `documentation/test-scenarios.md` (generated from `spec/acceptance/scenarios.yaml`; regenerate and keep in sync, a spec enforces this).

## Common Patterns

**Async / retry paths:**
- Plans do not use Ruby threads in specs. Retry loops in plans (`plans/subplans/install.pp`) are tested by stubbing the task to return a not-ready result first and a ready result on the next call with `expect_task(...).always_return` or sequenced returns, not by real sleeps.

**Error testing (Ruby tasks):**
```ruby
it 'raises when the rule is not an or-rule' do
  expect { node_group.pinned('PE Master') }.to raise_error('PE Master rule incompatible with pinning')
end

it 'treats a nil legacy_compilers as no nodes to check, without raising or logging' do
  expect(STDERR).not_to receive(:puts)
  expect { task.execute! }.not_to raise_error
end
```
Sources: `spec/unit/task/get_peadm_config_spec.rb`, `spec/unit/task/check_legacy_compilers_spec.rb`. Assert both the raised message (exact string) and the absence of unwanted STDERR/STDOUT output.

**Error testing (plans):**
- Test `fail_plan` paths by checking the failure returned by `run_plan` (BoltSpec). Look at `spec/plans/convert_compiler_to_legacy_spec.rb` and `spec/plans/convert_spec.rb` for existing examples to copy before writing a new one.

**Puppet function error testing:**
- rspec-puppet function specs can assert a raised error with `and_raise_error(/regex/)` on the `run.with_params(...)` chain. No function spec in `spec/functions/` currently demonstrates this; check the neighbouring specs before relying on it.

**Test-first conventions:**
- Every new Ruby task should get a `spec/unit/task/<task>_spec.rb` alongside the change. `spec_helper_local.rb` widens SimpleCov's tracked set to `tasks/*.rb` so an uncovered task shows up as a gap.
- Every new `peadm::` function gets a `spec/functions/<name>_spec.rb`.
- New acceptance scenarios go into `spec/acceptance/scenarios.yaml` and `documentation/test-scenarios.md` must be regenerated to match; `peadm_scenarios_spec.rb` fails otherwise.

---

*Testing analysis: 2026-11-10*

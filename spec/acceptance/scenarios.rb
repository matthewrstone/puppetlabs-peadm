#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'yaml'

# Reads spec/acceptance/scenarios.yaml. Used to list and filter scenarios, to
# emit a CI matrix, and to regenerate documentation/test-scenarios.md.
module PeadmScenarios
  CATALOG = File.join(__dir__, 'scenarios.yaml')
  DOC = File.expand_path('../../documentation/test-scenarios.md', __dir__)

  ARCHITECTURES = ['standard', 'standard-with-dr', 'large', 'large-with-dr', 'extra-large', 'extra-large-with-dr', 'unknown'].freeze
  STATUSES = ['ci', 'ci-partial', 'ci-manual', 'manual', 'unit', 'new', 'repro-only'].freeze
  CATEGORIES = ['install', 'upgrade', 'downgrade', 'rollback', 'failover', 'migrate', 'backup-restore', 'compiler', 'convert', 'replica', 'database'].freeze
  REQUIRED = ['id', 'name', 'category', 'from', 'arch', 'expect', 'cases', 'status', 'priority'].freeze
  VERSION = %r{\A\d{4}\.\d+\.(\d+|x)\z}.freeze
  CONCRETE = %r{\A\d{4}\.\d+\.\d+\z}.freeze
  DEFAULT_IMAGE = 'almalinux-cloud/almalinux-8'

  module_function

  def load(path = CATALOG)
    YAML.safe_load_file(path)
  end

  def archs(scenario)
    arch = scenario['arch']
    arch = scenario['arch_assumed'] if arch == 'unknown'
    Array(arch)
  end

  # Returns a list of problems; empty when the catalog is well-formed.
  def validate(scenarios)
    problems = []
    ids = scenarios.map { |s| s['id'] }
    ids.select { |i| ids.count(i) > 1 }.uniq.each { |i| problems << "duplicate id #{i}" }

    scenarios.each do |s|
      id = s['id'] || '(no id)'
      REQUIRED.each { |k| problems << "#{id}: missing #{k}" if s[k].nil? || s[k] == [] }
      problems << "#{id}: bad category #{s['category']}" unless CATEGORIES.include?(s['category'])
      problems << "#{id}: bad status #{s['status']}" unless STATUSES.include?(s['status'])
      problems << "#{id}: priority must be 1-3" unless [1, 2, 3].include?(s['priority'])
      problems << "#{id}: arch 'unknown' needs arch_assumed" if s['arch'] == 'unknown' && s['arch_assumed'].nil?
      (archs(s) - ARCHITECTURES).each { |a| problems << "#{id}: bad arch #{a}" }
      ['from', 'to', 'ci_from', 'ci_to'].each do |k|
        problems << "#{id}: #{k} '#{s[k]}' is not a version" if s[k] && s[k].to_s !~ VERSION
      end
      problems << "#{id}: needs a repro unless status is unit" if s['repro'].nil? && s['status'] != 'unit'
      problems << "#{id}: #{s['status']} needs a workflow" if ['ci', 'ci-partial', 'ci-manual'].include?(s['status']) && s['workflow'].nil?
      if s['workflow'] && !File.exist?(File.expand_path("../../.github/workflows/#{s['workflow']}", __dir__))
        problems << "#{id}: workflow #{s['workflow']} does not exist"
      end
    end
    problems
  end

  def filter(scenarios, opts)
    scenarios.select do |s|
      (opts[:ids].nil? || opts[:ids].include?(s['id'])) &&
        (opts[:category].nil? || s['category'] == opts[:category]) &&
        (opts[:status].nil? || opts[:status].include?(s['status'])) &&
        (opts[:priority].nil? || s['priority'] <= opts[:priority])
    end
  end

  def versions(scenario)
    from = scenario['ci_from'] || scenario['from']
    to = scenario['ci_to'] || scenario['to']
    [from, to]
  end

  # GitHub Actions matrix for scenarios that have a workflow. Scenarios whose
  # versions are not concrete (e.g. "2025.8.x") are skipped with a warning
  # unless a ci_from/ci_to pair gives installable versions.
  def matrix(scenarios)
    include = scenarios.select { |s| s['workflow'] }.flat_map do |s|
      from, to = versions(s)
      unless from.to_s.match?(CONCRETE) && (to.nil? || to.to_s.match?(CONCRETE))
        warn "skipping #{s['id']}: no concrete version (set ci_from/ci_to)"
        next []
      end
      archs(s).map do |a|
        { 'id' => s['id'], 'workflow' => s['workflow'], 'architecture' => a,
          'version' => from, 'version_to_upgrade' => to, 'image' => DEFAULT_IMAGE }.compact
      end
    end
    { 'include' => include }
  end

  def table(scenarios)
    rows = scenarios.map do |s|
      from, to = versions(s)
      path = to ? "#{from} -> #{to}" : from.to_s
      [s['id'], s['category'], path, archs(s).join(','), s['status'], "P#{s['priority']}", s['name']]
    end
    widths = (0..5).map { |i| rows.map { |r| r[i].size }.max }
    rows.map { |r| (0..5).map { |i| r[i].ljust(widths[i]) }.join('  ') + "  #{r[6]}" }.join("\n")
  end

  def markdown(scenarios)
    out = []
    out << '# Test scenarios'
    out << ''
    out << '<!-- Generated from spec/acceptance/scenarios.yaml by `ruby spec/acceptance/scenarios.rb --format markdown --write`. Do not edit by hand. -->'
    out << ''
    out << 'Scenarios for install, upgrade, downgrade, rollback, failover, migration and node replacement, '
    out << 'taken from support cases and Jira tickets about peadm. Each has the versions from the report and, '
    out << 'where the exact customer version is not worth installing, an equivalent that CI can run.'
    out << ''
    out << '| Status | Meaning |'
    out << '|---|---|'
    out << '| ci | runs on pull requests |'
    out << '| ci-partial | a PR workflow runs the same path but does not inject the fault |'
    out << '| ci-manual | workflow exists, run it on demand with workflow_dispatch |'
    out << '| manual | acceptance plan exists and is run by hand on operator VMs; no workflow |'
    out << '| unit | covered by rspec only |'
    out << '| new | needs an acceptance plan written |'
    out << '| repro-only | needs an environment or fault we cannot script yet |'
    out << ''
    out << '| ID | Category | Versions | Architecture | Status | Pri | Scenario |'
    out << '|---|---|---|---|---|---|---|'
    scenarios.each do |s|
      from, to = versions(s)
      v = s['to'] ? "#{s['from']} → #{s['to']}" : s['from'].to_s
      v += " (CI: #{from}#{to ? " → #{to}" : ''})" if s['ci_from'] || s['ci_to']
      out << "| [#{s['id']}](##{s['id'].downcase}) | #{s['category']} | #{v} | #{archs(s).join(', ')} | #{s['status']} | P#{s['priority']} | #{s['name']} |"
    end
    scenarios.each do |s|
      out << ''
      out << "## #{s['id']}"
      out << ''
      out << "**#{s['name']}**"
      out << ''
      out << "- Source: #{s['cases'].join(', ')}"
      out << "- Architecture: #{(s['arch'] == 'unknown') ? "not stated in the report; tested as #{s['arch_assumed']}" : archs(s).join(', ')}"
      out << "- CI runs: #{s['ci_arch']}" if s['ci_arch']
      out << "- OS: #{s['os']}" if s['os']
      out << "- Fault: #{s['fault']}" if s['fault']
      out << "- Workflow: `#{s['workflow']}`" if s['workflow']
      out << ''
      if s['repro']
        out << 'Reproduce:'
        out << ''
        s['repro'].each_with_index { |r, i| out << "#{i + 1}. #{r}" }
        out << ''
      end
      out << 'Expected:'
      out << ''
      s['expect'].each { |e| out << "- #{e}" }
      out << ''
      out << "Notes: #{s['notes']}" if s['notes']
    end
    "#{out.join("\n").gsub(%r{\n{3,}}, "\n\n").rstrip}\n"
  end

  def run(argv)
    opts = { format: 'table' }
    OptionParser.new { |o|
      o.banner = 'Usage: scenarios.rb [options]'
      o.on('--id IDS', 'Comma separated scenario ids') { |v| opts[:ids] = v.split(',') }
      o.on('--category CAT', CATEGORIES) { |v| opts[:category] = v }
      o.on('--status LIST', 'Comma separated statuses') { |v| opts[:status] = v.split(',') }
      o.on('--priority N', Integer, 'Include priority N and higher (1 is highest)') { |v| opts[:priority] = v }
      o.on('--format FMT', ['table', 'json', 'matrix', 'markdown']) { |v| opts[:format] = v }
      o.on('--write', 'With --format markdown, write documentation/test-scenarios.md') { opts[:write] = true }
      o.on('--validate', 'Check the catalog and exit') { opts[:validate] = true }
    }.parse!(argv)

    all = load
    problems = validate(all)
    unless problems.empty?
      warn problems.join("\n")
      return 1
    end
    return 0 if opts[:validate]

    unknown = (opts[:ids] || []) - all.map { |s| s['id'] }
    unless unknown.empty?
      warn "unknown scenario id: #{unknown.join(', ')}"
      return 1
    end

    selected = filter(all, opts)
    case opts[:format]
    when 'json' then puts JSON.pretty_generate(selected)
    when 'matrix' then puts JSON.generate(matrix(selected))
    when 'markdown'
      # The published document always lists every scenario.
      text = markdown(opts[:write] ? all : selected)
      opts[:write] ? File.write(DOC, text) : puts(text)
    else puts table(selected)
    end
    0
  end
end

exit(PeadmScenarios.run(ARGV)) if $PROGRAM_NAME == __FILE__

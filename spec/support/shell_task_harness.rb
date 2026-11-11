# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# Runs a peadm shell task under bash with stub executables first on PATH, so a
# task can be exercised without a Puppet Enterprise node or installer.
#
# Tasks source their helpers as "$(dirname $0)/../../peadm/files/<file>", which
# only resolves when the module directory is literally named "peadm". The
# harness therefore builds <root>/modules/peadm/{tasks,files} and copies the
# task and the shared shell helpers into it (a symlink would not work: the
# kernel resolves ".." physically).
class ShellTaskHarness
  REPO = File.expand_path('../..', __dir__)

  attr_reader :root, :stubs

  # Builds the temp module tree and copies the shared shell helpers into it.
  def initialize
    @root = Dir.mktmpdir('peadm-shell-task')
    @stubs = File.join(@root, 'stubs')
    @tasks = File.join(@root, 'modules', 'peadm', 'tasks')
    @files = File.join(@root, 'modules', 'peadm', 'files')
    [@stubs, @tasks, @files].each { |dir| FileUtils.mkdir_p(dir) }
    FileUtils.cp(Dir.glob(File.join(REPO, 'files', '*.sh')), @files)
  end

  # Writes an executable stub that records its arguments, then runs body.
  def stub(name, body)
    path = File.join(@stubs, name)
    File.write(path, "#!/bin/bash\necho \"$0 $*\" >> #{File.join(@root, "#{name}.calls")}\n#{body}\n")
    FileUtils.chmod(0o755, path)
    path
  end

  # Returns the recorded invocations of a stub, one line per call.
  def calls(name)
    file = File.join(@root, "#{name}.calls")
    File.exist?(file) ? File.readlines(file, chomp: true) : []
  end

  # Runs tasks/<task> with PT_<key> parameters and extra env, from inside the temp tree.
  def run(task, params = {}, env = {})
    FileUtils.cp(File.join(REPO, 'tasks', task), File.join(@tasks, task))
    environment = { 'PATH' => "#{@stubs}:#{ENV.fetch('PATH', nil)}", 'LANG' => 'C' }
    params.each { |key, value| environment["PT_#{key}"] = value.to_s }
    environment.merge!(env)
    stdout, stderr, status = Open3.capture3(environment, '/bin/bash', File.join(@tasks, task), chdir: @root)
    { stdout: stdout, stderr: stderr, status: status.exitstatus, json: parse_json(stdout) }
  end

  # Removes the temp tree.
  def cleanup
    FileUtils.rm_rf(@root)
  end

  private

  def parse_json(text)
    JSON.parse(text)
  rescue JSON::ParserError
    nil
  end
end

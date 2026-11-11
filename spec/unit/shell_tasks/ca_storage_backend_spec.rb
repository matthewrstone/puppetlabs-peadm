# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

describe 'tasks/ca_storage_backend.sh' do
  let(:harness) { ShellTaskHarness.new }
  let(:node_root) { File.join(harness.root, 'node') }
  let(:bootstrap) { File.join(node_root, 'etc/puppetlabs/puppetserver/bootstrap.cfg') }
  let(:etc_services_dir) { File.join(node_root, 'etc/puppetlabs/puppetserver/services.d') }
  let(:opt_services_dir) { File.join(node_root, 'opt/puppetlabs/server/apps/puppetserver/config/services.d') }
  let(:database_line) { 'puppetlabs.services.ca.database-storage-service/database-storage-service' }
  let(:filesystem_line) { 'puppetlabs.services.ca.certificate-authority-service/certificate-authority-service' }
  let(:checked) do
    [
      "#{node_root}/etc/puppetlabs/puppetserver/bootstrap.cfg",
      "#{node_root}/etc/puppetlabs/puppetserver/services.d/*.cfg",
      "#{node_root}/opt/puppetlabs/server/apps/puppetserver/config/services.d/*.cfg",
    ]
  end

  after(:each) { harness.cleanup }

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def detect
    harness.run('ca_storage_backend.sh', {}, { 'PEADM_ROOT' => node_root })
  end

  # Catches a mutation that stops recognising the line in bootstrap.cfg, which
  # would skip the pe-ca dump on every database-backed CA.
  it 'reports database and the file when bootstrap.cfg enables the database service' do
    write(bootstrap, "#{filesystem_line}\n  #{database_line}\n")
    result = detect
    expect(result[:status]).to eq(0)
    expect(result[:json]).to eq('backend' => 'database', 'source' => bootstrap, 'checked' => checked)
  end

  # Catches a mutation that counts a commented line, which would try to dump a
  # pe-ca database that does not exist.
  it 'reports filesystem when the database line is commented out' do
    write(bootstrap, "#{filesystem_line}\n# #{database_line}\n  #  #{database_line}\n")
    expect(detect[:json]).to eq('backend' => 'filesystem', 'source' => nil, 'checked' => checked)
  end

  # The parent of this task read bootstrap.cfg only; PE 2026 / Puppet 9 can put
  # the service line in a services.d file instead.
  it 'finds the line in the packaged services.d directory when bootstrap.cfg does not have it' do
    write(bootstrap, "#{filesystem_line}\n")
    ca_cfg = File.join(opt_services_dir, 'ca.cfg')
    write(ca_cfg, "#{database_line}\n")
    expect(detect[:json]).to eq('backend' => 'database', 'source' => ca_cfg, 'checked' => checked)
  end

  it 'finds the line in a services.d file under /etc when there is no bootstrap.cfg' do
    ca_cfg = File.join(etc_services_dir, 'ca.cfg')
    write(ca_cfg, "#{database_line}\n")
    expect(detect[:json]).to eq('backend' => 'database', 'source' => ca_cfg, 'checked' => checked)
  end

  it 'reports filesystem when only a services.d file exists and it lacks the line' do
    write(File.join(opt_services_dir, 'ca.cfg'), "#{filesystem_line}\n")
    expect(detect[:json]).to include('backend' => 'filesystem', 'source' => nil)
  end

  # Catches a mutation that answers filesystem when nothing could be read: the
  # callers warn on unknown instead of silently assuming no database-backed CA.
  it 'reports unknown, with every location checked, when none of the files exists' do
    result = detect
    expect(result[:status]).to eq(0)
    expect(result[:json]).to eq('backend' => 'unknown', 'source' => nil, 'checked' => checked)
  end

  it 'does not match a different service whose name only contains the database service name' do
    write(bootstrap, "puppetlabs.services.ca.database-storage-service-extra/foo\nsomething.puppetlabs.services.ca.database-storage-service/foo\n")
    expect(detect[:json]).to include('backend' => 'filesystem')
  end

  it 'reads the real paths when PEADM_ROOT is not set' do
    result = harness.run('ca_storage_backend.sh')
    expect(result[:json]['checked']).to eq(['/etc/puppetlabs/puppetserver/bootstrap.cfg',
                                            '/etc/puppetlabs/puppetserver/services.d/*.cfg',
                                            '/opt/puppetlabs/server/apps/puppetserver/config/services.d/*.cfg'])
  end
end

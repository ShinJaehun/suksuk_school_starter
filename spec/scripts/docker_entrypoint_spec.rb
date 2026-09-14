require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'
require 'json'
require 'yaml'

RSpec.describe 'Docker entrypoint' do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:entrypoint) { File.join(root, 'bin/docker-entrypoint') }

  around do |example|
    Dir.mktmpdir('starter-entrypoint') do |directory|
      @directory = directory
      FileUtils.mkdir_p(File.join(directory, 'bin'))
      File.write(File.join(directory, 'bin/rails'), <<~BASH)
        #!/bin/bash
        echo "rails $*" >> "$ENTRYPOINT_LOG"
        if [ "$1" = "db:prepare" ]; then exit "${PREPARE_STATUS:-0}"; fi
      BASH
      File.write(File.join(directory, 'bin/bundle'), <<~BASH)
        #!/bin/bash
        echo "bundle $*" >> "$ENTRYPOINT_LOG"
      BASH
      FileUtils.chmod(0o755, Dir[File.join(directory, 'bin/*')])
      example.run
    end
  end

  def run_entrypoint(*command, prepare_status: '0')
    log = File.join(@directory, 'calls')
    _, stderr, status = Open3.capture3(
      { 'PATH' => "#{@directory}/bin:#{ENV.fetch('PATH')}", 'ENTRYPOINT_LOG' => log,
        'PREPARE_STATUS' => prepare_status },
      entrypoint, *command, chdir: @directory
    )
    expect(stderr).to be_empty
    [status.exitstatus, File.exist?(log) ? File.readlines(log, chomp: true) : []]
  end

  it 'prepares before the Dockerfile default command' do
    command = JSON.parse(File.read(File.join(root, 'Dockerfile'))[/^CMD (.+)$/, 1])
    expect(run_entrypoint(*command)).to eq([0, ['rails db:prepare', 'bundle exec puma -C config/puma.rb']])
  end

  it 'prepares before the compose web command' do
    command = YAML.load_file(File.join(root, 'compose.prod.yml')).fetch('services').fetch('web').fetch('command')
    expect(run_entrypoint(*command)).to eq([0, ['rails db:prepare', 'bundle exec puma -C config/puma.rb']])
  end

  it 'does not start Puma when preparation fails' do
    expect(run_entrypoint('bundle', 'exec', 'puma', '-C', 'config/puma.rb', prepare_status: '17'))
      .to eq([17, ['rails db:prepare']])
  end

  it 'preserves preparation for the Rails server' do
    expect(run_entrypoint('./bin/rails', 'server')).to eq([0, ['rails db:prepare', 'rails server']])
  end

  it 'does not prepare for a console' do
    expect(run_entrypoint('./bin/rails', 'console')).to eq([0, ['rails console']])
  end

  it 'executes explicit preparation exactly once' do
    expect(run_entrypoint('./bin/rails', 'db:prepare')).to eq([0, ['rails db:prepare']])
  end

  it 'does not prepare for another task' do
    expect(run_entrypoint('bundle', 'exec', 'rake', 'about')).to eq([0, ['bundle exec rake about']])
  end

  it 'does not prepare for a shell and preserves its exit status' do
    expect(run_entrypoint('bash', '-c', 'exit 9')).to eq([9, []])
  end

  it 'does not start the Rails server when preparation fails' do
    expect(run_entrypoint('./bin/rails', 'server', prepare_status: '17')).to eq([17, ['rails db:prepare']])
  end
end

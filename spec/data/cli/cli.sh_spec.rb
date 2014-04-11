require 'spec_helper'
require 'open3'

def debug?
  ENV['DEBUG'] == "yes"
end

class MyProcess
  attr_reader :command, :exit_status, :env, :stdout, :stderr
  attr_accessor :debug

  def initialize(command, env)
    @command = command
    @env = env
    @stdout = ""
    @stderr = ""
  end


  def call(args, opts = {})
    opts = {timeout: 0.5, environment: env}.merge(opts)

    full_command = [command, args].join(" ")
    puts full_command if debug

    cmd = Mixlib::ShellOut.new(full_command, opts)
    cmd.run_command

    @stdout = cmd.stdout.chomp
    @stderr = cmd.stderr.chomp

    puts @stdout if debug
    puts @stderr if debug
    @exit_status = cmd.exitstatus

    self
  end

  def ko?
    ! ok?
  end

  def ok?
    exit_status && exit_status.zero?
  end
end

def generate_cli(config, target)

  ["etc/default", "etc/#{config.name}/conf.d", "usr/bin", config.home, "var/log/#{config.name}"].each do |dir|
    FileUtils.mkdir_p(File.join(target, dir))
  end

  content = ERB.new(File.read(File.expand_path("../../../../data/cli/cli.sh.erb", __FILE__))).result(config.sesame)
  cli_filename = File.join(target, "usr", "bin", config.name)

  File.open(cli_filename, "w+") do |f|
    f.puts content
  end
  FileUtils.chmod 0755, cli_filename

end

describe "bash cli" do
  let(:directory) { Dir.mktmpdir }
  let(:config) {
    Pkgr::Config.new(name: "my-app")
  }

  let(:command) {
    %{sudo -E #{directory}/usr/bin/#{config.name}}
  }

  let(:process) {
    process = MyProcess.new(command, "ROOT_PATH" => directory)
    process.debug = debug?
    process
  }

  before(:each) do
    generate_cli(config, directory)
    File.open(File.join(directory, "etc", "default", config.name), "w+") do |f|
      f.puts %{export HOME="#{config.home}"}
      f.puts %{export APP_NAME="#{config.name}"}
      f.puts %{export APP_GROUP="#{ENV['USER']}"}
      f.puts %{export APP_USER="#{ENV['USER']}"}
    end
  end

  after(:each) do
    FileUtils.rm_rf(directory) unless debug?
  end

  it "displays the usage if no args given" do
    process.call("")
    expect(process).to be_ok
    expect(process.stdout).to include("my-app run COMMAND")
  end

  it "returns the content of the logs" do
    File.open("#{directory}/var/log/#{config.name}/web-1.log", "w+") { |f| f << "some log here 1"}
    File.open("#{directory}/var/log/#{config.name}/worker-1.log", "w+") { |f| f << "some log here 2"}

    process.call("logs")
    expect(process).to be_ok
    expect(process.stdout).to include("some log here 1")
    expect(process.stdout).to include("some log here 2")
  end

  describe "config" do
    it "sets a config" do
      process.call("config:set YOH=YEAH")
      expect(process).to be_ok
      expect(process.stdout).to eq("")

      expect(File.read("#{directory}/etc/my-app/conf.d/other")).to eq("export YOH=YEAH\n")

      process.call("config:get YOH")
      expect(process).to be_ok
      expect(process.stdout).to eq("YEAH")
    end

    it "returns the full config" do
      process.call("config")
      expect(process).to be_ok
      expect(process.stdout).to include("HOME=/opt/my-app/app")
    end
  end

  describe "run" do
    it "returns the result of the arbitrary command" do
      process.call("run pwd")
      expect(process).to be_ok
      expect(process.stdout).to eq(File.join(directory, config.home))
    end

    it "returns the result of a declared process" do
      web_process_filename = File.join(directory, config.home, "vendor", "pkgr", "processes", "web")
      FileUtils.mkdir_p(File.dirname(web_process_filename))
      File.open(web_process_filename, "w+") do |f|
        f.puts "#!/bin/sh"
        f << "exec "
        f << "ls"
        f << " $@"
      end
      FileUtils.chmod 0755, web_process_filename

      process.call("run web -1")
      expect(process).to be_ok
      expect(process.stdout.split("\n")).to eq(["vendor"])
    end
  end

  describe "scale" do
    context "upstart" do
      it "scales up from 0" do
        pending
      end
      it "scales up from x" do
        pending
      end
    end
  end

end

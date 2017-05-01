require "open3"
require "ostruct"
require "yaml"

require_relative "dockerhelper"
require_relative "syncfiles"

class Common
  @@commands = []

  def Common.register_command(command)
    @@commands.push(command)
  end

  def Common.commands()
    @@commands
  end

  attr :docker
  attr :sf

  def initialize()
    @docker = DockerHelper.new(self)
    @sf = SyncFiles.new(self)
  end

  def print_usage()
    STDERR.puts "\nUsage: ./project.rb <command> <options>\n\n"
    STDERR.puts "COMMANDS\n\n"
    @@commands.each do |command|
      STDERR.puts bold_term_text(command[:invocation])
      STDERR.puts command[:description]
      STDERR.puts
    end
  end

  def handle_or_die(command, *args)
    handler = @@commands.select{ |x| x[:invocation] == command }.first
    if handler.nil?
      error "#{command} command not found."
      exit 1
    end

    handler[:fn].call(*args)
  end

  def load_env()
    if not File.exists?("project.yaml")
      error "Missing project.yaml"
      exit 1
    end
    OpenStruct.new YAML.load(File.read("project.yaml"))
  end

  def red_term_text(text)
    "\033[0;31m#{text}\033[0m"
  end

  def blue_term_text(text)
    "\033[0;36m#{text}\033[0m"
  end

  def bold_term_text(text)
    "\033[1m#{text}\033[0m"
  end

  def status(text)
    STDERR.puts blue_term_text(text)
  end

  def error(text)
    STDERR.puts red_term_text(text)
  end

  def put_command(cmd)
    if cmd.is_a?(String)
      STDERR.puts "+ #{cmd}"
    else
      STDERR.puts "+ #{cmd.join(" ")}"
    end
  end

  def run_inline(cmd)
    put_command(cmd)
    if not system(*cmd)
      exit $?.exitstatus
    end
  end

  def run_or_fail(cmd)
    put_command(cmd)
    Open3.popen3(*cmd) do |i, o, e, t|
      i.close
      if not t.value.success?
        STDERR.write red_term_text(e.read)
        exit t.value.exitstatus
      end
    end
  end

  def run(cmd)
    Open3.popen3(*cmd) do |i, o, e, t|
      i.close
      t.value
    end
  end

  def pipe(*cmds)
    s = cmds.map { |x| x.join(" ") }
    s = s.join(" | ")
    STDERR.puts "+ #{s}"
    Open3.pipeline(*cmds).each do |status|
      unless status.success?
        error "Piped command failed"
        exit 1
      end
    end
  end
end

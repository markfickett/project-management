#!/usr/bin/env ruby

unless Dir.exists? ".project/common"
  system(*%W{mkdir -p .project})
  system(*%W{git clone https://github.com/dmohs/project-management.git .project/common})
end

require_relative ".project/common/common"
Dir.foreach(".project") do |item|
  unless item =~ /^\.\.?$/ || item == "common"
    require_relative ".project/#{item}"
  end
end

c = Common.new

if ARGV.length == 0 or ARGV[0] == "--help"
  c.print_usage
  exit 0
end

command = ARGV.first
args = ARGV.drop(1)

c.handle_or_die(command, *args)

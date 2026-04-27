require "bundler/gem_tasks"
require "rb_sys/extensiontask"

GEMSPEC = Gem::Specification.load("paradoxical.gemspec")

RbSys::ExtensionTask.new("paradoxical", GEMSPEC) do |ext|
  ext.lib_dir = "lib/paradoxical"
end

task default: :compile

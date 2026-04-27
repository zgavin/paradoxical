$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "yaml"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random
  Kernel.srand config.seed

  # `:integration` specs require the Rust extension and an off-repo fixture
  # path. They are gated on PARADOXICAL_EXAMPLE_MOD and skipped in CI until
  # MODERNIZATION.md phase 2 (rutie -> magnus) lands a sane FFI build.
  config.filter_run_excluding :integration unless ENV["PARADOXICAL_EXAMPLE_MOD"]
end

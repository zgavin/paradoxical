$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "yaml"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random
  Kernel.srand config.seed

  # `:integration` specs need both the compiled Rust extension and an
  # off-repo fixture path. Skipped when PARADOXICAL_EXAMPLE_MOD is unset;
  # CI doesn't build the extension yet (lands with MODERNIZATION.md phase 1c).
  config.filter_run_excluding :integration unless ENV["PARADOXICAL_EXAMPLE_MOD"]
end

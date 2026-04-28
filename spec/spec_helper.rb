$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "yaml"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random
  Kernel.srand config.seed

  # Off-repo specs that need both the compiled Rust extension and a real
  # filesystem fixture. CI doesn't build the extension yet — that lands
  # with MODERNIZATION.md phase 1d.
  config.filter_run_excluding :integration unless ENV["PARADOXICAL_EXAMPLE_MOD"]
  config.filter_run_excluding :parse_smoke unless ENV["PARADOXICAL_PARSE_SMOKE"]
end

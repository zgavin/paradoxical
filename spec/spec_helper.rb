$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random
  Kernel.srand config.seed
end

module Paradoxical::Search
  # Thin facade over the Rust-backed search parser. ParseError is
  # allowed to propagate — pre-1c scaffolding swallowed it and called
  # `exit`, the same shape `Paradoxical::FileParser#parse` had until
  # the test suite landed; both want to bubble up so callers (and
  # specs) can react.
  def self.parse data
    Parser.parse data
  end
end

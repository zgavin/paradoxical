module Paradoxical::Games::ImperatorRome::DSL
  # Variable arithmetic — operation-keyed `{ name = X ... }` shape
  # Imperator introduced; EU5 inherited the same surface and lives
  # in `Paradoxical::Games::EU5::DSL`. If they diverge, split into
  # a shared module then.
  #
  # See phase 5e in MODERNIZATION.md for the per-game body shape
  # taxonomy and the three variable storage kinds (scope / context /
  # game-wide) that the scope-prefixed variants target.

  %w[set check].each do |verb|
    %w[variable local_variable global_variable].each do |kind|
      define_method("#{verb}_#{kind}") do |name, value|
        l("#{verb}_#{kind}", p("name", name), p("value", value)).single_line!
      end
    end
  end

  %w[change_variable change_local_variable change_global_variable].each do |key|
    define_method(key) do |name, **operations|
      l(key, p("name", name), *operations.map do |k, v| p(k.to_s, v) end).single_line!
    end
  end
end

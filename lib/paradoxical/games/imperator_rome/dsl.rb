module Paradoxical::Games::ImperatorRome::DSL
  # Variable arithmetic — operation-keyed `{ name = X ... }` shape
  # Imperator introduced; EU5 inherited the same surface and lives
  # in `Paradoxical::Games::EU5::DSL`. If they diverge, split into
  # a shared module then.
  #
  # See phase 5e in MODERNIZATION.md for the per-game body shape
  # taxonomy and the three variable storage kinds (scope / context /
  # game-wide) that the scope-prefixed variants target.

  # `check_variable` is an EU4/Stellaris-only trigger keyword;
  # Imperator's read-side trigger is `has_variable` (5891 uses
  # vs 0 of `check_variable`). Deferred to 5e-3 alongside the
  # other shapes the wiki documents (`round_variable`, `days =`
  # lifetime kwarg, property-form shorthand).
  %w[set_variable set_local_variable set_global_variable].each do |key|
    define_method(key) do |name, value|
      l(key, p("name", name), p("value", value)).single_line!
    end
  end

  %w[change_variable change_local_variable change_global_variable].each do |key|
    define_method(key) do |name, **operations|
      l(key, p("name", name), *operations.map do |k, v| p(k.to_s, v) end).single_line!
    end
  end
end

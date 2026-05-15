module Paradoxical::Games::EU5::DSL
  # Variable arithmetic — operation-keyed `{ name = X ... }` shape
  # introduced by Imperator and inherited by EU5. The shape is
  # identical between the two games today; the same surface lives
  # in `Paradoxical::Games::ImperatorRome::DSL`. If they diverge,
  # split into a shared module then.
  #
  # See phase 5e in MODERNIZATION.md for the per-game body shape
  # taxonomy and the three variable storage kinds (scope / context /
  # game-wide) that the scope-prefixed variants target.

  # `set_variable` and `check_variable`, with scope-prefixed variants
  # for the three storage kinds. Bare form targets the current
  # scope (a persistent game object — country, location, etc.);
  # `_local_` targets the current context (event chain / effect
  # block); `_global_` targets the game-wide store.
  %w[set check].each do |verb|
    %w[variable local_variable global_variable].each do |kind|
      define_method("#{verb}_#{kind}") do |name, value|
        l("#{verb}_#{kind}", p("name", name), p("value", value)).single_line!
      end
    end
  end

  # `change_variable` with operation kwargs — `add:`, `subtract:`,
  # `multiply:`, `divide:`, `modulo:`, `min:`, `max:`, `value:` —
  # emitted in declaration order. Multiple ops in one call work
  # (`change_variable("x", multiply: 100, min: 0)`) because PDX
  # treats the body as a sequence of operations applied in source
  # order. Nested operation bodies (a kwarg whose value is itself a
  # block of more operations) are a phase-5e follow-up.
  %w[change_variable change_local_variable change_global_variable].each do |key|
    define_method(key) do |name, **operations|
      l(key, p("name", name), *operations.map do |k, v| p(k.to_s, v) end).single_line!
    end
  end
end

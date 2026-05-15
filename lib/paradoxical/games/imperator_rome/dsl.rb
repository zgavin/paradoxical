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

  # See EU5::DSL for the nested-block example. `single_line!` only
  # fires for the one-flat-op shape; multi-op and block forms emit
  # multi-line.
  CHANGE_VARIABLE_OPERATIONS = %i[add subtract multiply divide modulo min max value].freeze

  %w[change_variable change_local_variable change_global_variable].each do |key|
    define_method(key) do |name, **operations, &block|
      unknown = operations.keys - CHANGE_VARIABLE_OPERATIONS
      if unknown.any? then
        raise ArgumentError,
              "unknown #{key} operation(s) #{unknown.inspect}; " \
              "allowed: #{CHANGE_VARIABLE_OPERATIONS.inspect}"
      end

      list = l(key, p("name", name), *operations.map do |k, v| p(k.to_s, v) end, &block)
      list.single_line! if block.nil? and operations.size == 1
      list
    end
  end
end

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

  # `set_variable` with scope-prefixed variants for the three
  # storage kinds. Bare form targets the current scope (a
  # persistent game object — country, location, etc.); `_local_`
  # targets the current context (event chain / effect block);
  # `_global_` targets the game-wide store.
  #
  # The read-side trigger is `has_variable` (not `check_variable`,
  # which EU5/Imperator don't expose — that's an EU4/Stellaris
  # thing). Deferred to 5e-3 along with `round_variable`, the
  # `days =` lifetime kwarg on `set_variable`, and the
  # property-form shorthand `set_variable = NAME`.
  %w[set_variable set_local_variable set_global_variable].each do |key|
    define_method(key) do |name, value|
      l(key, p("name", name), p("value", value)).single_line!
    end
  end

  # Operation kwargs allowed in `change_variable` and its scope
  # variants. Empirically derived from EU5 source (PR #74 review);
  # rejecting unknown kwargs catches typos like `add: 5` vs `ad: 5`
  # at construction time rather than producing engine-invalid script.
  CHANGE_VARIABLE_OPERATIONS = %i[add subtract multiply divide modulo min max value].freeze

  # `change_variable` with operation kwargs — emitted in declaration
  # order so `change_variable("x", multiply: 100, min: 0, max: 1)`
  # produces `{ name = x multiply = 100 min = 0 max = 1 }` and PDX
  # applies the ops left-to-right.
  #
  # Nested operations land via a block — any operation can also be
  # expressed inside the block as a nested body:
  #
  #   change_variable "imperial_authority" do
  #     add do
  #       value "scope:loser.total_population"
  #       divide "scope:winner.total_population"
  #       max 2
  #       min 0.1
  #       multiply 5
  #     end
  #   end
  #
  # The block evaluates in Builder context, so any `keyword do … end`
  # inside it falls through `method_missing` → `pdx_obj` and produces
  # the right `keyword = { body }` shape.
  #
  # Whitespace: `single_line!` only when there's exactly one flat
  # operation (`change_variable("x", add: 5)` style). Multi-op flat
  # forms and any block form stay multi-line — matches how real
  # EU5 source writes multi-op changes.
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

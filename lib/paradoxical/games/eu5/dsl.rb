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

  # `change_variable` with operation kwargs — `add:`, `subtract:`,
  # `multiply:`, `divide:`, `modulo:`, `min:`, `max:`, `value:` —
  # emitted in declaration order. Multiple ops in one call work
  # (`change_variable("x", multiply: 100, min: 0)`) because PDX
  # treats the body as a sequence of operations applied in source
  # order.
  #
  # Nested operations land via a block — any of the operation kwargs
  # can also be expressed inside the block as a nested body:
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
  # the right `keyword = { body }` shape. Block form emits multi-line;
  # flat-kwargs form stays single-line.
  %w[change_variable change_local_variable change_global_variable].each do |key|
    define_method(key) do |name, **operations, &block|
      list = l(key, p("name", name), *operations.map do |k, v| p(k.to_s, v) end, &block)
      list.single_line! if block.nil?
      list
    end
  end
end

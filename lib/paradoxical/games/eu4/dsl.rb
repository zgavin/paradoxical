module Paradoxical::Games::EU4::DSL
  # EU4 stores variable values as either a numeric literal or a
  # reference to another variable's name. The reference form uses
  # `which = NAME` rather than the `value = NAME` that the other
  # `which`/`value` games (Stellaris) use, so for non-numeric values
  # we emit `<op>_variable { which = X which = Y }` instead of
  # `<op>_variable { which = X value = Y }`. `export_to_variable`
  # is the lone exception — it always uses `value`.
  #
  # See phase 5e in MODERNIZATION.md for the per-game shape split.
  # This module used to inherit a base Builder loop with the simpler
  # `value`-second-key shape; the move from base Builder to per-game
  # DSL happened so HOI4 / EU5 / Imperator could carry their own
  # divergent shapes without inheriting wrong behavior.
  %w[set check change subtract multiply divide modulo round_variable_to_closest].each do |word|
    key = word.include?("variable") ? word : "#{word}_variable"

    define_method key do |which, operator, value = nil|
      value, operator = operator, "=" if value.nil?
      second_key = value.is_a?(Numeric) ? "value" : "which"
      l(key, p("which", which), p(second_key, operator, value)).single_line!
    end
  end

  # `export_to_variable` is EU4-only across the installed games
  # (370 uses in EU4, 0 elsewhere). `value` is always the second
  # key here — no `which`-wrinkle since this form references the
  # source-of-data not a variable.
  def export_to_variable which, value, who = nil
    l "export_to_variable" do
      p "which", which
      p "value", value
      p "who", who unless who.nil?
    end.single_line!
  end
end

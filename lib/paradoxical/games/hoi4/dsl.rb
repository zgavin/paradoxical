module Paradoxical::Games::HOI4::DSL
  # HOI4's variable arithmetic body shape is unique among PDS titles:
  # the variable name is the *key* of the inner property, not a
  # `which =` / `name =` wrapper. Examples from real game data:
  #
  #   set_variable      = { ETH_state_decentralization_resources = 0 }
  #   add_to_variable   = { SOV_paranoia_weekly_modifiers_amount = 1 }
  #   multiply_variable = { BUL_days_based_on_faction_loyalty = BUL_ff_missions_loyalty_factor }
  #
  # Arithmetic verb is `add_to_variable`, not `change_variable` like
  # EU4/Stellaris/EU5/Imperator.
  #
  # See phase 5e in MODERNIZATION.md.
  %w[set add_to subtract_from multiply divide modulo].each do |word|
    key = word.include?("variable") ? word : "#{word}_variable"

    define_method key do |name, operator, value = nil|
      value, operator = operator, "=" if value.nil?
      l(key, p(name, operator, value)).single_line!
    end
  end
end

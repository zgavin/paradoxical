module Paradoxical::Games::EU4
  NAME             = "Europa Universalis IV"
  SLUG             = "eu4"
  STEAM_ID         = 236850
  JOMINI_VERSION   = 1
  NATIVE_PLATFORMS = %i[windows linux macos].freeze

  # EU4-specific Builder helpers. Prepended onto Builder by
  # `paradoxical!` so methods defined here override the base ones.
  module DSL
    # EU4 stores variable values as either a numeric literal or a
    # reference to another variable's name. The reference form uses
    # `which = NAME` rather than the `value = NAME` that the other
    # PDS games use, so for non-numeric values we emit
    # `<op>_variable { which = X which = Y }` instead of
    # `<op>_variable { which = X value = Y }`. `export_to_variable`
    # is the lone exception — it always uses `value`.
    %w[set check change subtract multiply divide modulo round_variable_to_closest].each do |word|
      key = word.include?("variable") ? word : "#{word}_variable"

      define_method key do |which, operator, value=nil|
        value, operator = operator, '=' if value.nil?
        second_key = value.is_a?(Numeric) ? 'value' : 'which'
        l(key, p('which', which), p(second_key, operator, value)).single_line!
      end
    end
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

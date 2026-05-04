module Paradoxical::Games::Stellaris
  NAME             = "Stellaris"
  SLUG             = "stellaris"
  STEAM_ID         = 281990
  JOMINI_VERSION   = 1
  NATIVE_PLATFORMS = %i[windows linux macos].freeze

  # Stellaris-specific Builder helpers. `paradoxical!` prepends this
  # module onto Builder when Stellaris is the active game so these
  # methods become available to mod scripts (and stay absent for other
  # games where the constructs don't apply).
  module DSL
    # Galaxy-setup-value triggers — the `get_galaxy_setup_value` /
    # `check_galaxy_setup_value` constructs are Stellaris-only
    # (galaxy setup is a Stellaris feature).

    def get_galaxy_setup_value setting, operator, value=nil
      value, operator = operator, '=' if value.nil?
      l("get_galaxy_setup_value", p('setting', setting), p('value', operator, value)).single_line!
    end

    def check_galaxy_setup_value setting, operator, value=nil
      value, operator = operator, '=' if value.nil?
      l("check_galaxy_setup_value", p('setting', setting), p('value', operator, value)).single_line!
    end

    # Stellaris resource economy. `mult:` is Stellaris's per-month
    # accrual multiplier; `add_resource` with a String value also
    # routes through `mult` because the game treats string values as
    # references to per-month rates.

    def resource_stockpile_compare resource, operator, value=nil, mult: nil
      if value.nil? then
        value = operator
        operator = '='
      end

      if mult.nil? then
        l('resource_stockpile_compare', p('resource', resource), p('value', operator, value)).single_line!
      else
        l('resource_stockpile_compare', p('resource', resource), p('value', operator, value), p('mult', mult))
      end
    end

    def add_resource resource, value
      if value.is_a? String then
        l('add_resource', p(resource, 1), p('mult', value))
      else
        l('add_resource', p(resource, value)).single_line!
      end
    end

    def remove_resource resource, value
      if value.is_a? String then
        l('add_resource', p(resource, -1), p('mult', value))
      else
        l('add_resource', p(resource, -1 * value)).single_line!
      end
    end
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

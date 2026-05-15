module Paradoxical::Games::Stellaris::DSL
  # Galaxy-setup-value triggers — the `get_galaxy_setup_value` /
  # `check_galaxy_setup_value` constructs are Stellaris-only
  # (galaxy setup is a Stellaris feature).

  def get_galaxy_setup_value setting, operator, value = nil
    value, operator = operator, "=" if value.nil?
    l("get_galaxy_setup_value", p("setting", setting), p("value", operator, value)).single_line!
  end

  def check_galaxy_setup_value setting, operator, value = nil
    value, operator = operator, "=" if value.nil?
    l("check_galaxy_setup_value", p("setting", setting), p("value", operator, value)).single_line!
  end

  # Stellaris resource economy. `mult:` is Stellaris's per-month
  # accrual multiplier; `add_resource` with a String value also
  # routes through `mult` because the game treats string values as
  # references to per-month rates.

  def resource_stockpile_compare resource, operator, value = nil, mult: nil
    if value.nil? then
      value = operator
      operator = "="
    end

    if mult.nil? then
      l("resource_stockpile_compare", p("resource", resource), p("value", operator, value)).single_line!
    else
      l("resource_stockpile_compare", p("resource", resource), p("value", operator, value), p("mult", mult))
    end
  end

  def add_resource resource, value
    if value.is_a? String then
      l("add_resource", p(resource, 1), p("mult", value))
    else
      l("add_resource", p(resource, value)).single_line!
    end
  end

  def remove_resource resource, value
    if value.is_a? String then
      l("add_resource", p(resource, -1), p("mult", value))
    else
      l("add_resource", p(resource, -1 * value)).single_line!
    end
  end

  # Variable arithmetic. Stellaris uses the `which`/`value` body
  # shape — `change_variable { which = X value = Y }` etc. No
  # EU4-style second-key wrinkle (Stellaris always uses `value` as
  # the second key, even when Y is a non-numeric reference).
  %w[set check change subtract multiply divide modulo round_variable_to_closest].each do |word|
    key = word.include?("variable") ? word : "#{word}_variable"

    define_method key do |which, operator, value = nil|
      value, operator = operator, "=" if value.nil?
      l(key, p("which", which), p("value", operator, value)).single_line!
    end
  end
end

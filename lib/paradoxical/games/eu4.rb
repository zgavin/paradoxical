module Paradoxical::Games::EU4
  NAME              = "Europa Universalis IV"
  SLUG              = "eu4"
  STEAM_ID          = 236850
  NATIVE_PLATFORMS  = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR   = false
  LAUNCHER_FORMAT   = :sqlite

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

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

      define_method key do |which, operator, value = nil|
        value, operator = operator, "=" if value.nil?
        second_key = value.is_a?(Numeric) ? "value" : "which"
        l(key, p("which", which), p(second_key, operator, value)).single_line!
      end
    end
  end

  CORRECTIONS = {}

  # Files that parse correctly but are pathologically slow — usually
  # very deeply-nested constructs that hit a worst-case backtracking
  # path in the pest grammar. The smoke skips these by default;
  # `PARADOXICAL_PARSE_SMOKE_THOROUGH=1` includes them when you want
  # to verify everything still works (e.g. before tagging a release
  # or after grammar changes).
  #
  # The 167 KB `00_scripted_effects.txt` parses correctly but takes
  # ~72 seconds — three orders of magnitude per-byte slower than
  # equivalent files in HOI4/Stellaris (which parse 100-300 KB
  # scripted_effects in 20-50 ms). The bisection is in the second
  # half of the file; root-causing the grammar issue is its own
  # task.
  SLOW_FILES = %w[
    common/scripted_effects/00_scripted_effects.txt
  ].freeze

  Paradoxical::Games.register(self)
end

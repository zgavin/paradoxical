module Paradoxical::Games::EU4
  NAME              = "Europa Universalis IV"
  SLUG              = "eu4"
  STEAM_ID          = 236850
  NATIVE_PLATFORMS  = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR   = false
  LAUNCHER_FORMAT   = :sqlite

  CALENDAR = Paradoxical::Calendars::Calendar365
  FLOAT_PRECISION = 3

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
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

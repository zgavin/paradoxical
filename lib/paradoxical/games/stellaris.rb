module Paradoxical::Games::Stellaris
  NAME               = "Stellaris"
  SLUG               = "stellaris"
  STEAM_ID           = 281990
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = false
  LAUNCHER_FORMAT    = :sqlite
  CALENDAR           = Paradoxical::Calendars::Calendar360
  FLOAT_PRECISION    = 3

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  CORRECTIONS = {
    # `scripted_loc_ruloc.txt` is missing its closing `}` at EOF
    # (brace depth +1 with no trailing newline). Append `\n}` so
    # the outer `defined_text { … }` block closes cleanly.
    "4.3.5" => {
      "common/scripted_loc/scripted_loc_ruloc.txt" =>
        ->(data) { data << "\n}\n" },
    },

    # New in 4.4.x (cosmic-storm "nomads" mesh definitions). Both
    # parsed clean through 4.3.7 because the files didn't exist yet;
    # 4.4.0 was skipped, so 4.4.1 is the first-known-broken release.
    # Same missing-`}` shape: the outer `objectTypes = {` runs off EOF
    # still open while every inner `pdxmesh`/`meshsettings` block
    # nests cleanly, so append one closing brace at EOF.
    "4.4.1" => {
      "gfx/models/effects/nomads.gfx" =>
        ->(data) { data << "\n}\n" },
      "gfx/models/ui/nomads_frontend.gfx" =>
        ->(data) { data << "\n}\n" },
    },
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

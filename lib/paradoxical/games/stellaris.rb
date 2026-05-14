module Paradoxical::Games::Stellaris
  NAME               = "Stellaris"
  SLUG               = "stellaris"
  STEAM_ID           = 281990
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = false
  LAUNCHER_FORMAT    = :sqlite
  CALENDAR           = Paradoxical::Calendars::Calendar360

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
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

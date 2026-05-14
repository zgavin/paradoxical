module Paradoxical::Games::V3
  NAME               = "Victoria 3"
  SLUG               = "v3"
  STEAM_ID           = 529340
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = true
  LAUNCHER_FORMAT    = :sqlite
  CALENDAR           = Paradoxical::Calendars::Calendar365

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  CORRECTIONS = {}

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

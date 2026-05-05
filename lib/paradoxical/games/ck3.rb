module Paradoxical::Games::CK3
  NAME               = "Crusader Kings III"
  SLUG               = "ck3"
  STEAM_ID           = 1158310
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = true
  LAUNCHER_FORMAT    = :sqlite

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  module DSL
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

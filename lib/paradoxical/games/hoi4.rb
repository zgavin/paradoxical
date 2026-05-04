module Paradoxical::Games::HOI4
  NAME               = "Hearts of Iron IV"
  SLUG               = "hoi4"
  STEAM_ID           = 394360
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = false
  LAUNCHER_FORMAT    = :sqlite
  ENCODING_FALLBACKS = [].freeze

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  module DSL
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

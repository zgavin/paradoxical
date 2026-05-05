module Paradoxical::Games::ImperatorRome
  NAME               = "ImperatorRome"
  SLUG               = "imperator"
  STEAM_ID           = 859580
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  # Imperator (March 2019) was the first jomini-engine title and
  # ships the `game/` install layout that subsequent jomini titles
  # inherit. Mod loading still goes through the SQLite launcher.
  HAS_GAME_SUBDIR    = true
  LAUNCHER_FORMAT    = :sqlite

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  module DSL
  end

  CORRECTIONS = {
    # `posteffect_volumes.txt` ends with a stray column-0 `}` after
    # the structural close (47 opens, 48 closes). Same pattern as
    # the EU5 gui files — strip the trailing column-0 `}`.
    "2.0.5" => {
      "gfx/map/post_effects/posteffect_volumes.txt" =>
        ->(data) { data.sub!(/^\}\s*\z/, '') },
    },
  }

  Paradoxical::Games.register(self)
end

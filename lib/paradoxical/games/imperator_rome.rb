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
    "2.0.5" => {
      # Stray `\t}` mid-file just before the
      # `posteffect_height_volume` block whose
      # `name = "zoom_step_3"`. The double `\t}\n\t}\n` is the
      # tell. Anchor on the quoted `"zoom_step_3"` form (the only
      # quoted occurrence; an unquoted `zoom_step_3` exists
      # elsewhere as a different field) to keep the match scoped to
      # exactly this defect site.
      "gfx/map/post_effects/posteffect_volumes.txt" =>
        ->(data) {
          data.sub!(
            "\t}\n\t}\n\tposteffect_height_volume = {\n\t\tname = \"zoom_step_3\"",
            "\t}\n\tposteffect_height_volume = {\n\t\tname = \"zoom_step_3\"",
          )
        },
    },
  }

  Paradoxical::Games.register(self)
end

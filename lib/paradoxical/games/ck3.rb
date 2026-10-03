module Paradoxical::Games::CK3
  NAME               = "Crusader Kings III"
  SLUG               = "ck3"
  STEAM_ID           = 1158310
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = true
  LAUNCHER_FORMAT    = :sqlite
  CALENDAR           = Paradoxical::Calendars::Calendar365
  FLOAT_PRECISION    = 3

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  CORRECTIONS = {
    # First build checked (2026-10, via the corpus); defects may be
    # older, and get re-keyed if backfilled builds show it.
    "1.20.0.3" => {
      # Engine file beside `game/`, keyed root-relative via `..`. The
      # final `type dialog_property_filterable_property_list` block is
      # indented one level too deep and the file closes once too
      # often: the type's `}`, the `types` block's `}`, then a stray
      # column-0 `}` at EOF. Dropping the trailing one leaves the type
      # holding its `using` and `types` closed.
      "../clausewitz/gui/applicationutils/tools_gui_dialogs.gui" =>
        ->(data) { data.sub!(/^\}\s*\z/, "") },
    },
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

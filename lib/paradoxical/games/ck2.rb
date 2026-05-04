module Paradoxical::Games::CK2
  NAME               = "Crusader Kings II"
  SLUG               = "ck2"
  STEAM_ID           = 203770
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = false
  # CK2 predates both the SQLite-based and JSON-based PDS launchers —
  # it has its own legacy launcher for mod/playset config that we
  # haven't ported to. `:legacy` selects a stub mod-loading
  # implementation that raises if anything tries to actually load
  # mods (parser-only usage still works).
  LAUNCHER_FORMAT    = :legacy
  ENCODING_FALLBACKS = [].freeze

  # CK2 ships no branch file or launcher JSON. The game has been EOL
  # since the 3.3.5.1 patch (Sep 2021), so any installed copy is on
  # that version — hardcode and skip the changelog-scraping dance.
  def self.installed_version _game
    Gem::Version.new("3.3.5.1")
  end

  # Game-specific DSL helpers (mixed into Builder when this game is
  # active). Empty for now; populate as concrete needs surface.
  module DSL
  end

  # path → [block, …] of corrections to apply to the raw file bytes
  # before parsing. Empty for now; populate as malformed-input cases
  # surface from the parse smoke.
  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

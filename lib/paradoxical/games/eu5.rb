module Paradoxical::Games::EU5
  NAME               = "Europa Universalis V"
  SLUG               = "eu5"
  STEAM_ID           = 3450310
  # Windows-only at launch — Linux/macOS users run this via Proton/Wine.
  # `Games.executable_for` will append `.exe` accordingly.
  NATIVE_PLATFORMS   = %i[windows].freeze
  HAS_GAME_SUBDIR    = true
  # EU5 is the first PDS title to ship per-game JSON mod metadata
  # (`.metadata/metadata.json` per mod) instead of the shared
  # launcher-v2 SQLite database.
  LAUNCHER_FORMAT    = :json

  # EU5 ships no launcher-settings.json. The version sits in
  # `caesar_branch.txt` at the install root: `release/X.Y.Z`.
  def self.installed_version game
    Paradoxical::Games.read_branch_version(game, "caesar_branch.txt", /release\/(\S+)/)
  end

  module DSL
  end

  # Each correction is a per-path proc that mutates the raw file
  # bytes before the parser sees them. Versions key the corrections
  # by their first-known-broken release; an explicit `nil` at a
  # later version unregisters one once Paradox patches the file.
  # See `Paradoxical::Games::Corrections.resolve` for the inheritance
  # semantics.
  #
  # All three of these gui files end with one extra column-0 `}`
  # past the structural close — brace counts are 47/48 (or similar).
  # The substitution targets a `}` at start-of-line followed only by
  # whitespace through EOF, so it only fires on the trailing
  # extra brace. Per-path scoping keeps the loose regex from
  # touching legitimately-balanced files.
  STRIP_TRAILING_BRACE = ->(data) { data.sub!(/^\}\s*\z/, '') }

  CORRECTIONS = {
    "1.1.0" => {
      "in_game/gui/panels/organization/coalition.gui" => STRIP_TRAILING_BRACE,
      "in_game/gui/panels/organization/crusade.gui"   => STRIP_TRAILING_BRACE,
      "in_game/gui/shared/city_tooltips.gui"          => STRIP_TRAILING_BRACE,
    },
  }

  Paradoxical::Games.register(self)
end

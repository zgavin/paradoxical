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
  # Each correction anchors on a unique substring near the defect
  # rather than a line number — line numbers shift if Paradox edits
  # earlier in the file, but the surrounding context tends to stay
  # stable through patches.
  CORRECTIONS = {
    "1.1.0" => {
      # Stray `}` directly after the self-closing
      # `country_flag_small = {}`. Removing it leaves the surrounding
      # structure balanced. `country_flag_small = {}` is unique to
      # this file so anchoring on it is sufficient.
      "in_game/gui/panels/organization/crusade.gui" =>
        ->(data) {
          data.sub!(
            "\t\t\tcountry_flag_small = {}\n\t\t\t}\n\t\t}",
            "\t\t\tcountry_flag_small = {}\n\t\t}",
          )
        },

      # Two `blockoverride "ios_header_content_divider" {}` sites
      # exist; only the first has a stray `\t}` line after it. The
      # following block's name (`ios_information_header_content_extra_2`)
      # is unique to the broken site, so we anchor on the divider →
      # stray-brace → next-block sequence to disambiguate.
      "in_game/gui/panels/organization/coalition.gui" =>
        ->(data) {
          data.sub!(
            "        blockoverride \"ios_header_content_divider\" {}\n\t}\n\n" \
            "\tblockoverride \"ios_information_header_content_extra_2\"",
            "        blockoverride \"ios_header_content_divider\" {}\n\n" \
            "\tblockoverride \"ios_information_header_content_extra_2\"",
          )
        },

      # Genuine trailing-brace case: 75 opens vs. 76 closes, with
      # one extra column-0 `}` at EOF past the structural close.
      "in_game/gui/shared/city_tooltips.gui" =>
        ->(data) { data.sub!(/^\}\s*\z/, "") },
    },
  }

  Paradoxical::Games.register(self)
end

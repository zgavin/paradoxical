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

  # EU5 ships no launcher-settings.json. `caesar_branch.txt` is also
  # unreliable: its format is at Paradox's whim and patch components
  # have been silently dropped (1.1.10 reported as `release/1.1.0`),
  # so we ignore it. We use the 32-char build checksum from
  # `binaries/checksum.txt` instead — it's build-time-stamped, also
  # embedded inline in eu5.exe, and changes per Paradox release.
  #
  # `BUILD_VERSION_MAP` keys on the *last 4 chars* of the disk
  # checksum rather than the full hex. Through 1.1.x, those 4 chars
  # are exactly the publicly-displayed checksum Paradox prints in
  # the launcher and uses for achievement gating — so the map can
  # be populated for past releases from public patchnotes alone, no
  # install required. 1.2.0 introduced some kind of transformation
  # (the public checksum no longer matches the disk suffix), so
  # those entries have to be populated by hand from an actual
  # install. 4 hex chars = 16 bits = ~65k space; Paradox treats
  # that as adequately unique so we do too.
  BUILD_VERSION_MAP = {
    "f98c" => "1.0.4",   # "Lepanto", earliest publicly-released build
    "e7e4" => "1.0.7",
    "6cba" => "1.0.9",
    "1cb4" => "1.0.10",
    "6166" => "1.0.11",
    "d718" => "1.1.9",   # "Rossbach", first official 1.1.x release (1.1.0–1.1.8 were beta-only)
    "b0ac" => "1.1.10",
    "2a62" => "1.2.0",   # "Echinades"; publicly-displayed checksum (obfuscated) is 5be7
    "cb31" => "1.2.1",   # publicly-displayed checksum (obfuscated) is e429
  }.freeze

  def self.installed_version game
    checksum = Paradoxical::Games.read_build_checksum(game)
    return nil if checksum.nil? || checksum.length < 4

    version = BUILD_VERSION_MAP[checksum[-4..]]
    version && Gem::Version.new(version)
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
    # Earliest publicly-released build is 1.0.4. All three defects
    # below are present from that release through the latest (1.2.1
    # at time of writing), so keying at 1.0.4 covers every known
    # build via `Corrections.resolve`'s `<= installed` selection.
    "1.0.4" => {
      # Stray `}` directly after the self-closing
      # `country_flag_small = {}`. `country_flag_small = {}` is unique
      # to this file so anchoring on it is sufficient. The capture
      # preserves the self-closing block; `\s*\n\s*\}` matches the
      # newline + indent + stray `}` and gets dropped.
      "in_game/gui/panels/organization/crusade.gui" =>
        ->(data) { data.sub!(/(country_flag_small = \{\})\s*\n\s*\}/, '\1') },

      # Two `blockoverride "ios_header_content_divider" {}` sites
      # exist; only the first has a stray `\t}` line after it. The
      # following block's name (`ios_information_header_content_extra_2`)
      # is unique to the broken site, so anchor on the divider + stray
      # `}` + whitespace + that next block. Captures keep the divider
      # and the whitespace-leading-into-next-block; the stray `}` is
      # dropped.
      "in_game/gui/panels/organization/coalition.gui" =>
        ->(data) {
          data.sub!(
            %r{
              (blockoverride\s+"ios_header_content_divider"\s+\{\})
              \s*\}
              (\s*blockoverride\s+"ios_information_header_content_extra_2")
            }x,
            '\1\2',
          )
        },

      # Genuine trailing-brace case: 75 opens vs. 76 closes, with
      # one extra column-0 `}` at EOF past the structural close.
      "in_game/gui/shared/city_tooltips.gui" =>
        ->(data) { data.sub!(/^\}\s*\z/, "") },
    },
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

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
  CALENDAR           = Paradoxical::Calendars::Calendar365
  # EU5 generally accepts up to 6 decimal digits in source, but
  # `set_local_variable` / `change_local_variable` cap at 5 (with
  # distinct errors for set vs change — separately validated paths,
  # not a shared parser). 5 is the variable-safe default; modders
  # who need 6 in a non-variable context can opt out via raw bytes.
  FLOAT_PRECISION    = 5

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
    "e7e4" => "1.0.0", # "Lepanto" launch build (patchnotes call it 1.0)
    # no 1.0.1 in the depot history or the patchnotes
    "ae68" => "1.0.2",
    "94d0" => "1.0.3",
    "f98c" => "1.0.4",
    "cdab" => "1.0.5",
    "7ff6" => "1.0.6",
    "724a" => "1.0.7",
    "dce5" => "1.0.8",
    "6cba" => "1.0.9",
    "1cb4" => "1.0.10",
    "6166" => "1.0.11",
    # 1.1.0–1.1.8 were the "Rossbach" open beta, all on Steam's `1.1.0`
    # branch. Checksums are from the forum update posts, except 1.1.3:
    # its post repeats 1.1.2's `2675`, apparently copied over, and
    # `d568` is the only branch build between 1.1.2 and 1.1.4, two days
    # after 1.1.2, matching the posts.
    "9d08" => "1.1.0",
    "79a8" => "1.1.1",
    "2675" => "1.1.2",
    "d568" => "1.1.3",
    "318e" => "1.1.4",
    "e728" => "1.1.5",
    "f7ef" => "1.1.6",
    "5c65" => "1.1.7",
    "33c6" => "1.1.8",
    "d718" => "1.1.9",   # first official 1.1.x release
    "b0ac" => "1.1.10",
    "2a62" => "1.2.0",   # "Echinades"; publicly-displayed checksum (obfuscated) is 5be7
    "cb31" => "1.2.1",   # publicly-displayed checksum (obfuscated) is e429
    "6005" => "1.2.2",   # publicly-displayed checksum (obfuscated) is fb04
    "78ec" => "1.2.3",   # publicly-displayed checksum (obfuscated) is 6a4a
    "c9d1" => "1.2.4",   # publicly-displayed checksum (obfuscated) is e02d
    "4e92" => "1.2.5",   # publicly-displayed checksum (obfuscated) is cf2f
    # 1.3.0–1.3.10 were an open-beta cycle; 1.3.10 was both the final
    # beta build and the first official (non-beta) 1.3.x release, and
    # subsequent releases are official builds. Odd numbers through the
    # beta were reserved for hotfixes and none shipped.
    "2774" => "1.3.0", # open-beta build; public checksum 5ad0
    # 1.3.1 skipped; reserved for a hotfix that proved unnecessary
    "fc9d" => "1.3.2", # open-beta build; public checksum ede5
    # 1.3.3 skipped; reserved for a hotfix that proved unnecessary
    "6064" => "1.3.4", # open-beta build; public checksum 3244
    # 1.3.5 skipped; reserved for a hotfix that proved unnecessary
    "ed4b" => "1.3.6", # open-beta build; no official checksum, in-game only (872e)
    # 1.3.7 skipped; reserved for a hotfix that proved unnecessary
    "2f83" => "1.3.8", # open-beta build; public checksum 98b8
    # 1.3.9 skipped; reserved for a hotfix that proved unnecessary
    "a2c4" => "1.3.10", # final beta / first official 1.3.x release; public checksum c764
    "54cd" => "1.3.11", # official 1.3.x release; public checksum b08d
    "d9c8" => "1.4.0", # open-beta build; public checksum 592b
  }.freeze

  def self.installed_version game
    checksum = Paradoxical::Games.read_build_checksum(game)
    return nil if checksum.nil? || checksum.length < 4

    version = BUILD_VERSION_MAP[checksum[-4..]]
    version && Gem::Version.new(version)
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
    # below are present from that release through 1.3.11, so keying at
    # 1.0.4 covers every known build via `Corrections.resolve`'s
    # `<= installed` selection. crusade.gui is fixed in 1.4.0 and
    # unregistered there; the other two persist through the latest
    # (1.4.0 at time of writing).
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

    # New in the 1.3.0 open beta. Both files parsed clean through
    # 1.2.5, so these are first-known-broken here rather than at
    # 1.0.4 with the others.
    "1.3.0" => {
      # Same genuine trailing-brace shape as city_tooltips: the
      # `lateralview` block closes cleanly, then a stray column-0 `}`
      # follows at EOF (87 opens vs. 88 closes). Drop the trailing one.
      "in_game/gui/estate_actions_lateralview.gui" =>
        ->(data) { data.sub!(/^\}\s*\z/, "") },

      # Inverse case: the final `window = {}` block is missing its
      # closing brace (140 opens vs. 139 closes), so the parser runs
      # off EOF still open. Every inner block nests cleanly and the
      # file is a flat list of top-level definitions, so the missing
      # close unambiguously belongs at EOF — append one `}` line.
      "main_menu/gui/report_issue.gui" =>
        ->(data) { data.sub!(/\}\n\z/, "}\n}\n") },
    },

    "1.4.0" => {
      # Fixed by Paradox in the 1.4.0 open beta. Both files now
      # balance, and the corrections' anchors still match legitimate
      # braces, so leaving them registered would strip a real close
      # and break the parse.
      "in_game/gui/panels/organization/crusade.gui" => nil,
      "in_game/gui/estate_actions_lateralview.gui" => nil,

      # First engine-file defect. The engine dirs sit beside `game/`,
      # so the key is root-relative via `..`. The block holding the
      # scrollbar spacer closes twice: the spacer is followed by two
      # `}` lines at the same indent, and every enclosing brace after
      # that is off by one until the stray close at EOF. The spacer's
      # comment is unique to the file; keep the first `}` and drop the
      # duplicate.
      "../clausewitz/loading_screen/gui/tools/save_dialog.gui" =>
        ->(data) { data.sub!(/(# make space for scrollbar\n(\t*)\}\n)\2\}\n/, '\1') },
    },
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

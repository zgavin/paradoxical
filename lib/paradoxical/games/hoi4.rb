module Paradoxical::Games::HOI4
  NAME               = "Hearts of Iron IV"
  SLUG               = "hoi4"
  STEAM_ID           = 394360
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = false
  LAUNCHER_FORMAT    = :sqlite
  CALENDAR           = Paradoxical::Calendars::Calendar365
  FLOAT_PRECISION    = 3

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  # Most of HOI4's malformed files are off by a single brace. A missing
  # `}` gets one appended at EOF, which is exactly what the engine does
  # (it implicitly closes open blocks at EOF); a single extra trailing
  # `}` is stripped.
  APPEND_BRACE = ->(data) { data << "\n}\n" }
  STRIP_TRAILING_BRACE = ->(data) { data.sub!(/\}\s*\z/, "") }

  # Several small-nation history files were cloned from Angola's: the
  # cloners commented out its `create_country_leader` block line by
  # line but left the block's closing `}` live, so a stray column-0
  # `}` sits between it and the `1939.1.1` block (in Angola itself the
  # leader block is live and the `}` is just as stray). Drop it.
  STRIP_STRAY_HISTORY_BRACE =
    ->(data) { data.sub!(/^\}\r?\n((?:[ \t]*\r?\n)+(?:#[^\n]*\n)*1939\.1\.1 = \{)/, '\1') }

  # Corrections are keyed by first-known-broken build. 1.8.2 is the
  # corpus floor (the first build shipping `launcher-settings.json`),
  # so a file keyed there may well be broken earlier too.
  CORRECTIONS = {
    "1.8.2" => {
      "common/units/names_divisions/BRA_names_divisions.txt" => APPEND_BRACE,
      "gfx/entities/empty.gfx" => APPEND_BRACE,
      "history/countries/NOR - Norway.txt" => APPEND_BRACE,
      "history/units/FRA_1936.txt" => APPEND_BRACE,
      "history/units/FRA_1939_naval_legacy.txt" => APPEND_BRACE,
      "history/units/FRA_1939_naval_mtg.txt" => APPEND_BRACE,
      "interface/backend.gui" => APPEND_BRACE,
      "interface/equipmentdesignermodules.gfx" => APPEND_BRACE,

      "history/countries/ANG - Angola.txt" => STRIP_STRAY_HISTORY_BRACE,
      "history/countries/BAH - Bahamas.txt" => STRIP_STRAY_HISTORY_BRACE,
      "history/countries/BAN - Bangladesh.txt" => STRIP_STRAY_HISTORY_BRACE,
      "history/countries/BAS - British Antilles.txt" => STRIP_STRAY_HISTORY_BRACE,
      "history/countries/BLZ - Belize.txt" => STRIP_STRAY_HISTORY_BRACE,
      # Guyana also never closes the `set_politics = {` inside its
      # `1939.1.1` block.
      "history/countries/GYA - Guyana.txt" =>
        ->(data) { STRIP_STRAY_HISTORY_BRACE.call(data) and APPEND_BRACE.call(data) },

      # `pdx_tooltip = ` with no value, straight before the enclosing
      # `}`. The engine skips a valueless property, so drop the line
      # rather than invent a value.
      "interface/menubar.gui" => ->(data) { data.sub!(/^[ \t]*pdx_tooltip = \r?\n/, "") },
    },

    "1.11.13" => {
      "common/ideas/SOV.txt" => APPEND_BRACE,
      "history/units/FRA_1936_nsb.txt" => APPEND_BRACE,
      "interface/sov_propaganda_campaigns_scripted_gui.gui" => APPEND_BRACE,

      # Fixed: the cloned history files lost their stray `}`, and
      # Guyana closed its `set_politics` (its stray remains a release
      # longer).
      "history/countries/ANG - Angola.txt" => nil,
      "history/countries/BAH - Bahamas.txt" => nil,
      "history/countries/BAN - Bangladesh.txt" => nil,
      "history/countries/BAS - British Antilles.txt" => nil,
      "history/countries/BLZ - Belize.txt" => nil,
      "history/countries/GYA - Guyana.txt" => STRIP_STRAY_HISTORY_BRACE,
      "interface/equipmentdesignermodules.gfx" => nil,
      "interface/menubar.gui" => nil,
    },

    "1.12.14" => {
      "common/ideas/switzerland.txt" => APPEND_BRACE,
      "history/countries/GYA - Guyana.txt" => nil,
    },

    "1.14.10" => {
      "common/military_industrial_organization/organizations/BRA_organization.txt" => APPEND_BRACE,
      "common/technology_sharing/00_tech_sharing_groups.txt" => STRIP_TRAILING_BRACE,
    },

    "1.15.4" => {
      "common/national_focus/austria.txt" => APPEND_BRACE,
      "gfx/entities/flame_tanks.gfx" => APPEND_BRACE,
      "gfx/entities/landmarks.gfx" => APPEND_BRACE,
      "interface/ger_monroe_doctrine_scripted_gui.gui" => APPEND_BRACE,
      "interface/powerbalanceview.gfx" => APPEND_BRACE,

      # Multiple `base = ´45` lines (acute-accent typo, presumably
      # meant `45` — `base` takes a numeric weight in `ai_chance`
      # blocks). Strip the stray accent character before parsing.
      "events/WUW_Germany.txt" => ->(data) { data.gsub!("base = ´45", "base = 45") },

      "common/technology_sharing/00_tech_sharing_groups.txt" => nil,
    },

    "1.16.10" => {
      "common/ideas/persia.txt" => APPEND_BRACE,
      "common/national_focus/austria.txt" => nil,
    },

    "1.17.5.2" => {
      "common/doctrines/subdoctrines/sea/navy_submarine_doctrines.txt" => APPEND_BRACE,
      "common/national_focus/TSR_lingguang_incident_joint_branch.txt" => STRIP_TRAILING_BRACE,
      "gfx/entities/landmarks.gfx" => nil,
    },

    # New in the 1.19 content cycle (Australia / Siam focus-tree
    # additions). All four parsed clean through 1.18.3.0 because the
    # files didn't exist yet — first-known-broken is the 1.19 line.
    # 1.19.0.0 shipped for ~2 days before the 1.19.0.1 hotfix; both
    # carry these files, so key at 1.19.0.0 (the corrections are
    # anchor/EOF fixups and no-op safely if a file is later patched).
    # Each is the same single-missing-`}` shape as the 1.18.1.0 set:
    # the outermost block runs off EOF still open, every inner block
    # nests cleanly, so the missing close unambiguously belongs at EOF.
    "1.19.0.0" => {
      # Outer `ast_right_vs_left_campaign_empty_inlay_window = {` never closes.
      "common/focus_inlay_windows/ast_right_vs_left_campaign_empty_inlay_window.txt" => APPEND_BRACE,
      # Outer `scripted_gui = {` never closes.
      "common/scripted_guis/AST_cabinet_trust_scripted_gui.txt" => APPEND_BRACE,
      # Final `instant_effect = {` never closes.
      "history/units/AST_1936.txt" => APPEND_BRACE,
      # Outer `guiTypes = {` never closes.
      "interface/sia_movie_theater_campaigns_scripted_gui.gui" => APPEND_BRACE,
    },
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

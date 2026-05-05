module Paradoxical::Games::HOI4
  NAME               = "Hearts of Iron IV"
  SLUG               = "hoi4"
  STEAM_ID           = 394360
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = false
  LAUNCHER_FORMAT    = :sqlite
  # HOI4 ships pure UTF-8 except for a handful of older files that
  # use Windows-1252 in-game markup bytes (`§R`, `§!` color codes).
  # `pdx_online_assets/interface/online_accountcreate.gui` is the
  # one we know about; the smoke tries UTF-8 first and falls back.
  ENCODING_FALLBACKS = ["Windows-1252"].freeze

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  module DSL
  end

  # 17 of HOI4's allowlisted-fail files are upstream-malformed by a
  # single brace: 16 are missing one `}` (engine implicitly closes
  # at EOF), 1 has one extra `}`. Engine tolerates either; our
  # parser is strict, so apply per-file byte fixups.
  APPEND_BRACE = ->(data) { data << "\n}\n" }
  STRIP_TRAILING_BRACE = ->(data) { data.sub!(/\}\s*\z/, '') }

  CORRECTIONS = {
    "1.18.1.0" => {
      # 16 files missing one `}` — append a closing brace.
      "common/doctrines/subdoctrines/sea/navy_submarine_doctrines.txt" => APPEND_BRACE,
      "common/ideas/SOV.txt"                                            => APPEND_BRACE,
      "common/ideas/persia.txt"                                         => APPEND_BRACE,
      "common/ideas/switzerland.txt"                                    => APPEND_BRACE,
      "common/military_industrial_organization/organizations/BRA_organization.txt" => APPEND_BRACE,
      "common/units/names_divisions/BRA_names_divisions.txt"            => APPEND_BRACE,
      "gfx/entities/empty.gfx"                                          => APPEND_BRACE,
      "gfx/entities/flame_tanks.gfx"                                    => APPEND_BRACE,
      "history/countries/NOR - Norway.txt"                              => APPEND_BRACE,
      "history/units/FRA_1936.txt"                                      => APPEND_BRACE,
      "history/units/FRA_1936_nsb.txt"                                  => APPEND_BRACE,
      "history/units/FRA_1939_naval_legacy.txt"                         => APPEND_BRACE,
      "history/units/FRA_1939_naval_mtg.txt"                            => APPEND_BRACE,
      "interface/backend.gui"                                           => APPEND_BRACE,
      "interface/ger_monroe_doctrine_scripted_gui.gui"                  => APPEND_BRACE,
      "interface/powerbalanceview.gfx"                                  => APPEND_BRACE,
      "interface/sov_propaganda_campaigns_scripted_gui.gui"             => APPEND_BRACE,

      # 1 file has one extra trailing `}` — strip it.
      "common/national_focus/TSR_lingguang_incident_joint_branch.txt"   => STRIP_TRAILING_BRACE,

      # `events/WUW_Germany.txt` has multiple `base = ´45` lines
      # (acute accent typo, presumably meant `45` — `base` takes a
      # numeric weight in `ai_chance` blocks). Strip the stray
      # accent character before parsing.
      "events/WUW_Germany.txt" => ->(data) { data.gsub!("base = ´45", "base = 45") },
    },
  }

  Paradoxical::Games.register(self)
end

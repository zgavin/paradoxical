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

  # A missing `}` gets one appended at EOF, which is what the engine
  # does (it implicitly closes open blocks at EOF); a single extra
  # trailing `}` is stripped.
  APPEND_BRACE = ->(data) { data << "\n}\n" }
  APPEND_TWO_BRACES = ->(data) { data << "\n}\n}\n" }
  STRIP_TRAILING_BRACE = ->(data) { data.sub!(/\}\s*\z/, "") }

  # History files carry a few malformed date keys: a trailing dot
  # (`841.1.1. = {`) or extra components (`1019.1.1.1.1 = {`). Paradox
  # shipped them for years, so the engine reads them as the plain
  # `Y.M.D` date; trim them to match rather than loosen the grammar.
  TRIM_MALFORMED_DATES = ->(data) { data.gsub!(/^(\s*\d+\.\d+\.\d+)(?:\.\d*)+(\s*=)/, '\1\2') }

  # A valueless `key =` straight before the enclosing `}`. The engine
  # skips it, so drop the line rather than invent a value.
  def self.drop_valueless key
    ->(data) { data.sub!(/^[ \t]*#{Regexp.escape(key)}[ \t]*=[ \t]*\r?\n(?=[ \t]*\})/, "") }
  end

  # Corrections are keyed by first-known-broken build, with an explicit
  # `nil` where Paradox fixed the file. 1.0.3 is the earliest build in
  # the corpus.
  CORRECTIONS = {
    "1.0.3" => {
      "events/government_events/clan_events.txt" => APPEND_BRACE,
      "events/stress_events/stress_threshold_events.txt" => drop_valueless("event_background"),
      "history/characters/french.txt" => TRIM_MALFORMED_DATES,
      "history/characters/serbian.txt" => TRIM_MALFORMED_DATES,
      # `{ save_temporary_scope_as = other_parent } }`: a doubled close.
      "common/scripted_triggers/00_bastard_triggers.txt" =>
        ->(data) { data.gsub!(/(save_temporary_scope_as = other_parent \}) \}/, '\1') },
    },
    "1.1.3" => {
      "events/government_events/clan_events.txt" => nil,
      "events/stress_events/stress_threshold_events.txt" => nil,
    },
    "1.2.2" => {
      "common/genes/01_genes_morph.txt" => APPEND_BRACE,
      "common/scripted_triggers/00_bastard_triggers.txt" => nil,
    },
    "1.3.1" => {
      "common/genes/01_genes_morph.txt" => nil,
    },
    "1.5.1.1" => {
      "common/genes/06_genes_special_accessories_headgear.txt" => APPEND_BRACE,
      "gui/artifact_details_view.gui" => STRIP_TRAILING_BRACE,
      "gui/shared/value_breakdown.gui" => APPEND_BRACE,
      "gui/window_court_events.gui" => APPEND_BRACE,

      # Engine file beside `game/`, keyed root-relative via `..`. The
      # final `type dialog_property_filterable_property_list` block is
      # indented one level too deep and the file closes once too
      # often: the type's `}`, the `types` block's `}`, then a stray
      # column-0 `}` at EOF. Dropping the trailing one leaves the type
      # holding its `using` and `types` closed.
      "../clausewitz/gui/applicationutils/tools_gui_dialogs.gui" => STRIP_TRAILING_BRACE,
    },
    "1.6.1.2" => {
      "gui/interaction_interfere_in_war_notification.gui" => APPEND_BRACE,
      "history/characters/castilian.txt" => TRIM_MALFORMED_DATES,
    },
    "1.8.2" => {
      "gui/artifact_details_view.gui" => nil,
      "gui/window_artifact_details.gui" => STRIP_TRAILING_BRACE,
    },
    "1.9.2.1" => {
      "common/genes/06_genes_special_accessories_headgear.txt" => nil,
      "common/genes/07_genes_special_accessories_misc.txt" => APPEND_TWO_BRACES,
      "gfx/portraits/portrait_modifiers/00_custom_legwear.txt" => APPEND_BRACE,
      "gui/shared/value_breakdown.gui" => nil,
      "gui/window_court_events.gui" => nil,
    },
    "1.11.5" => {
      "gfx/portraits/portrait_modifiers/00_custom_legwear.txt" => nil,
      "history/titles/k_transoxiana.txt" => TRIM_MALFORMED_DATES,
      # `depth=1.010000 }` closes `instance` inline, and the next line
      # closes it again, so everything after closes one level early.
      # Drop the inline close.
      "common/coat_of_arms/coat_of_arms/90_dynasties.txt" =>
        ->(data) { data.sub!(/(depth=1\.010000) \}/, '\1') },
    },
    "1.12.5" => {
      "history/characters/castilian.txt" => nil,
    },
    "1.13.2" => {
      "common/coat_of_arms/coat_of_arms/90_dynasties.txt" => nil,
      "common/genes/07_genes_special_accessories_misc.txt" => nil,
      "gui/interaction_interfere_in_war_notification.gui" => nil,
      "gui/window_artifact_details.gui" => nil,
      "history/characters/french.txt" => nil,
    },
    "1.15.0.2" => {
      "common/defines/ai/00_ai.txt" => APPEND_TWO_BRACES,
    },
    "1.16.2.3" => {
      "common/defines/ai/00_ai.txt" => nil,
      "common/genes/04_genes_special_accessories_beards.txt" => APPEND_BRACE,
      "common/schemes/scheme_types/learn_language_scheme.txt" => drop_valueless("has_domicile_parameter"),
    },
    "1.18.4" => {
      "common/genes/04_genes_special_accessories_beards.txt" => nil,
      "common/schemes/scheme_types/learn_language_scheme.txt" => nil,
      "history/titles/e_khmer.txt" => TRIM_MALFORMED_DATES,
      "history/titles/k_dvaravati.txt" => TRIM_MALFORMED_DATES,
    },
    "1.20.0.2" => {
      "history/characters/serbian.txt" => nil,
      "history/titles/e_khmer.txt" => nil,
      "history/titles/k_dvaravati.txt" => nil,
      "history/titles/k_transoxiana.txt" => nil,
    },
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

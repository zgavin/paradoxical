module Paradoxical::Games::V3
  NAME               = "Victoria 3"
  SLUG               = "v3"
  STEAM_ID           = 529340
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
  # trailing `}` is stripped. Portrait-editor DNA exports in
  # `common/dna_data` are the most common case: they're wrapped by hand
  # in `dna_<name> = { portrait_info = { … } }` with the outer `}`
  # forgotten.
  APPEND_BRACE = ->(data) { data << "\n}\n" }
  APPEND_TWO_BRACES = ->(data) { data << "\n}\n}\n" }
  STRIP_TRAILING_BRACE = ->(data) { data.sub!(/\}\s*\z/, "") }

  def self.dna name
    "common/dna_data/00_#{name}.txt"
  end

  DNA_1_7_7 = %w[
    abdul_hamid_ii arthur_balfour david_lloyd_george douglas_haig empress_myeongseong
    friedrich_engels george_curzon john_maynard_keynes joseph_chamberlain
    kemens_von_metternich provo_wallis reza_shah_pahlavi rotha_lintorn_orman tsar_alexander_03
  ].map do |name| dna(name) end.freeze

  CITY_TYPES = %w[african_wood arabic_wood asian_wood default_wood latin_mine latin_wood].map do |name|
    "gfx/map/city_data/city_types/#{name}.txt"
  end.freeze

  # Corrections are keyed by first-known-broken build, with an explicit
  # `nil` where Paradox fixed the file. 1.0.6 is the earliest build in
  # the corpus.
  CORRECTIONS = {
    "1.0.6" => {
      **CITY_TYPES.to_h do |path| [path, APPEND_BRACE] end,
      "common/genes/02_genes_accessories_hairstyles.txt" => APPEND_BRACE,
      "common/genes/03_genes_accessories_beards.txt" => APPEND_BRACE,
      "common/genes/97_genes_accessories_clothes.txt" => APPEND_BRACE,
      "common/genes/99_genes_special.txt" => APPEND_BRACE,
      "gfx/portraits/portrait_modifiers/01_clothes.txt" => APPEND_BRACE,
      "gui/frontend/frontend_bookmarks.gui" => APPEND_BRACE,
      "gfx/map/post_effects/posteffect_volumes.txt" => STRIP_TRAILING_BRACE,
      "gui/shared/button_icons.gui" => STRIP_TRAILING_BRACE,
      # Engine file beside `game/`, keyed root-relative via `..`.
      "../clausewitz/gui/applicationutils/tools_gui_dialogs.gui" => STRIP_TRAILING_BRACE,
      # An all-comment example file with one line pasted in from a diff,
      # still carrying its `+`.
      "gfx/map/spline_network/route_graphics/00_example.txt" => ->(data) { data.sub!(/^\+#/, "#") },
    },
    "1.1.2" => {
      "gui/shared/button_icons.gui" => nil,
    },
    "1.3.6" => {
      **CITY_TYPES.to_h do |path| [path, nil] end,
      "gfx/map/post_effects/posteffect_volumes.txt" => nil,
    },
    "1.5.13" => {
      "common/laws/00_slavery.txt" => APPEND_BRACE,
      "common/named_colors/00_formation_colors.txt" => APPEND_BRACE,
      "common/state_traits/06_eastern_europe_traits.txt" => APPEND_BRACE,
      # A commented-out mobilization option left its last two lines
      # (`value = 1` and the `ai_weight` close) live. Comment them too.
      "common/mobilization_options/00_mobilization_option.txt" =>
        ->(data) { data.sub!(/^(# \tai_weight = \{\r?\n)(\t\tvalue = 1\r?\n)(\t\}\r?\n)/, '\1#\2#\3') },
    },
    "1.6.2" => {
      "../clausewitz/gui/applicationutils/tools_gui_dialogs.gui" => nil,
    },
    "1.7.7" => {
      **DNA_1_7_7.to_h do |path| [path, APPEND_BRACE] end,
      "common/named_colors/00_formation_colors.txt" => nil,
      "common/state_traits/06_eastern_europe_traits.txt" => nil,
      "gfx/portraits/portrait_modifiers/01_clothes.txt" => nil,
      "gui/principle_selection_window.gui" => STRIP_TRAILING_BRACE,
      # `iconsize = [`: a typo for `{`, closed by `}` as usual.
      "gui/texticons.gui" => ->(data) { data.sub!("iconsize = [", "iconsize = {") },
    },
    "1.8.7" => {
      **DNA_1_7_7.to_h do |path| [path, nil] end,
      **%w[bal_gangadhar_tilak mahatma_gandhi rani_lakshmibai sarojni_naidu].to_h do |name|
        [dna(name), APPEND_BRACE]
      end,
      "common/genes/02_genes_accessories_hairstyles.txt" => nil,
      "common/genes/03_genes_accessories_beards.txt" => nil,
      "common/genes/97_genes_accessories_clothes.txt" => nil,
      "common/genes/99_genes_special.txt" => nil,
      "common/laws/00_slavery.txt" => nil,
      "common/mobilization_options/00_mobilization_option.txt" => nil,
      "gui/frontend/frontend_bookmarks.gui" => nil,
      "gui/principle_selection_window.gui" => nil,
    },
    "1.9.8" => {
      dna("iwasaki_yataro") => APPEND_BRACE,
      dna("zhou_xuexi") => APPEND_BRACE,
      "gfx/map/spline_network/route_graphics/00_example.txt" => nil,
      "gui/texticons.gui" => nil,
      # Both outer blocks are left open after a run of commented-out
      # characters.
      "common/history/characters/swe - sweden.txt" => APPEND_TWO_BRACES,
    },
    "1.13.0" => {
      "common/history/characters/swe - sweden.txt" => nil,
    },
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

module Paradoxical::Games::Stellaris
  NAME               = "Stellaris"
  SLUG               = "stellaris"
  STEAM_ID           = 281990
  NATIVE_PLATFORMS   = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR    = false
  LAUNCHER_FORMAT    = :sqlite
  CALENDAR           = Paradoxical::Calendars::Calendar360
  FLOAT_PRECISION    = 3

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  # A missing `}` gets one appended at EOF, which is what the engine
  # does (it implicitly closes open blocks at EOF); a single extra
  # trailing `}` is stripped.
  APPEND_BRACE = ->(data) { data << "\n}\n" }
  STRIP_TRAILING_BRACE = ->(data) { data.sub!(/\}\s*\z/, "") }

  # Corrections are keyed by first-known-broken build, with an explicit
  # `nil` where Paradox fixed the file. 2.4.1 is the corpus floor (the
  # first build shipping `launcher-settings.json`), so a file keyed
  # there may well be broken earlier too.
  CORRECTIONS = {
    "2.4.1" => {
      "gfx/models/add_ons/_add_ons_meshes.gfx" => APPEND_BRACE,

      # Titan mesh files: a stray `}` after a blank line at EOF.
      "gfx/models/ships/titans/fungoid_01/_fungoid_01_titan_meshes.gfx" => STRIP_TRAILING_BRACE,
      "gfx/models/ships/titans/mammalian_01/_mammalian_01_titan_meshes.gfx" => STRIP_TRAILING_BRACE,
      "gfx/models/ships/titans/molluscoid_01/_molluscoid_titan_meshes.gfx" => STRIP_TRAILING_BRACE,
      "gfx/models/ships/titans/plantoid_01/_plantoid_01_titan_meshes.gfx" => STRIP_TRAILING_BRACE,

      # `ion_cannon = { = {`: a doubled `= {` typo.
      "common/name_lists/HUMAN1_SC.txt" => ->(data) { data.sub!(/(ion_cannon = \{) = \{/, '\1') },

      # The government icons sit in a row at `y = @gov_icon_y`; only the
      # third has `y = -@gov_icon_y`, which would put it far off the row.
      # A typo (nothing anywhere else ever writes `-@var`), so correct
      # it to match its siblings rather than accept the syntax.
      "interface/species_ethics.gui" => ->(data) { data.sub!("y = -@gov_icon_y", "y = @gov_icon_y") },
    },

    "2.6.3" => {
      "common/name_lists/HUMAN1_SC.txt" => nil,
      "gfx/models/add_ons/_add_ons_meshes.gfx" => nil,
      "gfx/models/ships/titans/fungoid_01/_fungoid_01_titan_meshes.gfx" => nil,
      "gfx/models/ships/titans/plantoid_01/_plantoid_01_titan_meshes.gfx" => nil,
      "interface/species_ethics.gui" => nil,
    },

    "2.8.1" => {
      "gfx/particles/_necroid_portrait.gfx" => APPEND_BRACE,
    },

    "3.0.4" => {
      "gfx/models/ships/titans/mammalian_01/_mammalian_01_titan_meshes.gfx" => nil,
      "gfx/particles/_necroid_portrait.gfx" => nil,
    },

    "3.2.2" => {
      "events/terraforming_events.txt" => APPEND_BRACE,
    },

    "3.3.4" => {
      "events/terraforming_events.txt" => nil,
      "gfx/models/ships/titans/molluscoid_01/_molluscoid_titan_meshes.gfx" => nil,
    },

    "3.4.5" => {
      "common/species_names/species_00.txt" => APPEND_BRACE,
      "common/species_names/species_01.txt" => APPEND_BRACE,
      "gfx/models/ships/juggernauts/aquatics_01/aquatic_01_juggernaut.gfx" => APPEND_BRACE,
    },

    "3.5.3" => {
      "common/species_names/species_00.txt" => nil,
      "common/species_names/species_01.txt" => nil,
    },

    "3.8.4" => {
      "common/achievements.txt" => APPEND_BRACE,
      "gfx/models/ships/juggernauts/aquatics_01/aquatic_01_juggernaut.gfx" => nil,
    },

    "3.10.4" => {
      "common/achievements.txt" => nil,
    },

    "3.11.3" => {
      "events/federations_events_1.txt" => APPEND_BRACE,
    },

    "3.12.5" => {
      "events/federations_events_1.txt" => nil,
    },

    "3.13.2" => {
      "gfx/models/effects/cosmic_storms/stormbhole.gfx" => APPEND_BRACE,
    },

    "3.14.1592653" => {
      "gfx/models/effects/cosmic_storms/stormbhole.gfx" => nil,
    },

    # `defined_text { … }` never closes (no trailing newline either).
    # 4.0.23 parses clean; broken from the 4.1 line through 4.4.6.
    "4.1.7" => {
      "common/scripted_loc/scripted_loc_ruloc.txt" => APPEND_BRACE,
    },

    # New in 4.4.x (cosmic-storm "nomads" mesh definitions). The outer
    # `objectTypes = {` runs off EOF still open while every inner block
    # nests cleanly. 4.4.0 was skipped, so 4.4.1 is first-known-broken.
    "4.4.1" => {
      "gfx/models/effects/nomads.gfx" => APPEND_BRACE,
      "gfx/models/ui/nomads_frontend.gfx" => APPEND_BRACE,
    },

    # Fixed by Paradox as of 4.5.0: the closing `}` now ships.
    "4.5.0" => {
      "common/scripted_loc/scripted_loc_ruloc.txt" => nil,
    },
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

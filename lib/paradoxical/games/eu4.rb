module Paradoxical::Games::EU4
  NAME              = "Europa Universalis IV"
  SLUG              = "eu4"
  STEAM_ID          = 236850
  NATIVE_PLATFORMS  = %i[windows linux macos].freeze
  HAS_GAME_SUBDIR   = false
  LAUNCHER_FORMAT   = :sqlite
  # EU4 (jomini-v1, 2013) is mostly Windows-1252, but a handful of
  # files with non-Latin characters (Korean province names, the
  # Tengri events, the Mamluk missions) are actually UTF-8 — so the
  # smoke tries UTF-8 first and falls back to Windows-1252.
  ENCODING_FALLBACKS = ["Windows-1252"].freeze

  # Reads `rawVersion` from the game's `launcher-settings.json`.
  def self.installed_version game
    Paradoxical::Games.read_launcher_version(game)
  end

  # EU4-specific Builder helpers. Prepended onto Builder by
  # `paradoxical!` so methods defined here override the base ones.
  module DSL
    # EU4 stores variable values as either a numeric literal or a
    # reference to another variable's name. The reference form uses
    # `which = NAME` rather than the `value = NAME` that the other
    # PDS games use, so for non-numeric values we emit
    # `<op>_variable { which = X which = Y }` instead of
    # `<op>_variable { which = X value = Y }`. `export_to_variable`
    # is the lone exception — it always uses `value`.
    %w[set check change subtract multiply divide modulo round_variable_to_closest].each do |word|
      key = word.include?("variable") ? word : "#{word}_variable"

      define_method key do |which, operator, value=nil|
        value, operator = operator, '=' if value.nil?
        second_key = value.is_a?(Numeric) ? 'value' : 'which'
        l(key, p('which', which), p(second_key, operator, value)).single_line!
      end
    end
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

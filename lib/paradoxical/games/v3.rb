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

  # Portrait-editor DNA exports wrapped by hand in
  # `dna_<name> = { portrait_info = { … } }`, with the outer `}`
  # forgotten: `portrait_info` closes, then `dna_<name>` runs off EOF.
  # Every one ends in a newline, so append the missing close.
  APPEND_BRACE = ->(data) { data << "}\n" }

  CORRECTIONS = {
    # First build checked (2026-10, via the corpus); defects may be
    # older, and get re-keyed if backfilled builds show it.
    "1.13.11" => %w[
      bal_gangadhar_tilak
      iwasaki_yataro
      mahatma_gandhi
      rani_lakshmibai
      sarojni_naidu
      zhou_xuexi
    ].to_h do |name| ["common/dna_data/00_#{name}.txt", APPEND_BRACE] end,
  }

  SLOW_FILES = [].freeze

  Paradoxical::Games.register(self)
end

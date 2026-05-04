module Paradoxical::Games::CK2
  NAME             = "Crusader Kings II"
  SLUG             = "ck2"
  STEAM_ID         = 203770
  JOMINI_VERSION   = 1
  NATIVE_PLATFORMS = %i[windows linux macos].freeze

  # Game-specific DSL helpers (mixed into Builder when this game is
  # active). Empty for now; populate as concrete needs surface.
  module DSL
  end

  # path → [block, …] of corrections to apply to the raw file bytes
  # before parsing. Empty for now; populate as malformed-input cases
  # surface from the parse smoke.
  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

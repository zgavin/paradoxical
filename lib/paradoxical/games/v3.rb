module Paradoxical::Games::V3
  NAME             = "Victoria 3"
  SLUG             = "v3"
  STEAM_ID         = 529340
  JOMINI_VERSION   = 2
  NATIVE_PLATFORMS = %i[windows linux macos].freeze

  module DSL
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

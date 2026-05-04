module Paradoxical::Games::HOI4
  NAME             = "Hearts of Iron IV"
  SLUG             = "hoi4"
  STEAM_ID         = 394360
  JOMINI_VERSION   = 1
  NATIVE_PLATFORMS = %i[windows linux macos].freeze

  module DSL
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

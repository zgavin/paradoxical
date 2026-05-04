module Paradoxical::Games::CK3
  NAME             = "Crusader Kings III"
  SLUG             = "ck3"
  STEAM_ID         = 1158310
  JOMINI_VERSION   = 2
  NATIVE_PLATFORMS = %i[windows linux macos].freeze

  module DSL
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

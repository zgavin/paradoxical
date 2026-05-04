module Paradoxical::Games::Stellaris
  NAME             = "Stellaris"
  SLUG             = "stellaris"
  STEAM_ID         = 281990
  JOMINI_VERSION   = 1
  NATIVE_PLATFORMS = %i[windows linux macos].freeze

  module DSL
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

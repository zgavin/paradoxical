module Paradoxical::Games::EU4
  NAME             = "Europa Universalis IV"
  SLUG             = "eu4"
  STEAM_ID         = 236850
  JOMINI_VERSION   = 1
  NATIVE_PLATFORMS = %i[windows linux macos].freeze

  module DSL
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

module Paradoxical::Games::ImperatorRome
  NAME             = "ImperatorRome"
  SLUG             = "imperator"
  STEAM_ID         = 859580
  JOMINI_VERSION   = 1
  NATIVE_PLATFORMS = %i[windows linux macos].freeze

  module DSL
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

module Paradoxical::Games::EU5
  NAME             = "Europa Universalis V"
  SLUG             = "eu5"
  STEAM_ID         = 3450310
  JOMINI_VERSION   = 2
  # Windows-only at launch — Linux/macOS users run this via Proton/Wine.
  # `Games.executable_for` will append `.exe` accordingly.
  NATIVE_PLATFORMS = %i[windows].freeze

  module DSL
  end

  CORRECTIONS = {}

  Paradoxical::Games.register(self)
end

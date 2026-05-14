require "active_support/all"
require "pathname"
require "yaml"
require "zip"

Zip.warn_invalid_date = false

module Paradoxical
  module Elements end
  module Elements::Concerns end
  module Elements::Primitives end
  module Search end

  class << self
    def game= game
      @game = game
    end

    def game
      @game
    end
  end
end

%w{
  version

  file_parser

  builder
  game
  games
  games/corrections
  helper
  mod
  parser
  search

  elements/concerns/arrayable
  elements/concerns/impersonator
  elements/concerns/searchable

  elements/node

  elements/comment
  elements/document
  elements/list
  elements/code_block
  elements/parameter_block
  elements/property
  elements/value
  elements/yaml

  elements/primitives/color
  elements/primitives/color/rgb
  elements/primitives/color/hsv
  elements/primitives/color/hsv360
  elements/primitives/color/hex
  elements/primitives/core_extensions
  elements/primitives/date
  elements/primitives/float
  elements/primitives/integer
  elements/primitives/string

  search/function_matcher
  search/parser
  search/property_matcher
  search/rule
}.each do |file|
  require "paradoxical/#{file}"
end

# Per-game modules — registered into Paradoxical::Games on require so
# `paradoxical!` and Games.find can resolve slugs. Listed in
# chronological release order for readability.
%w{
  ck2
  eu4
  hoi4
  stellaris
  imperator_rome
  ck3
  v3
  eu5
}.each do |slug|
  require "paradoxical/games/#{slug}"
end

# Per-game game-namespaced submodules. Each game has a DSL (prepended
# onto Builder by `paradoxical!`); Stellaris additionally has a Helper
# (extended onto `main` by `paradoxical!`) and the save-file Editor it
# delegates to. Required after the main game files so reopening their
# parent modules works.
%w{
  ck2/dsl
  ck3/dsl
  eu4/dsl
  eu5/dsl
  hoi4/dsl
  imperator_rome/dsl
  stellaris/dsl
  stellaris/editor
  stellaris/helper
  v3/dsl
}.each do |path|
  require "paradoxical/games/#{path}"
end

require "paradoxical/paradoxical"

# Single entry point for mod scripts. Resolves the game slug to its
# `Paradoxical::Games::*` module, builds the Game (which pulls in the
# module's per-game constants and auto-registers per-version
# corrections), selects the playset and mod, prepends the per-game
# DSL onto Builder, and extends the top-level `main` object with
# Helper so the script can use `parse_files`, `write`, etc. without
# an explicit include.
#
#   require "paradoxical"
#   paradoxical! game: "eu5", playset: "Standard", mod: "My Mod"
#
# Helper is added to `main` (via `extend`) rather than mixed into
# Object, so the methods are callable as globals from the script's
# top level without polluting every other object in the system.
#
# `root:` and `user_directory:` override the default install / user
# paths; everything else flows from the game module's constants.
def paradoxical! game:, playset: nil, mod: nil, root: nil, user_directory: nil
  game_module = Paradoxical::Games.find(game)

  Paradoxical.game = Paradoxical::Game.new(game_module, root: root, user_directory: user_directory)
  Paradoxical.game.playset = playset if playset
  Paradoxical.game.mod = Paradoxical.game.mods.find { |m| m.name == mod } if mod

  # `prepend` (vs `include`) so DSL methods win over Builder's base
  # ones — this is how EU4's variable-method override (different
  # second-key semantics for non-numeric values) takes effect.
  Paradoxical::Builder.prepend(game_module::DSL)

  main = TOPLEVEL_BINDING.eval("self")
  main.extend(Paradoxical::Helper)
  # Game-namespaced top-level helpers (e.g. Stellaris's `edit` for
  # save-file editing). DSL handles Builder-context methods; Helper
  # handles methods that take paths/blocks and run at the script's
  # top level. Only defined when a game actually has top-level
  # helpers, so the const lookup is gated.
  main.extend(game_module::Helper) if game_module.const_defined?(:Helper, false)

  Paradoxical.game
end

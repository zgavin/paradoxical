require 'active_support/all'
require 'pathname'
require 'yaml'
require 'zip'

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
	editor
  game
  games
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

require 'paradoxical/paradoxical'

# Single entry point for mod scripts. Resolves the game slug to the
# corresponding `Paradoxical::Games::<Game>` module (constants like
# STEAM_ID, JOMINI_VERSION, NATIVE_PLATFORMS come from there), builds
# the Game, selects the playset and mod, mixes the per-game DSL into
# Builder, registers any per-game default corrections on the active
# game, and extends the top-level `main` object with Helper so the
# rest of the mod script can use `parse_files`, `write`, etc. without
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

  Paradoxical.game = Paradoxical::Game.new(
    game_module::NAME,
    executable: Paradoxical::Games.executable_for(game_module),
    jomini_version: game_module::JOMINI_VERSION,
    steam_id: game_module::STEAM_ID,
    root: root,
    user_directory: user_directory,
  )

  Paradoxical.game.playset = playset if playset
  Paradoxical.game.mod = Paradoxical.game.mods.find { |m| m.name == mod } if mod

  Paradoxical::Builder.include(game_module::DSL)

  game_module::CORRECTIONS.each do |path, blocks|
    blocks.each { |block| Paradoxical.game.add_correction(path, &block) }
  end

  TOPLEVEL_BINDING.eval('self').extend(Paradoxical::Helper)

  Paradoxical.game
end
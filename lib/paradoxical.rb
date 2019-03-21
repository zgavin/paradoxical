require 'active_support/all'
require 'parslet'
require 'zip'
require 'yaml'
require 'rutie'

Zip.warn_invalid_date = false

module Paradoxical
  module Elements end
  module Elements::Concerns end
  module Elements::Primitives end
  module Search end 
  
	class << self 
		def generate &block
			Generator.new.instance_exec &block
		end
	
		def game= game
			@game = game
		end
	
		def game
			@game
		end
	
		def mod= mod
			@mod = mod
		end
	
		def mod
			@mod
		end
	end
end

%w{
  version

  parser
  transformer
  helper
  generator
  file_parser
  game
  mod

  elements/concerns/arrayable
  elements/concerns/searchable
  elements/concerns/impersonator

  elements/node

  elements/comment
  elements/document
  elements/list
  elements/property
  elements/value

  elements/primitives/core_extensions
  elements/primitives/date
  elements/primitives/float
  elements/primitives/integer
  elements/primitives/string

  search/search
  search/parser
  search/transformer
  search/rule
  search/property_matcher
  search/function_matcher
}.each do |file|
  require "paradoxical/#{file}"
end

Rutie.new(:paradoxical).init 'Init_Rust_Parser', File.expand_path( __dir__ )
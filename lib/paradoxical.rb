require 'active_support/all'
require 'pathname'
require 'rutie'
require 'yaml'
require 'zip'

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
  
  file_parser

  game
  generator
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
  elements/property
  elements/value

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

Rutie.new(:paradoxical).init 'Init_Rust_Parser', File.expand_path( __dir__ )
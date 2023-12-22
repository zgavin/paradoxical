module Paradoxical::Helper
	def game! name,  executable: nil, root: nil, user_directory: nil
		Paradoxical.game = Paradoxical::Game.new name, executable: executable, root: root, user_directory: user_directory
	end
	
	def game
		Paradoxical.game
	end
	
	def mods
		game.mods
	end
	
	def playset! name
		game.playset = name
	end
	
  def glob s
    game.glob s
  end
	
	def mod
		game.mod
	end
	
	def exists? path
		game.mod.exists? path
	end
	
	def mod_enabled? name
		mod = mod_named(name)
		mod.present? and mod.enabled?
	end
	
	def mod_named name
		game.mod_named name
	end
	
	def mod! name
		game.mod = mods.find do |mod| mod.name == name end
	end	
	
	def common_files dir
		glob "common/#{dir}/*.txt"
	end
  
  def build &block
    Paradoxical::Builder.new.build &block
  end
  
  def document whitespace: nil, path: nil, owner: nil, &block
    children = block.nil? ? [] : build( &block )
    
    Paradoxical::Elements::Document.new children, whitespace: whitespace, path: path, owner: ( owner or mod )
  end
  
  def write file_or_path, &block
    file = if file_or_path.is_a? Paradoxical::Elements::Document then
			file_or_path.tap do |doc|
		    children = doc.instance_variable_get :@children 
		    children.concat build &block unless block.nil?
			end
		elsif file_or_path.is_a? Paradoxical::Elements::Yaml then
			file_or_path.tap do |yaml|
				values = yaml.instance_variable_get :@values 
				values.merge! build &block unless block.nil?
			end
		elsif %w{.txt .gfx .gui}.include? File.extname file_or_path then
			children = build &block
			Paradoxical::Elements::Document.new children, owner: mod, path: file_or_path
		elsif %w{.yml .yaml}.include? File.extname file_or_path then
			values = block.call
			Paradoxical::Elements::Yaml.new values, owner: mod, path: file_or_path
		else 
			raise "unhandled file type for #{file_or_path}"
		end
    
    mod.write file
  end
	
	def delete path
		game.mod.delete path
	end

	def parse_files ...
		game.parse_files(...)
	end
  
  def parse ...
    game.parse(...)
  end
	
	def edit path, &block
		Paradoxical::Editor.edit path, &block
	end
	
	def run_directly?
		caller_locations.first.path == $PROGRAM_NAME
	end
end
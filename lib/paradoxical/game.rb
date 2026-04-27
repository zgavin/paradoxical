require 'sqlite3'
require 'json'
require 'os'

class Paradoxical::Game
  include Paradoxical::FileParser
	
	attr_accessor :name, :executable, :root, :user_directory, :jomini_version, :steam_id
	attr_reader :mod, :playset
	
	def initialize name, executable: nil, root: nil, user_directory: nil, jomini_version: nil, steam_id: nil
		@name = name
		@executable = ( executable or name.downcase )
		@root = Pathname.new( ( root or default_root(name) ) )
		@file_cache = {}
		@jomini_version = (jomini_version or 1)
		@steam_id = steam_id
		
		userdir_txt_path = @root.join 'userdir.txt'
		
		if user_directory.present? then
			@user_directory = user_directory
		elsif File.exist? userdir_txt_path then
			@user_directory = File.read(userdir_txt_path).chomp
		end
		
		if @user_directory.blank? then
			@user_directory = default_user_directory name
		end
    
    @user_directory = Pathname.new @user_directory

		extend(jomini_version == 1 ? SqliteConfig : JsonConfig )
	end
	
	def mods			
		_mods.dup
	end
	
	def enabled_mods
		_enabled_mods.dup
	end
	
	def mod_named name
		mods.find do |mod| mod.name.include? name	end
	end
	
	def mod= mod
		@mod = mod
		@enabled_mods = nil
		@mod
	end

	def playset= playset
		@playset = playset
		@enabled_mods = nil
		@playset
	end
	
	def is? name
		name == self.executable
	end
  
  def exists? relative_path, mod: false
    return super relative_path if mod == false
    
    return mod.exists? relative_path unless mod.nil?
    
    return true unless mod_for_path( relative_path ).nil? 
    
    super relative_path
  end
  
	def glob relative_path
		[ super, *_enabled_mods.map do |mod| mod.glob relative_path end ].flatten.uniq.sort
	end
	
	def read relative_path, mod: false
		mod ||= mod_for_path relative_path, mod: mod unless mod == false
		
		return super relative_path unless mod.present?

		mod.read relative_path
	end
  
  def parse_file relative_path, mod: nil, mutex: nil, ignore_cache: false, encoding: nil
    mod ||= mod_for_path relative_path, mod: mod unless mod == false
    
    return super relative_path, mutex: mutex, ignore_cache: ignore_cache, encoding: encoding unless mod.present?
    
    mod.parse_file relative_path, mutex: mutex, ignore_cache: ignore_cache, encoding: encoding
  end
  
	def parse_files *files, mod: nil, encoding: nil
    mutex = Mutex.new
    
		results = files.flatten.map do |relative_path|  
      _mod = mod_for_path relative_path, mod: mod
          
			Thread.new do
				document = parse_file relative_path, mod: _mod, mutex: mutex, encoding: encoding
        
        Thread.current[:document] = document
			end
		end.map do |thread| thread.join[:document] end
      
    results.count > 1 ? results : results.first
	end
  
  private

  def mod_for_path relative_path, mod: nil
    return mod unless mod.nil?
    
    _enabled_mods.reverse_each.find do |mod| mod.exists? relative_path end 
  end
end

def default_root name 
	File.join(
		steamapps_dir,
		"common", 
		name,
		*(jomini_version == 1 ? [] : ["game"])
	)
end

def default_user_directory name
	File.expand_path(
		File.join(
			"~",
			*(OS.linux? ? [".local", "share" ] : ["Documents"]),
			"Paradox Interactive",
			name
		)
	)
end

def steamapps_dir
	@steamapps_dir ||= File.expand_path( 
		File.join(
			*(		
				OS.linux? ? ["~", ".local", "share"] :
				OS.mac? ? ["~", "Library", "Application Support"] :
				["C", "Program Files (x86)"]
			),  
			"Steam", 
			"steamapps", 
		)
	)
end

module SqliteConfig
	def db
		@db ||= SQLite3::Database.new user_directory.join("launcher-v2.sqlite")
	end

  def _mods
		@mods ||= begin
			db.execute("SELECT id, gameRegistryId  FROM mods;").map do |(id, gameRegistryId)|
				Paradoxical::Mod.new self, id, user_directory.join(gameRegistryId)
			end
		end
  end
  
  def _enabled_mods
    @enabled_mods ||= begin						 
			enabled_mods = if @playset.present? then
				db
					.execute("SELECT m.id FROM mods m join playsets_mods pm on pm.modId = m.id join playsets p on pm.playsetId = p.id where pm.enabled and p.name = '#{@playset}' order by pm.position ASC;")
					.map do |(id)| _mods.find do |mod| mod.id == id end end
			else
				_mods.dup
			end
		
			enabled_mods.delete_if do |other| other.id == @mod.id end if @mod.present?
			
			enabled_mods
		end
  end
end


module JsonConfig
  def _mods
		@mods ||= begin
			(
				Dir[File.join(steamapps_dir, "common", "workshop", "content", steam_id.to_s, "*", ".metadata", "metadata.json")] + 
				Dir[File.join(user_directory, "mod", "*", ".metadata", "metadata.json")]
			).map do |metadata_path|
				path = File.expand_path File.join(metadata_path, "..", "..") 
				steam_id =  File.basename path
				metadata = JSON.parse File.read(metadata_path, encoding: "bom|utf-8")
				name = metadata["name"]
				id = metadata["id"]
				Paradoxical::Mod.new self, id, path, name: name, steam_id: steam_id
			end
		end
  end
  
  def _enabled_mods
    @enabled_mods ||= begin			
			enabled_mods = if @playset.present? then
				playsets = JSON.parse(File.read(File.join(user_directory, "playsets.json"), encoding: "bom|utf-8"))["playsets"]
				playset = playsets.find do |p| p["name"] === self.playset end
				_mods.filter do |mod| 
					playset["orderedListMods"].any? do |entry| entry["isEnabled"] and File.basename(entry["path"]) == File.basename(mod.path) end
				end
			else
				_mods.dup
			end
		
			enabled_mods.delete_if do |other| other.name == @mod.name end if @mod.present?
			
			enabled_mods
		end
  end
end
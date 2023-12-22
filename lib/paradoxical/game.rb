require 'sqlite3'

class Paradoxical::Game
  include Paradoxical::FileParser
	
	attr_accessor :name, :executable, :root, :user_directory
	attr_reader :mod, :playset
	
	def initialize name, executable: nil, root: nil, user_directory: nil
		@name = name
		@executable = ( executable or name.downcase )
		@root = Pathname.new( ( root or File.expand_path("~/Library/Application Support/Steam/steamapps/common/#{name}" ) ) )
		@file_cache = {}
		
		userdir_txt_path = @root.join 'userdir.txt'
		
		if user_directory.present? then
			@user_directory = user_directory
		elsif File.exist? userdir_txt_path then
			@user_directory = File.read(userdir_txt_path).chomp
		end
		
		if @user_directory.blank? then
			@user_directory = File.expand_path("~/Documents/Paradox Interactive/#{name}")
		end
    
    @user_directory = Pathname.new @user_directory
	end
	
	def mods			
		_mods.dup
	end
	
	def db
		@db ||= SQLite3::Database.new user_directory.join("launcher-v2.sqlite")
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
  
  def parse_file relative_path, mod: nil, mutex: nil, ignore_cache: false
    mod ||= mod_for_path relative_path, mod: mod unless mod == false
    
    return super relative_path, mutex: mutex, ignore_cache: ignore_cache unless mod.present?
    
    mod.parse_file relative_path, mutex: mutex, ignore_cache: ignore_cache
  end
  
	def parse_files *files, mod: nil
    mutex = Mutex.new
    
		results = files.flatten.map do |relative_path|  
      _mod = mod_for_path relative_path, mod: mod
          
			Thread.new do
				document = parse_file relative_path, mod: _mod, mutex: mutex
        
        Thread.current[:document] = document
			end
		end.map do |thread| thread.join[:document] end
      
    results.count > 1 ? results : results.first
	end
  
  private
	
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

  def mod_for_path relative_path, mod: nil
    return mod unless mod.nil?
    
    _enabled_mods.reverse_each.find do |mod| mod.exists? relative_path end 
  end
end
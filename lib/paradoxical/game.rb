class Paradoxical::Game
  include Paradoxical::FileParser
  
	attr_accessor :name, :executable, :root, :user_directory
	
	def initialize name, executable: nil, root: nil, user_directory: nil
		@name = name
		@executable = ( executable or name.downcase )
		@root = Pathname.new( ( root or File.expand_path("~/Library/Application Support/Steam/steamapps/common/#{name}" ) ) )
		@file_cache = {}
		
		userdir_txt_path = @root.join 'userdir.txt'
		
		if user_directory.present? then
			@user_directory = user_directory
		elsif File.exists? userdir_txt_path then
			@user_directory = File.read(userdir_path).chomp
		else
			@user_directory = File.expand_path("~/Documents/Paradox Interactive/#{name}")
		end
    
    @user_directory = Pathname.new @user_directory
	end
	
	def mods			
		@mods ||= Dir[ user_directory.join 'mod', '*.mod' ].map do |path| Paradoxical::Mod.new self, path end
	end
	
	def enabled_mods
		return self.enabled_mods = mods if @enabled_mods.nil?
		
		@enabled_mods.dup
	end
	
	def enabled_mods= mods
		@sorted_mods = nil
		@enabled_mods = mods.dup
	end
	
	def sorted_mods
		@sorted_mods ||= enabled_mods.sort_by &:name
	end 
  
  def exists? relative_path, mod: false
    return super relative_path if mod == false
    
    return mod.exists? relative_path unless mod.nil?
    
    return true unless mod_for_path( relative_path ).nil? 
    
    super relative_path
  end
  
	def glob relative_path
		[ super, *enabled_mods.map do |mod| mod.glob relative_path end ].flatten.uniq.sort
	end
	
	def read relative_path, mod: false
		mod ||= mod_for_path relative_path, mod: mod unless mod == false
		
		return super relative_path unless mod.present?

		mod.read relative_path
	end
  
  def parse_file relative_path, mod: nil, mutex: nil
    mod ||= mod_for_path relative_path, mod: mod unless mod == false
    
    return super relative_path, mutex: mutex unless mod.present?
    
    mod.parse_file relative_path, mutex: mutex
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
  
  def mod_for_path relative_path, mod: nil
    return mod unless mod.nil?
    
    sorted_mods.find do |mod| mod.exists? relative_path end 
  end
end
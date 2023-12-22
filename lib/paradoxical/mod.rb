class Paradoxical::Mod
  include Paradoxical::FileParser
  
	attr_reader :game, :id, :path, :corrections
	
	def initialize game, id, path
		@game = game
		@id = id
		@path = Pathname.new path

    @file_cache = {}    
    @config = {}
    @corrections = {}
		
		result = parse_file path
			
		result.properties.each do |p|
      @config[p.key] = p.value
    end
	end
	
	%w{name path supported_version remote_file_id archive}.each do |key|
		define_method key do
			@config[key]
		end
	end
	
	def archive? 
		@config['archive'].present?
	end
  
  def enabled? 
    game.enabled_mods.include? self
  end
	
	def exists? relative_path
		return super unless archive?
    
		result = nil
		
		Zip::File.open( archive ) do |zip_file|
		  result = zip_file.glob( relative_path.to_s ).first.present?
		end
		
		result
	end

	def glob relative_path
    return super unless archive?

		result = nil
		
		Zip::File.open( archive ) do |zip_file|
		  result = zip_file.glob( relative_path.to_s ).map(&:name)
		end
		
		result
	end
	
	def read relative_path
		return super unless archive?

		result = nil
		
		Zip::File.open( archive ) do |zip_file|
		  result = zip_file.glob( relative_path.to_s ).first.get_input_stream.read
		end
		
		result
	end
	
	def root
		Pathname.new( path.to_s.start_with?('/') ? path :  File.join( game.user_directory, path ) )
	end
	
	def write file
		full_path = full_path_for file.path

		FileUtils.mkdir_p File.dirname full_path
		
		data = file.bom? ? "\xEF\xBB\xBF" : ""
		data << file.to_pdx
		
		File.write full_path, data
	end
	
	def delete path
		full_path = full_path_for path
		File.delete full_path if exists? full_path
		
		return unless full_path.to_s.start_with? root.to_s

		dir = full_path.dirname
		while dir.empty? and dir != root do
			File.rmdir dir
			dir = dir.dirname
		end
	end
end
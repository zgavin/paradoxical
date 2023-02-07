class Paradoxical::Mod
  include Paradoxical::FileParser
  
	attr_reader :path, :game, :corrections
	
	def initialize game, path
		@path = Pathname.new path
		@game = game
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
	
	def write_file relative_path, data=nil, language: nil, &block
    extension = File.extname( relative_path )[1..-1] 
		
		data ||= begin
			if %w{gui gfx txt}.include? extension then
				result = Paradoxical::Builder.new.build &block
      
	      document = if result.is_a? Paradoxical::Elements::Node then
	        Paradoxical::Elements::Document.new [result]
	      elsif result.is_a? Array then
	        Paradoxical::Elements::Document.new result
	      else
	        result
	      end        
      
	      document.to_pdx
	    elsif %w{yaml yml}.include? extension then
	      language ||= ( relative_path.match(/l_(\w+)\.#{extension}$/) or %w{english} ).to_a.last
      
	      result = block.call
      
	      s =  "\uFEFF"  # BOM marker
	      s << "l_#{language}:\n"
	      s + result.map do |pair| 
	        next pair.to_pdx if pair.is_a? Paradoxical::Elements::Value
	        next ' ' if pair.empty?
	        next pair.first.to_pdx if pair.count == 1

	        k,v = pair

	        " #{k.to_s}: #{v.to_s.inspect}"       
	      end.join("\n")
	    else
				block.call
			end
		end
		
		full_path = full_path_for relative_path

		FileUtils.mkdir_p File.dirname full_path
		
		File.write full_path, data
	end
end
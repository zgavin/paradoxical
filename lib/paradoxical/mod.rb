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
		Pathname.new( File.join game.user_directory, path )
	end
	
	def update_file relative_path, name: "GENERATED CONTENT", start_delimeter: nil, end_delimeter: nil, wrap_block_with_generate: nil, &block
		raise "zipped mods are read-only" if archive?
		
		full_path = full_path_for relative_path
		
		data = File.read full_path

		line_break = data.include?( "\r\n" ) ? "\r\n" : "\n"

		start_delimeter ||= "# #{name} START"
		end_delimeter ||= "# #{name} END"

		start_index = data.index start_delimeter
		
		end_index = data.index( /#{end_delimeter}#{line_break}/, start_index ) + end_delimeter.length + line_break.length - 1

		whitespace = ( data[0..(start_index-1)].scan( /^([\t ]*)\z/ ).first&.first or "" )

		wrap_block_with_generate ||= %{.gui .gfx .txt}.include? File.extname( relative_path ) 

		generated_content = if wrap_block_with_generate then
			result = Paradoxical.generate do self.instance_exec &block end
			
			document = if result.is_a? Array then 
				Paradoxical::Elements::Document.new result
			elsif result.is_a? Paradoxical::Elements::Document then
				result
			else
				Paradoxical::Elements::Document.new [result]
			end

			document.to_pdx.split("\r\n")
		else
			result = block.call
			
			if result.is_a?(Array) then
				result.flatten.map do |s| s.is_a?( Paradoxical::Elements::Value ) ? s.value : s end
			elsif result.is_a?(String) then
				result.split(/\r?\n/)
			else
				Array(result)
			end
		end
		
		generated_content.unshift ""
		generated_content.push "", end_delimeter

		generated_content.map! do |line| "#{whitespace}#{line}" end

		generated_content.unshift start_delimeter

		data[start_index..end_index] = generated_content.join(line_break) + line_break
	
		File.write full_path, data
	end
	
	def write_file relative_path, data=nil, wrap_block_with_generate: nil, language: nil, &block
    extension = File.extname( relative_path )[1..-1] 
    
		wrap_block_with_generate ||= %w{gui gfx txt}.include? extension
		
		data ||= if wrap_block_with_generate then
			result = Paradoxical.generate do
				self.instance_exec &block
			end
      
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
		
		full_path = full_path_for relative_path

		FileUtils.mkdir_p File.dirname full_path
		
		File.write full_path, data
	end
end
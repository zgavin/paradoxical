module Paradoxical::FileParser 
  def corrections
    @corrections ||= {}
  end
   
  def add_correction path, &block
    corrections[ path ] ||= []
    
    corrections[ path ] << block
  end
  
  def exists? relative_path
    File.exist? full_path_for relative_path
  end
  
	def glob relative_path
		Dir[ full_path_for relative_path ].map do |path| path.reverse.chomp( (root.to_s + '/').reverse ).reverse end
	end
  
  def read relative_path
  	File.read( full_path_for relative_path )
  end
  
  def full_path_for path
    path.to_s.start_with?('/') ? path : root.join( path )
  end
  
  def parse_file path, mutex: nil, ignore_cache: false
    document = nil
    
    mutex ||= Object.new.tap do |o| o.define_singleton_method :synchronize do |&block| block.call end end
    
    mutex.synchronize do
      document = @file_cache[path] 
    end
    
    return document unless ignore_cache or document.nil? 
    
    data = read( path ).force_encoding("windows-1252").encode("utf-8")
    
    ( corrections[ path ] or [] ).each do |block|
      block.call data
    end
    
    document = parse data, path: path
    
		mutex.synchronize do
			@file_cache[path] = document
		end
    
    return document
  end
  
	def parse data, path: nil
		document = Paradoxical::Parser.parse data
  
    document.instance_variable_set( :@owner, self )
    document.instance_variable_set( :@path, path )
		document.instance_variable_set( :@line_break, data.include?("\r") ? "\r\n" : "\n")
    
    document
  rescue Paradoxical::Parser::ParseError => error
    puts "Error parsing #{path}#{ self.is_a?(Paradoxical::Mod) ? " ( #{name} )" : '' }" unless path.nil?
    puts error.message
    exit
	end  
end
class Paradoxical::Elements::Yaml
  attr_reader :path, :owner, :language, :extension
  
  def initialize values={}, path: nil, owner: nil
		@values = values      
    @path = path
    @owner = owner
		@extension = File.extname( path )[1..-1]
		@language = ( path.match(/_l_(\w+)\.#{@extension}$/)&.to_a&.last or "english" )
  end
  
	def values
		@values.dup
	end
	
  def dup path: nil, owner: nil
    self.class.new @values.dup, path: (path or self.path) , owner: (owner or self.owner)
  end
  
  def eql? other
    other.is_a?( Yaml ) and @values.eql?( other.send( :values ) )
  end
  
  def == other
    other.is_a?( Yaml ) and @values == other.send( :values )
  end
  
  def hash
    @values.hash
  end
	
	def to_pdx    
    s = "l_#{language}:\n"
    s + @values.map do |(k, v)| 
			" #{k.to_s}: #{v.to_s.inspect}"       
    end.join("\n")
	end
	
	def bom?
		true
	end
  
	def defines
		properties.select do |p| p.key.starts_with? '@' end.map do |p| [p.key, p.value] end.to_h
	end
  
  def vanilla?
    @owner.is_a? Paradoxical::Game
  end
end
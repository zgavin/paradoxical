class Paradoxical::Elements::Value < Paradoxical::Elements::Node  
  attr_accessor :value
  
  def self.empty_line
    empty_line = self.new Paradoxical::Elements::Primitives::String.new '', is_quoted: false
    
    empty_line.instance_variable_set :@empty_line, true
    
    empty_line
  end
  
  def initialize value, whitespace: nil
		self.value = value
		self.whitespace = whitespace
  end

  def dup
    self.class.new value.dup, whitespace: whitespace.dup
  end
  
  def eql? other
    other.is_a?( self.class ) and @value.eql?( other.value )
  end
  
  def == other
    other.is_a?( self.class ) and @value == other.value
  end
  
  def hash
    @value.hash
  end
  
  def to_pdx indent: nil, buffer: ""				
    buffer << ( whitespace&.first or indent or '' ) << value.to_pdx
  end
  		
  def inspect
    "#<Paradoxical::Elements::Value text=#{value.inspect}>"
  end
  
  def reset_whitespace!
    self.whitespace = nil
  end	
  
  def empty_line? 
    @empty_line == true
  end
end
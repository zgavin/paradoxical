class Paradoxical::Elements::Property < Paradoxical::Elements::Node
  attr_accessor :key, :value, :operator

  def initialize key, operator, value=nil, whitespace: nil
		if value.nil? then
			value = operator
			operator = '='
		end
		
    self.key = key
    self.value = value
		self.operator = operator
    self.whitespace = whitespace
  end

  def dup key: nil
    self.class.new (key or @key).dup, operator.dup, value.dup, whitespace: whitespace.dup 
  end
  
  def eql? other
    other.is_a?( Paradoxical::Elements::Property ) and @key.eql?( other.key ) and @value.eql?( other.value )
  end
  
  def == other
    other.is_a?( Paradoxical::Elements::Property ) and @key == other.key and @value == other.value
  end
  
  def hash
    [@key, @value].hash
  end
  
  def to_pdx indent: nil, buffer: ""
		whitespace = ( self.whitespace or [] )
		
		prefix   = ( whitespace[0] or indent )
		leading  = ( whitespace[1] or ' ' )
		trailing = ( whitespace[2] or ' ' )
		
		buffer << prefix << key.to_pdx << leading << operator << trailing << value.to_pdx
  end
  
  def inspect
    "#<Paradoxical::Elements::Property key=#{key.inspect} value=#{value.inspect}>"
  end
  
  def - value
    self.value - value
  end
  
  def + value
    self.value + value
  end
  
  def reset_whitespace!
    self.whitespace = nil
		
		self
  end	
end
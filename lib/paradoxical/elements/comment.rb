class Paradoxical::Elements::Comment < Paradoxical::Elements::Node
  attr_accessor :text, :marker

  def initialize text, whitespace: nil, marker: "#"
    self.text = text
		self.whitespace = whitespace
    self.marker = marker
  end

  def dup
    self.class.new text.dup, whitespace: whitespace.dup, marker: marker.dup
  end

  def to_pdx indent: nil, buffer: ""
    buffer << ( whitespace&.first or indent or "" ) << marker << text
  end
  
  def inspect
    "#<Paradoxical::Elements::Comment text=#{text.inspect}>"
  end
  
  def reset_whitespace!
    self.whitespace = nil
  end	
end
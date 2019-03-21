class Paradoxical::Elements::Comment < Paradoxical::Elements::Node
  attr_accessor :text

  def initialize text, whitespace: nil
    self.text = text
		self.whitespace = whitespace
  end

  def dup
    self.class.new text.dup, whitespace: whitespace.dup
  end

  def to_pdx indent: nil, buffer: ""
    buffer << ( whitespace&.first or indent or "" ) << '#' << text
  end
  
  def inspect
    "#<Paradoxical::Elements::Comment text=#{text.inspect}>"
  end
  
  def reset_whitespace!
    self.whitespace = nil
  end	
end
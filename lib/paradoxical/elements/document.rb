class Paradoxical::Elements::Document
  include Paradoxical::Elements::Concerns::Arrayable
  include Paradoxical::Elements::Concerns::Searchable

  attr_reader :path, :whitespace, :owner
  
  def initialize children, whitespace: nil
    @children = children
    @whitespace = whitespace
      
    @children.each do |obj| obj.send( :parent=, self ) end
      
    @owner = nil 
  end
  
  def dup children: nil
    self.class.new ( children or @children ).map( &:dup ), whitespace: @whitespace.dup
  end
  
  def eql? other
    other.is_a?( Document ) and @children.eql?( other.send( :children ) )
  end
  
  def == other
    other.is_a?( Document ) and @children == other.send( :children )
  end
  
  def hash
    @children.hash
  end
  
	def to_pdx
    buffer = ""
    
		@children.each_with_index do |obj,i|
			indent = i == 0 ? '' : "\r\n"
			

			obj.whitespace ||=  [indent, nil, nil, nil] 
			obj.to_pdx buffer: buffer
		end 
    
    buffer << ( whitespace&.first or '' )
	end
  
	def defines
		properties.select do |p| p.key.starts_with? '@' end.map do |p| [p.key, p.value] end.to_h
	end
  
  def vanilla?
    @owner.is_a? Paradoxical::Game
  end
end
class Paradoxical::Elements::Document
  include Paradoxical::Elements::Concerns::Arrayable
  include Paradoxical::Elements::Concerns::Searchable

  attr_reader :path, :whitespace, :owner
  
  def initialize children=[], whitespace: nil, path: nil, owner: nil, bom: false
    @children = children
    @whitespace = whitespace
		@bom = bom
      
    @children.each do |obj| obj.send( :parent=, self ) end
      
    @path = path
    
    @owner = owner
  end
  
  def dup children: nil, path: nil
    self.class.new ( children or @children ).map( &:dup ), whitespace: @whitespace.dup, path: path, bom: @bom
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
	
	def line_break
		@line_break ||= "\n"
	end
  
	def to_pdx
    buffer =  ""
    
		@children.each_with_index do |obj,i|
			indent = i == 0 ? '' : line_break
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
	
	def bom? 
		@bom
	end
	
  def reset_whitespace!
    @whitespace = nil
    
		@children.each do |object|
      if object.respond_to? :reset_whitespace! then
				object.reset_whitespace!
			end
		end
				
		self
  end
	
	def reset_line_breaks!
		descendents
			.flat_map do |n| n.whitespace end
			.compact
			.each do |s| s.gsub! /\r\n?/, "\n" end
				
		@line_break = "\n"
		
		self
	end
end
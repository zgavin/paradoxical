class Paradoxical::Elements::List < Paradoxical::Elements::Node
  include Paradoxical::Elements::Concerns::Arrayable
  include Paradoxical::Elements::Concerns::Searchable
  
  attr_accessor :key, :operator

  def initialize key, children, operator: "=", whitespace: nil
    @key = key
    @children = children
		@operator = operator
    @whitespace = whitespace
    
    @children.each do |object| 
      raise ArgumentError.new "Must be Paradoxical::Elements::Node: #{object.inspect}" unless object.is_a? Paradoxical::Elements::Node
      
      object.send( :parent=, self ) 
    end
  end

  def dup children: nil, key: nil
    self.class.new( (key or @key).dup, ( children or @children ).map( &:dup ), whitespace: @whitespace.dup )
  end
  
  def eql? other
    other.is_a?( Paradoxical::Elements::List ) and @key.eql?( other.key ) and @children.eql?( other.send( :children ) )
  end
  
  def == other
    other.is_a?( Paradoxical::Elements::List ) and @key == other.key and @children == other.send( :children )
  end
  
  def hash
    [@key, *@children].hash
  end
  
	def line_break
		document&.line_break or "\n"
	end
	
  def to_pdx indent: 0, buffer: ""
		whitespace = ( self.whitespace or [] ) 
		
		current_indent = line_break + ("\t" * indent)
    
    buffer << ( whitespace[0] or current_indent )
    
    unless key == false then
      buffer << key.to_s
      buffer << ( whitespace[1] or ' ' )
      buffer << operator
      buffer << ( whitespace[2] or ' ' )
    end
    
    buffer << '{'
    
    @children.each do |object| 
      if object.is_a? Paradoxical::Elements::List then
        object.to_pdx indent: indent + 1, buffer: buffer 
      else
        object.to_pdx indent: "#{current_indent}\t", buffer: buffer 
      end
    end 
    
    buffer << ( whitespace[3] or current_indent )
    buffer << '}'
    
    buffer
  end
  
  def inspect
    "#<Paradoxical::Elements::List key=#{key.inspect} children=#{children.inspect} >"
  end
	
	def single_line! indent: nil
		self.whitespace = [ indent, ' ', ' ', ' ' ]
		
		@children.each do |object|
			if object.is_a? Paradoxical::Elements::List then
				object.single_line! indent: ' '
			elsif object.is_a? Paradoxical::Elements::Property then
				object.whitespace = [' '] * 3
			elsif object.is_a? Paradoxical::Elements::Value then
				object.whitespace = [' ']
			elsif object.respond_to? :whitespace= then
				object.whitespace = [' ']
			end
		end
				
		self
	end
  
  def singleton? 
    return false if @children.count != 1
    
    child = @children.first
    
    return false unless child.respond_to? :key
    
    return true if child.is_a? Paradoxical::Elements::Property
    return true if %w{add_resource resource_stockpile_compare}.include? child.key
    return true if /_variable$/ =~ child.key    
    
    false
  end
  
  def reset_whitespace!
    self.whitespace = nil
    
		@children.each do |object|
      if object.respond_to? :reset_whitespace! then
				object.reset_whitespace!
			end
		end
				
		self
  end
end
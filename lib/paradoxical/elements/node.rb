class Paradoxical::Elements::Node
  attr_reader :parent
  
  attr_accessor :whitespace
  
  def document
    return nil if @parent.nil?
    
    @parent.is_a?( Paradoxical::Elements::Document ) ? @parent : @parent.document 
  end
  
  def remove
    @parent&.delete self
    
    self
  end
  
  def insert_before *objects, offset: 0
    raise ArgumentError.new "Cannot insert into nil parent" if @parent.nil?
    
  	index = @parent.index(self) + offset

  	@parent.insert index, *objects
    
    objects.count == 1 ? objects.first : objects
  end
  
  def insert_after *objects, offset: 0
    raise ArgumentError.new "Cannot insert into nil parent" if @parent.nil?
    
  	index = @parent.index( self ) + offset + 1

  	@parent.insert index, *objects
    
    objects.count == 1 ? objects.first : objects
  end
  
  def replace! object
    raise ArgumentError.new "Cannot replace a node with nil parent" if @parent.nil?
    
    index = parent.find_index do |obj| obj.equal? self end
    
    insert_after object
    
    object.whitespace = self.whitespace.dup
    
    @parent.delete_at index
    
    object
  end
  
  def ancestors up_to: nil
    parent.is_a?( Paradoxical::Elements::Document ) or parent == up_to ? [@parent] : [@parent, *@parent.ancestors]
  end
  
  def siblings
    @parent.nil? ? [] : @parent.send(:children) - [self]
  end
	
	def line_break 
		@line_break ||= ( parent&.line_break or "\n" )
	end
  
  private 
  
  def parent= parent
    raise ArgumentError.new "must be Paradoxical::Elements::List, Paradoxical::Elements::Document, or nil" unless parent.nil? or parent.is_a? Paradoxical::Elements::List or parent.is_a? Paradoxical::Elements::Document
    
    @parent.delete self unless @parent.nil? or parent.nil?
    
		@line_break = nil
		
    @parent = parent
  end
end
class Paradoxical::Search::FunctionMatcher
  attr_accessor :name, :arguments

  def initialize name, arguments: []
    @name = name
    @arguments = arguments
  end

  def matches? node
    send( name.underscore, node )
  end

  def comment node
    return false unless node.is_a? Paradoxical::Elements::Comment 
    
    return true if arguments.empty?
    
    arguments.first.is_a?(Regexp) ? arguments.first =~ node.text : node.text.include?( arguments.first.to_s )
  end

  def list node
    node.is_a? Paradoxical::Elements::List
  end

  def property node
    node.is_a? Paradoxical::Elements::Property
  end
  
  def keyable node
    node.respond_to? :key
  end

  def value node
    node.is_a? Paradoxical::Elements::Value
  end

  def first_child node
    node == node.parent&.send(:children)&.first
  end

  def last_child node
    node == node.parent&.send(:children)&.last
  end

  def nth_child node
    node == node.parent&.send(:children)&.at( arguments.first )
  end
  
  def value node
    node.value == arguments.first
  end

  def value_matches node
    node.respond_to?( :value ) and arguments.first.is_a?(Regexp) ? arguments.first =~ node.value.to_s : node.value.to_s.include?( arguments.first.to_s )
  end
  
  def key_matches node
    node.respond_to?( :key ) and arguments.first.is_a?(Regexp) ? arguments.first =~ node.key : node.key.include?( arguments.first.to_s )
  end
end
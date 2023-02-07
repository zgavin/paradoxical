class Paradoxical::Search::Rule 
  attr_accessor :key, :property_matchers, :function_matchers, :combinator

  # rutie seemingly has no way to pass keyword arguments to ruby 3, so we expose an optional opts argument and a splat then merge them
  def initialize key, opts={}, **kwargs
    ({ id: nil, name: nil, property_matchers: [], function_matchers: [], combinator: nil }).merge(opts).merge(kwargs) => { id:, name:, property_matchers:, function_matchers:, combinator: }
    @combinator = combinator
    @key = key.blank? ? '*' : key.downcase
    @property_matchers = property_matchers
    @function_matchers = function_matchers

    @property_matchers << Paradoxical::Search::PropertyMatcher.new( 'id', operator: '=', value: id ) unless id.nil?
    @property_matchers << Paradoxical::Search::PropertyMatcher.new( 'name', operator: '=', value: name ) unless name.nil?
  end

  def matches? node
    return false unless key == '*' or ( node.respond_to?(:key) and key == node.key.to_s.downcase )

    return false unless property_matchers.all? do |p| p.matches? node end
    
    return false unless function_matchers.all? do |p| p.matches? node end

    true
  end
  
  def objects_for node
    case @combinator
    when '>'
      node.send :children
    when '~'
      node.siblings
    else
      node.descendents
    end
  end
end
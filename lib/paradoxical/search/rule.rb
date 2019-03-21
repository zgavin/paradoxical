class Paradoxical::Search::Rule 
  attr_accessor :key, :property_matchers, :function_matchers, :combinator

  def initialize key, id: nil, name: nil, property_matchers: [], function_matchers: [], combinator: nil
    @combinator = combinator
    @key = key.blank? ? '*' : key.downcase
    @property_matchers = property_matchers
    @function_matchers = function_matchers

    @property_matchers << Paradoxical::Search::PropertyMatcher.new( 'id', operator: '=', value: id ) unless id.nil?
    @property_matchers << Paradoxical::Search::PropertyMatcher.new( 'name', operator: '=', value: name.first ) unless name.nil? # for some reason name gets passed as an array
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
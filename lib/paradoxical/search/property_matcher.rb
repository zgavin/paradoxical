class Paradoxical::Search::PropertyMatcher
  attr_accessor :key, :operator, :value

  # rutie seemingly has no way to pass keyword arguments to ruby 3, so we expose an optional opts argument and a splat then merge them
  def initialize key, opts={}, **kwargs
    { operator: nil, value: nil }.merge(opts).merge(kwargs) => {  operator:, value: }
    @key = key.downcase
    @operator = operator
    @value = value
  end

  def matches? node
    return false unless node.is_a? Paradoxical::Elements::Document or node.is_a? Paradoxical::Elements::List
    
    properties = node.send(:children).select do |node| node.is_a? Paradoxical::Elements::Property and node.key.downcase == key end

    return false if properties.empty?

    return true if operator.nil? or value.nil?
    
    properties.any? do |property|
      tmp = value
      tmp = tmp.to_i if property.value.is_a? Integer
      tmp = tmp.to_f if property.value.is_a?(Float) or property.value.is_a?(Paradoxical::Elements::Primitives:: Float)
      
      case operator
      when '='
        property.value == tmp
      when '>='
        property.value >= tmp
      when '<='
        property.value <= tmp
      when '>'
        property.value > tmp
      when '<'
        property.value < tmp
      when '~='
        property.value.to_s.include? value.to_s
      when '^='
        property.value.to_s.start_with? value.to_s
      when '$='
        property.value.to_s.end_with? value.to_s
      else
        false
      end
    end    
  end
end
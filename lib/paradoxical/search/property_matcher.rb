class Paradoxical::Search::PropertyMatcher
  # `case_sensitivity` carries the trailing `i`/`s` flag the grammar
  # captures inside `[ … ]`. `#matches?` doesn't branch on it yet, but
  # storing it preserves the parsed information so a future case-folding
  # implementation has the data it needs and so the Rust caller's
  # keyword set matches the Ruby signature exactly.
  attr_accessor :key, :operator, :value, :case_sensitivity

  def initialize key, operator: nil, value: nil, case_sensitivity: nil
    @key = key.downcase
    @operator = operator
    @value = value
    @case_sensitivity = case_sensitivity
  end

  def matches? node
    return false unless node.is_a? Paradoxical::Elements::Document or node.is_a? Paradoxical::Elements::List

    properties = node.send(:children).select do |node|
      node.is_a? Paradoxical::Elements::Property and node.key.downcase == key
    end

    return false if properties.empty?

    return true if operator.nil? or value.nil?

    properties.any? do |property|
      tmp = value
      tmp = tmp.to_i if property.value.is_a? Integer
      tmp = tmp.to_f if property.value.is_a?(Float) or property.value.is_a?(Paradoxical::Elements::Primitives::Float)

      case operator
      when "="
        property.value == tmp
      when ">="
        property.value >= tmp
      when "<="
        property.value <= tmp
      when ">"
        property.value > tmp
      when "<"
        property.value < tmp
      when "~="
        property.value.to_s.include? value.to_s
      when "^="
        property.value.to_s.start_with? value.to_s
      when "$="
        property.value.to_s.end_with? value.to_s
      else
        false
      end
    end
  end
end

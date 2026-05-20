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

    # The `key.is_a?(String)` guard skips compound-keyed entries (PDX
    # save files use a List on the LHS of `=`); a name selector can't
    # match a structural key. See MODERNIZATION.md phase 10.
    properties = node.send(:children).select do |node|
      node.is_a? Paradoxical::Elements::Property and node.key.is_a?(String) and node.key.downcase == key
    end

    return false if properties.empty?

    return true if operator.nil? or value.nil?

    properties.any? do |property|
      tmp = value
      tmp = tmp.to_i if property.value.is_a? Integer
      # `Primitives::Float` is BigDecimal-backed (8d), and
      # Impersonator's `is_a?` override makes it answer true to
      # `is_a?(::BigDecimal)` — so the explicit Primitives::Float
      # check is redundant. Split Float vs BigDecimal so Ruby Floats
      # match via Float#== (binary-FP semantics) and BigDecimals match
      # exactly via BigDecimal#== — avoids the
      # `BigDecimal("0.1") != 0.1` precision gotcha.
      tmp = tmp.to_f if property.value.is_a? Float
      tmp = tmp.to_d if property.value.is_a? BigDecimal

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

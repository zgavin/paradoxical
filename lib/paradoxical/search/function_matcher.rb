class Paradoxical::Search::FunctionMatcher
  attr_accessor :name, :arguments

  def initialize name, arguments: []
    @name = name
    @arguments = arguments
  end

  def matches? node
    send(name.underscore, node)
  end

  def comment node
    return false unless node.is_a? Paradoxical::Elements::Comment

    return true if arguments.empty?

    arguments.first.is_a?(Regexp) ? arguments.first =~ node.text : node.text.include?(arguments.first.to_s)
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

  def first_child node
    node == node.parent&.send(:children)&.first
  end

  def last_child node
    node == node.parent&.send(:children)&.last
  end

  def nth_child node
    node == node.parent&.send(:children)&.at(arguments.first)
  end

  def value node
    (arguments.nil? or arguments.empty?) ? node.is_a?(Paradoxical::Elements::Value) : node.value == arguments.first
  end

  def value_matches node
    return false unless node.respond_to? :value

    arg = arguments.first
    arg.is_a?(Regexp) ? arg =~ node.value.to_s : node.value.to_s.include?(arg.to_s)
  end

  def key_matches node
    return false unless node.respond_to? :key
    # String and VariableRef keys are both name-string-like (VariableRef's
    # `to_s` returns the source `@foo` form). Compound-keyed entries
    # (List on the LHS of `=` in PDX saves) can't match regex / substring
    # tests; skip them. See MODERNIZATION.md phase 10.
    return false unless node.key.is_a?(String) or node.key.is_a?(Paradoxical::Elements::Primitives::VariableRef)

    arg = arguments.first
    arg.is_a?(Regexp) ? arg =~ node.key.to_s : node.key.to_s.include?(arg.to_s)
  end

  # Nested search: re-runs the argument as a search rooted at `node`,
  # matching when that nested search finds at least one node. Only
  # container nodes (List / Document) are searchable, so leaf nodes
  # (Property, Value, Comment) — which `Rule#matches?` also feeds in —
  # simply don't match.
  def has node
    return false unless node.respond_to? :find

    node.find(arguments.first).present?
  end
end

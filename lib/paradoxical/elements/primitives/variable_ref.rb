class Paradoxical::Elements::Primitives::VariableRef
  # PDX variable reference — `@varname`. The engine substitutes the
  # named definition's value at parse time; on the Ruby side, the
  # reference round-trips literally and `#resolve` walks the AST to
  # find the defining property whenever a caller wants the value.
  #
  # Lifted out of `Primitives::String` in phase 8e since `@varname`
  # is semantically a value reference, not opaque text. Other
  # `@`-using patterns that share the sigil for unrelated runtime
  # operators (HOI4 `key@modifier` dynamic accessor, Stellaris
  # `event_target:name@suffix`, EU5 template `@@var`, Stellaris
  # parameter splice `@$NAME$_text`, math `@[expr]`) all stay as
  # `Primitives::String` per the grammar — the var_ref rule only
  # matches token-leading `@` followed by a bare identifier.
  #
  # Immutable value-state. Raw bytes round-trip via `to_pdx`; `name`
  # is the identifier without the leading `@`. Equality / hashing are
  # name-based (two refs to `@foo` are equal regardless of raw bytes —
  # the parser only ever produces one canonical form anyway, but the
  # builder accepts shapes like `var_ref("foo")` vs `var_ref("@foo")`
  # that normalize to the same name).
  #
  # `@owner` is contextual state, not value state — it's the
  # containing Property/Value, set by the parser at construction and
  # by `Property`/`Value` setters when a VariableRef is assigned into
  # a tree. `#resolve` uses it to find the AST entry point; without
  # an owner the reference is detached and resolution raises.

  include Comparable

  attr_reader :raw, :name
  attr_accessor :owner

  def initialize raw
    @raw = raw.to_s

    raise ArgumentError, "expected @-prefixed name, got #{@raw.inspect}" unless @raw.start_with?("@")

    @name = @raw[1..]

    raise ArgumentError, "VariableRef name cannot be empty" if @name.empty?
  end

  def to_pdx
    @raw
  end

  def to_s
    @raw
  end

  def dup
    self.class.new @raw.dup
  end

  # Walk up from `@owner`, scanning each enclosing scope for a property
  # whose *key* is a VariableRef with the same name; if the value found
  # is itself a VariableRef, follow the chain through to a concrete
  # value. Cycle-detects by name: `@a = @b`, `@b = @a` raises rather
  # than looping forever.
  #
  # Raises if the ref is detached (no owner) or if no matching
  # definition is found in any ancestor scope. PDX engine semantics
  # don't restrict definitions to lexically-earlier siblings — defs
  # anywhere in scope are visible — so the scan covers all siblings
  # at each ancestor level.
  def resolve
    visited = Set.new
    current = self

    loop do
      raise "VariableRef cycle: @#{visited.to_a.join(" -> @")} -> @#{current.name}" if visited.include?(current.name)

      visited << current.name

      value = current.send(:lookup_definition_value)

      return value unless value.is_a?(Paradoxical::Elements::Primitives::VariableRef)

      current = value
    end
  end

  protected

  # Single-hop definition lookup. The `key.equal?(self)` short-circuit
  # handles the def-site case — calling `#resolve` on a key-side
  # var-ref (the LHS of `@foo = 5`) returns its own definition's
  # value. The siblings scan handles the use-site case, walking up
  # ancestor scopes since the engine's lexical visibility is upward.
  def lookup_definition_value
    raise "VariableRef #{@raw} is detached — call #resolve only on refs reachable from a Document" if @owner.nil?

    if @owner.is_a?(Paradoxical::Elements::Property) and @owner.key.equal?(self) then
      return @owner.value
    end

    node = @owner

    while node and node.respond_to?(:parent) and not node.parent.nil?
      node.siblings.each do |sibling|
        next unless sibling.is_a?(Paradoxical::Elements::Property)
        next unless sibling.key.is_a?(Paradoxical::Elements::Primitives::VariableRef)
        next unless sibling.key.name == @name

        return sibling.value
      end

      node = node.parent
    end

    raise "VariableRef #{@raw} could not be resolved — no @#{@name} definition found in scope"
  end

  public

  def <=> other
    return nil unless other.is_a?(Paradoxical::Elements::Primitives::VariableRef)

    @name <=> other.name
  end

  def == other
    other.is_a?(Paradoxical::Elements::Primitives::VariableRef) and @name == other.name
  end

  def eql? other
    self == other
  end

  def hash
    [self.class, @name].hash
  end
end

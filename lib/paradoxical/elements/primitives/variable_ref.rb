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

  # Walk up from `@owner`, scanning each enclosing list/document for a
  # property whose *key* is a VariableRef with the same name. Returns
  # the property's value (which may itself be a VariableRef — callers
  # that want a fully-evaluated value can call `#resolve` again).
  #
  # Raises if the ref is detached (no owner) or if no matching
  # definition is found in any ancestor scope. PDX engine semantics
  # don't restrict definitions to lexically-earlier siblings — defs
  # anywhere in scope are visible — so the scan covers all siblings.
  def resolve
    raise "VariableRef #{@raw} is detached — call #resolve only on refs reachable from a Document" if @owner.nil?

    node = @owner

    while node and node.respond_to?(:parent) and not node.parent.nil?
      node.parent.each do |sibling|
        next unless sibling.is_a?(Paradoxical::Elements::Property)
        next unless sibling.key.is_a?(self.class)
        next unless sibling.key.name == @name

        return sibling.value
      end

      node = node.parent
    end

    raise "VariableRef #{@raw} could not be resolved — no @#{@name} definition found in scope"
  end

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

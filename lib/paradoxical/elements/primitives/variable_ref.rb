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

  # Auto-coerce a raw `"@foo"` String into a typed VariableRef so DSL
  # callers don't have to wrap every reference in `var_ref(...)`.
  # Only coerces strings that match the grammar's `var_ref` rule
  # exactly: `@` + letter-or-digit-first-char + word chars. Whitespace
  # or anything else in the tail (`"@foo bar"`, `"@foo.bar"`) stays a
  # String — the engine would reject it as an invalid name shape, so
  # typing it as a ref would lie about the AST.
  #
  # Other `@`-sigil shapes (`@@var` template indirect, `@$NAME$_text`
  # parameter splice, `@[expr]`/`@\[expr]` computation) stay as
  # Strings — they're distinct runtime operators sharing the sigil.
  NAME_PATTERN = /\A@[A-Za-z0-9]\w*\z/.freeze

  def self.coerce value
    return value unless value.instance_of?(::String)
    return value unless NAME_PATTERN.match?(value)

    new value
  end

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
  # value.
  #
  # Returns `nil` for unresolved cases — missing definition or a
  # cyclical reference (`@a = @b`, `@b = @a`). Mirrors how the engine
  # itself handles these: error.log reports "Failed to find a valid
  # event target link" and the runtime substitutes 0, so a strict raise
  # here would be louder than the engine and break mods the engine
  # would still run. Honest `nil` lets callers decide — phase 9's
  # warning channel will surface these as warnings rather than the
  # silent-zero fallback the engine uses.
  #
  # Still raises when the ref is detached (no owner) — that's a
  # programmer error (resolve called on a ref built outside the AST),
  # distinct from a mod-content issue.
  def resolve
    visited = Set.new
    current = self

    loop do
      return nil if visited.include?(current.name)

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
  # Returns `nil` when no definition exists in any ancestor scope.
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

    nil
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

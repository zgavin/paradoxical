class Paradoxical::Elements::Primitives::Operator
  # A comparison operator used as a value rather than between a key
  # and value — `OPERATOR = <=`, a scripted trigger argument that the
  # trigger body splices into operator position
  # (`count $OPERATOR$ $COUNT$`). Its own primitive rather than a
  # `Primitives::String` because the engine tokenizes it as an
  # operator: lumping it in with strings would let invalid text
  # through wherever a mod writes one.
  #
  # Only the comparison operators parse as values (see `operator_value`
  # in script.pest); `=` and `?=` never do.
  #
  # Immutable, same shape as `Primitives::Percentage`.

  COMPARISONS = %w[== != >= <= > <].freeze

  attr_reader :raw

  def initialize raw
    raw = raw.to_s
    raise ArgumentError, "not a comparison operator: #{raw.inspect}" unless COMPARISONS.include? raw

    @raw = raw
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

  def == other
    other.is_a?(Paradoxical::Elements::Primitives::Operator) and raw == other.raw
  end

  def eql? other
    self == other
  end

  def hash
    [self.class, raw].hash
  end
end

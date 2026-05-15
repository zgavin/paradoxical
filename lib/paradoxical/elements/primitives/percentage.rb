class Paradoxical::Elements::Primitives::Percentage
  # PDX percentage primitive — `50%`, `-12.5%`, `+10.00%%`. Lifted
  # out of `Primitives::String` in phase 8e since the engine treats
  # percentages as numeric values, not opaque strings, and DSL math
  # needs the underlying number.
  #
  # The raw byte string round-trips via `to_pdx`. `value` returns
  # the literal number (the part before the trailing `%`s) as a
  # `BigDecimal` so precision survives arithmetic — matches the 8d
  # Float backing. `fraction` returns `value / 100` for the
  # conventional 0..1-style interpretation a caller might want.
  #
  # No range validation. Empirically all five games ship negative
  # percentages (`-100%` and beyond) and percentages above 100%
  # (HOI4 has 13k+ uses of `>100%`). Multi-`%` (`50%%`) is a
  # localization-template escape — engine-presentation only; the
  # underlying value is the leading number, so we strip all trailing
  # `%` for `value`.

  include Comparable

  attr_reader :raw

  def initialize raw
    @raw = raw.to_s
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

  # Literal numeric part before the trailing `%`s. `"50%"` → `50`,
  # `"-12.5%"` → `-12.5`, `"+10.00%%"` → `10`.
  def value
    BigDecimal(@raw.sub(/%+\z/, ""))
  end

  # Conventional 0..1 fraction. `50%` → `0.5`. Unbounded — HDR-style
  # values flow through (`200%` → `2.0`).
  def fraction
    value / 100
  end

  def <=> other
    return nil unless other.is_a?(Paradoxical::Elements::Primitives::Percentage)

    value <=> other.value
  end

  def == other
    other.is_a?(Paradoxical::Elements::Primitives::Percentage) and value == other.value
  end

  def eql? other
    self == other
  end

  def hash
    [self.class, value].hash
  end
end

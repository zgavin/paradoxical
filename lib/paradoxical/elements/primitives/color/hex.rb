class Paradoxical::Elements::Primitives::Color::Hex < Paradoxical::Elements::Primitives::Color
  # Hex carries a single `0x......` byte string rather than typed
  # numeric components. The parser hands it through as-is so
  # round-trip is byte-identical; conversion to a typed integer
  # value (or to RGB) is a phase 8 follow-up.

  def initialize literal, whitespace: nil
    @literal = literal
    @whitespace = whitespace || []
  end

  attr_accessor :literal

  def dup
    self.class.new @literal.dup, whitespace: @whitespace.dup
  end

  def components
    [@literal]
  end

  def colors
    [@literal]
  end

  def to_pdx
    iter = @whitespace.each
    next_ws = ->(default = " ") { iter.next rescue default }

    buffer = String.new(type)
    buffer << next_ws.call
    buffer << "{"
    buffer << next_ws.call
    buffer << @literal
    buffer << next_ws.call
    buffer << "}"
    buffer
  end

  def justify!
    raise NotImplementedError, "justify! for hex is a phase 8 follow-up"
  end

  def to_rgb
    raise NotImplementedError, "hex -> rgb conversion is a phase 8 follow-up"
  end

  def to_hsv
    raise NotImplementedError, "hex -> hsv conversion is a phase 8 follow-up"
  end

  def to_hsv360
    raise NotImplementedError, "hex -> hsv360 conversion is a phase 8 follow-up"
  end

  def to_hex
    self
  end
end

class Paradoxical::Elements::Primitives::Color::Hex < Paradoxical::Elements::Primitives::Color
  # Hex carries a single `0xRRGGBB` or `0xRRGGBBAA` byte string. It's
  # still conceptually 3-or-4 components (the channels are just
  # stored as 2-char hex byte strings rather than numbers), so the
  # `#r`/`#g`/`#b`/`#alpha` accessors below derive them by slicing
  # the literal. Conversion to numeric / RGB is a phase 8 follow-up.

  HEX_PAIR = /\A[0-9a-fA-F]{2}\z/

  def initialize literal, whitespace: nil
    @literal = literal
    @whitespace = whitespace || []
  end

  attr_accessor :literal

  def dup
    self.class.new @literal.dup, whitespace: @whitespace.dup
  end

  def r       ; component(0)            end
  def r= v    ; set_component(0, v)     end
  def g       ; component(1)            end
  def g= v    ; set_component(1, v)     end
  def b       ; component(2)            end
  def b= v    ; set_component(2, v)     end
  def alpha   ; component(3)            end
  def alpha= v; set_component(3, v)     end

  # 3-or-4 channels depending on whether alpha is present. Mirrors
  # the array shape of RGB/HSV/HSV360 (component count = channel count)
  # rather than the previous "literal as a 1-element array" shape.
  def components
    [r, g, b, alpha].compact
  end

  def colors
    components
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

  private

  # Components are at offsets 2/4/6/8 (after the "0x" prefix), each
  # 2 chars wide. Returns nil when the literal is too short for that
  # channel — e.g. a 6-char hex (`0xRRGGBB`) has no alpha.
  def component idx
    start = 2 + idx * 2
    return nil if @literal.length < start + 2

    @literal[start, 2]
  end

  # Setters validate exactly 2 hex chars and require the literal to
  # already carry that channel — we don't auto-grow a `0xRRGGBB` into
  # `0xRRGGBBAA` when alpha is set. That kind of width-changing
  # mutation belongs with the conversion work in phase 8 follow-up.
  def set_component idx, value
    raise ArgumentError, "hex component must be exactly 2 hex chars, got #{value.inspect}" unless value =~ HEX_PAIR

    start = 2 + idx * 2

    raise ArgumentError, "cannot set component #{idx} on #{@literal.inspect} (literal too short)" if @literal.length < start + 2

    @literal[start, 2] = value
  end
end

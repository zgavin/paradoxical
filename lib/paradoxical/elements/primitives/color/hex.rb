class Paradoxical::Elements::Primitives::Color::Hex < Paradoxical::Elements::Primitives::Color
  # Hex carries a single `0xRRGGBB` or `0xRRGGBBAA` byte string. It's
  # still conceptually 3-or-4 components (the channels are just
  # stored as 2-char hex byte strings rather than numbers), so the
  # `#r`/`#g`/`#b`/`#alpha` accessors below derive them by slicing
  # the literal.

  HEX_PAIR = /\A[0-9a-fA-F]{2}\z/

  def initialize literal, whitespace: nil
    @literal = literal
    @whitespace = whitespace || []
    validate!
  end

  attr_accessor :literal

  def dup
    self.class.new @literal.dup, whitespace: @whitespace.dup
  end

  channels :r, :g, :b, :alpha

  def type; "hex"; end
  def hex?; true; end

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
    next_ws = ->(default = " ") { (iter.next or default) rescue default }

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
    @whitespace = [nil, " ", " ", nil]

    self
  end

  # Conversions chain through RGB — hex maps cleanly onto integer
  # channels (each 2-char pair is a 0..255 byte), so converting to
  # RGB first and chaining from there is both correct and concise.
  def to_rgb
    pairs = [r, g, b].compact.map do |pair| pair.to_i(16) end
    components = pairs.map do |i| make_int(i) end
    components << make_int(alpha.to_i(16)) unless alpha.nil?

    Paradoxical::Elements::Primitives::Color::RGB.new(components)
  end

  def to_hsv
    to_rgb.to_hsv
  end

  def to_hsv360
    to_rgb.to_hsv.to_hsv360
  end

  def to_hex
    dup
  end

  private

  # Hex literals must be `0x` followed by at least one hex digit.
  # We don't enforce an even digit count — EU5 ships at least one
  # 9-digit literal (`0xffeDAA06D`) which the engine accepts; the
  # component slicer below already returns nil for incomplete pairs,
  # so odd lengths degrade gracefully rather than corrupt the read.
  def validate!
    return if @literal =~ /\A0x[0-9a-fA-F]+\z/

    raise ArgumentError, "hex literal must match 0x<hex digits>; got #{@literal.inspect}"
  end

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

    if @literal.length < start + 2 then
      raise ArgumentError, "cannot set component #{idx} on #{@literal.inspect} (literal too short)"
    end

    @literal[start, 2] = value
  end
end

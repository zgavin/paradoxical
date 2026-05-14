class Paradoxical::Elements::Primitives::Color
  # Abstract base. The parser instantiates one of the concrete
  # subclasses below (RGB / HSV / HSV360 / Hex) based on which keyword
  # the source used. `is_a?(Color)` stays true across all four.
  #
  # Components are stored as typed primitives (Integer / Float for
  # RGB/HSV/HSV360, raw byte string for Hex's `0x......` literal).
  # `whitespace` is the per-token byte capture for byte-identical
  # round-trip, same shape as Elements::List's whitespace.

  attr_accessor :components, :whitespace

  def initialize components, whitespace: nil
    @components = components
    @whitespace = whitespace || []
  end

  def dup
    self.class.new @components.map(&:dup), whitespace: @whitespace.dup
  end

  def type
    self.class.name.split("::").last.downcase
  end

  def rgb?     ; is_a? RGB     end
  def hsv?     ; is_a? HSV     end
  def hsv360?  ; is_a? HSV360  end
  def hex?     ; is_a? Hex     end

  # Back-compat surface: `colors` historically returned an array of
  # stringified components. Keep that signature so existing call
  # sites (and spec assertions) work; per-subclass getters
  # (`#r`, `#g`, `#b`, `#alpha` for RGB, etc.) are the typed path.
  def colors
    @components.map(&:to_pdx)
  end

  def to_pdx
    iter = @whitespace.each
    next_ws = ->(default = " ") { iter.next rescue default }

    buffer = String.new(type)
    buffer << next_ws.call
    buffer << "{"
    @components.each do |c|
      buffer << next_ws.call
      buffer << c.to_pdx
    end
    buffer << next_ws.call
    buffer << "}"
    buffer
  end

  def to_s
    to_pdx
  end
end

class Paradoxical::Elements::Primitives::Color::RGB < Paradoxical::Elements::Primitives::Color
  def r       ; @components[0]      end
  def r= v    ; @components[0] = v  end
  def g       ; @components[1]      end
  def g= v    ; @components[1] = v  end
  def b       ; @components[2]      end
  def b= v    ; @components[2] = v  end
  def alpha   ; @components[3]      end
  def alpha= v; @components[3] = v  end

  def justify!
    if @components.length == 3 then
      strs = @components.map(&:to_pdx)
      @whitespace = [nil, *strs.map do |c| " " * (4 - c.length) end, nil]
    else
      raise NotImplementedError, "justify! for 4-component rgb is a phase 8 follow-up"
    end

    self
  end

  # https://en.wikipedia.org/wiki/HSL_and_HSV#From_RGB
  def to_hsv
    raise NotImplementedError, "4-component rgb -> hsv conversion is a phase 8 follow-up" if @components.length != 3

    r, g, b = @components.map do |c| c.to_i / 255.0 end

    x_max = [r, g, b].max
    x_min = [r, g, b].min

    v = x_max
    c = x_max - x_min

    h =
      if c == 0 then
        0
      elsif v == r then
        ((g - b) / c)
      elsif v == g then
        ((b - r) / c) + 2
      elsif v == b then
        ((r - g) / c) + 4
      end

    h /= 6
    h += 1 if h < 0

    s = v == 0 ? 0 : c / v

    components = [h, s, v].map do |val|
      Paradoxical::Elements::Primitives::Float.new("%.3f" % val)
    end

    HSV.new(components)
  end

  def to_rgb
    self
  end

  def to_hsv360
    raise NotImplementedError, "rgb -> hsv360 conversion is a phase 8 follow-up"
  end

  def to_hex
    raise NotImplementedError, "rgb -> hex conversion is a phase 8 follow-up"
  end
end

class Paradoxical::Elements::Primitives::Color::HSV < Paradoxical::Elements::Primitives::Color
  def h       ; @components[0]      end
  def h= v    ; @components[0] = v  end
  def s       ; @components[1]      end
  def s= v    ; @components[1] = v  end
  def v       ; @components[2]      end
  def v= v    ; @components[2] = v  end
  def alpha   ; @components[3]      end
  def alpha= v; @components[3] = v  end

  def justify!
    if @components.length == 3 then
      @whitespace = []
      @components = @components.map do |val|
        Paradoxical::Elements::Primitives::Float.new("%.3f" % val.to_f)
      end
    else
      raise NotImplementedError, "justify! for 4-component hsv is a phase 8 follow-up"
    end

    self
  end

  # https://en.wikipedia.org/wiki/HSL_and_HSV#HSV_to_RGB
  def to_rgb
    raise NotImplementedError, "4-component hsv -> rgb conversion is a phase 8 follow-up" if @components.length != 3

    h, s, v = @components.map(&:to_f)

    c = v * s
    h_prime = (h * 6) % 6
    x = c * (1 - ((h_prime % 2) - 1).abs)

    r1, g1, b1 =
      if h_prime >= 0 and h_prime < 1 then
        [c, x, 0]
      elsif h_prime >= 1 and h_prime < 2 then
        [x, c, 0]
      elsif h_prime >= 2 and h_prime < 3 then
        [0, c, x]
      elsif h_prime >= 3 and h_prime < 4 then
        [0, x, c]
      elsif h_prime >= 4 and h_prime < 5 then
        [x, 0, c]
      elsif h_prime >= 5 and h_prime < 6 then
        [c, 0, x]
      end

    m = v - c

    components = [r1, g1, b1].map do |c|
      Paradoxical::Elements::Primitives::Integer.new(((c + m) * 255).to_i.to_s)
    end

    RGB.new(components)
  end

  def to_hsv
    self
  end

  def to_hsv360
    raise NotImplementedError, "hsv -> hsv360 conversion is a phase 8 follow-up"
  end

  def to_hex
    raise NotImplementedError, "hsv -> hex conversion is a phase 8 follow-up"
  end
end

class Paradoxical::Elements::Primitives::Color::HSV360 < Paradoxical::Elements::Primitives::Color
  def h       ; @components[0]      end
  def h= v    ; @components[0] = v  end
  def s       ; @components[1]      end
  def s= v    ; @components[1] = v  end
  def v       ; @components[2]      end
  def v= v    ; @components[2] = v  end

  def justify!
    raise NotImplementedError, "justify! for hsv360 is a phase 8 follow-up"
  end

  def to_rgb
    raise NotImplementedError, "hsv360 -> rgb conversion is a phase 8 follow-up"
  end

  def to_hsv
    raise NotImplementedError, "hsv360 -> hsv conversion is a phase 8 follow-up"
  end

  def to_hsv360
    self
  end

  def to_hex
    raise NotImplementedError, "hsv360 -> hex conversion is a phase 8 follow-up"
  end
end

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

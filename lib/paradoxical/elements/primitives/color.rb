class Paradoxical::Elements::Primitives::Color
  # Abstract base. The parser instantiates one of the concrete
  # subclasses (RGB / HSV / HSV360 / Hex) under this namespace based
  # on which keyword the source used. `is_a?(Color)` stays true
  # across all four.
  #
  # Components are stored as typed primitives (Integer / Float for
  # RGB/HSV/HSV360; raw byte string for Hex's `0x......` literal).
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

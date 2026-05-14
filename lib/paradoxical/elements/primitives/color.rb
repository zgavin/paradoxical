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

  # Declarative per-channel accessor macro. Each subclass calls
  # `channels :a, :b, :c[, :alpha]` to get the matching reader/writer
  # pairs. Storage delegates to `component`/`set_component`, which
  # default to `@components[idx]` (the shape RGB/HSV/HSV360 use) and
  # are overridden by `Hex` to slice the 2-char channels out of its
  # `0x...` literal.
  def self.channels *names
    names.each_with_index do |name, idx|
      define_method(name) { component(idx) }
      define_method("#{name}=") { |v| set_component(idx, v) }
    end
  end

  def initialize components, whitespace: nil
    @components = components
    @whitespace = whitespace || []
  end

  private

  def component idx
    @components[idx]
  end

  def set_component idx, value
    @components[idx] = value
  end

  public

  def dup
    self.class.new @components.map(&:dup), whitespace: @whitespace.dup
  end

  def type
    raise NotImplementedError, "subclass must define #type"
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

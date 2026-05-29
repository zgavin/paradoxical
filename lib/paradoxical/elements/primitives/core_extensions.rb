class Object
  def to_pdx
    inspect
  end
end

class Symbol
  def to_pdx
    self.to_s
  end

  def quote
    self.to_s.quote
  end

  def literal
    self.to_s.literal
  end
end

class String
  prepend Paradoxical::Elements::Concerns::Impersonator::NativeComparisons

  IS_VALID_RAW_STRING_REGEXP = %r{^((\w+:|@)?(\w+\.)*\w+)|-?\d+\.?\d*%+$}x

  def to_pdx
    IS_VALID_RAW_STRING_REGEXP =~ self ? self : %{"#{self}"}
  end

  def quote
    Paradoxical::Elements::Primitives::String.new self, quoted: true
  end

  def literal
    Paradoxical::Elements::Primitives::String.new self, quoted: false
  end
end

class Float
  prepend Paradoxical::Elements::Concerns::Impersonator::NativeComparisons

  # Round + trim via `Primitives::Float.format`, using the active
  # game's precision cap (set by `Game.new` from `FLOAT_PRECISION`,
  # default 3). Replaces the old hard-coded `"%.3f"` shape: `0.5`
  # now emits `"0.5"` rather than `"0.500"`. Modders who need a
  # specific precision / trailing zeros can pass a string literal
  # through `Primitives::String` instead.
  def to_pdx
    Paradoxical::Elements::Primitives::Float.format(self)
  end
end

class BigDecimal
  prepend Paradoxical::Elements::Concerns::Impersonator::NativeComparisons

  # BigDecimals land in AST values when `Primitives::Float` arithmetic
  # returns a result (post-8d). Default `to_s` is scientific notation
  # (`"0.1234e4"`) which the engine doesn't accept. Round + trim via
  # the same formatter `::Float#to_pdx` uses.
  def to_pdx
    Paradoxical::Elements::Primitives::Float.format(self)
  end
end

class Integer
  prepend Paradoxical::Elements::Concerns::Impersonator::NativeComparisons

  def to_pdx
    to_s
  end
end

class TrueClass
  def to_pdx
    "yes"
  end
end

class FalseClass
  def to_pdx
    "no"
  end
end

class Array
  def to_pdx
    Paradoxical::Elements::Document.new(self, whitespace: [""]).to_pdx
  end

  def pdx_add_padding_lines
    self.map do |v| [v, Paradoxical::Elements::Value.empty_line] end.flatten(1)[0..-2]
  end
end

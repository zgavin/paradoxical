class Paradoxical::Elements::Primitives::Integer
  include Paradoxical::Elements::Concerns::Impersonator

  impersonate ::Integer

  impersonate_infix_methods %i{!~ % & * ** + - / << =~ >> ^ |}

  # Round-trip metadata for binary-parsed integers — one of
  # `TokenKind::U32` / `U64` / `I32` / `I64`, captured by the binary
  # parser so a future binary writer can re-emit the same token shape.
  # Plaintext-parsed integers leave this nil; the future writer picks
  # "smallest token that fits" as a default. Equality / hash
  # intentionally ignore it — two integers with the same value are
  # equal regardless of source format. See MODERNIZATION.md phase 10h.
  attr_reader :binary_encoding

  def initialize value, binary_encoding: nil
    super value
    @binary_encoding = binary_encoding
  end

  def dup
    self.class.new @value.dup, binary_encoding: @binary_encoding
  end

  def to_int
    @value.to_i
  end

  def coerce something
    case something
    when Float
      [@value.to_f, something]
    when Integer
      [@value.to_i, something]
    else
      super
    end
  end
end

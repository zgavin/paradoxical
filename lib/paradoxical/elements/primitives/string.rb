class Paradoxical::Elements::Primitives::String
  include Paradoxical::Elements::Concerns::Impersonator

  impersonate ::String

  impersonate_infix_methods %i{!~ % * + =~ <<}

  # Round-trip metadata for binary-parsed strings. Plaintext-parsed
  # strings always leave these nil. Equality / hash intentionally
  # ignore them — two strings with the same text are equal regardless
  # of source format.
  #
  # `token_index` is set when the string was resolved from a 2-byte
  # token in the per-game `tokens:` table (phase 10e). `lookup_index`
  # is set when the string was resolved from an integer index in the
  # per-save `string_lookup:` table (phase 10f). `binary_encoding` is
  # set when the string came in via a `LOOKUP_*` token and records
  # which specific variant — the byte-width alone doesn't
  # disambiguate (`LOOKUP_08` / `LOOKUP_08A` are both 1 byte;
  # `LOOKUP_16` / `LOOKUP_16A` are both 2). For `QUOTED`/`UNQUOTED`
  # strings the `quoted` flag is sufficient (1:1 mapping), so
  # `binary_encoding` stays nil there. The future binary writer
  # dispatches on which of these is set to emit the matching token
  # shape. See MODERNIZATION.md phases 10e / 10f / 10h.
  attr_reader :token_index, :lookup_index, :binary_encoding

  def initialize string, quoted: nil, token_index: nil, lookup_index: nil, binary_encoding: nil
    if quoted.nil? then
      @quoted = (string.start_with? '"' and string.end_with? '"')

      super @quoted ? string[1..-2] : string
    else
      @quoted = quoted

      super string
    end

    @token_index = token_index
    @lookup_index = lookup_index
    @binary_encoding = binary_encoding
  end

  def quoted?
    @quoted
  end

  def dup
    self.class.new(
      @value,
      quoted: @quoted,
      token_index: @token_index,
      lookup_index: @lookup_index,
      binary_encoding: @binary_encoding
    )
  end

  def to_pdx
    @quoted ? %{"#{self}"} : self
  end

  def coerce something
    case something
    when String
      [@value.to_s, something]
    else
      super
    end
  end
end

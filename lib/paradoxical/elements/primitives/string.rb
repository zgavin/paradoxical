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
  # per-save `string_lookup:` table (phase 10f). At most one is
  # populated on any given instance — the wire format uses a different
  # opcode for each. The future binary writer dispatches on which is
  # set to emit the matching token shape.
  attr_reader :token_index, :lookup_index

  def initialize string, quoted: nil, token_index: nil, lookup_index: nil
    if quoted.nil? then
      @quoted = (string.start_with? '"' and string.end_with? '"')

      super @quoted ? string[1..-2] : string
    else
      @quoted = quoted

      super string
    end

    @token_index = token_index
    @lookup_index = lookup_index
  end

  def quoted?
    @quoted
  end

  def dup
    self.class.new @value, quoted: @quoted, token_index: @token_index, lookup_index: @lookup_index
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

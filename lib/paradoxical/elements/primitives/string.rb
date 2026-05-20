class Paradoxical::Elements::Primitives::String
  include Paradoxical::Elements::Concerns::Impersonator

  impersonate ::String

  impersonate_infix_methods %i{!~ % * + =~ <<}

  # `token_index` is round-trip metadata for binary-parsed strings that
  # were resolved from a 2-byte token in the per-game `tokens:` table.
  # Plaintext-parsed strings always leave it nil. When set, the future
  # binary writer emits the 2-byte token instead of the
  # quoted/unquoted-string token shape. Equality / hash intentionally
  # ignore it — two strings with the same text are equal regardless of
  # source format. See MODERNIZATION.md phase 10e.
  attr_reader :token_index

  def initialize string, quoted: nil, token_index: nil
    if quoted.nil? then
      @quoted = (string.start_with? '"' and string.end_with? '"')

      super @quoted ? string[1..-2] : string
    else
      @quoted = quoted

      super string
    end

    @token_index = token_index
  end

  def quoted?
    @quoted
  end

  def dup
    self.class.new @value, quoted: @quoted, token_index: @token_index
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

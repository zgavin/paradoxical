# Pure-Ruby parser for Paradox's binary save format. Mirrors the text
# parser's API: a class-level `parse` returning a Paradoxical::Document
# built from the same Elements primitives as the text path.
#
# Binary saves encode the same value / property / list tree as the text
# format but compress identifiers ("date", "country", etc.) into 2-byte
# token IDs. The token → identifier mapping is game-specific and
# *cannot be distributed* (Paradox legal has historically pursued
# projects that ship the mappings). Callers must supply the table —
# either per-parse via `tokens:` or once at the class level via
# `default_tokens=`, which `paradoxical!`'s `binary_tokens:` kwarg
# wires up for the active game.
class Paradoxical::BinaryParser
  class ParseError < StandardError
  end

  # Paradox's binary format stores dates as hours since -5000, but
  # this counts year 0. No game operates in negative years and save
  # data should not contain them (unlike game-data files), so we can
  # offset by 1 to skip year 0 and treat the epoch as -5001.
  INITIAL_DATE = Paradoxical::Elements::Primitives::Date.new "-5001.01.01"

  class << self
    # Per-game default token table, used when `parse(data)` is called
    # without an explicit `tokens:`. `paradoxical!` sets this from
    # its `binary_tokens:` kwarg. Defaults to an empty hash, in which
    # case every identifier surfaces as its raw 2-byte integer
    # instead of a name — fine for inspection, not what real
    # consumers want.
    attr_writer :default_tokens

    def default_tokens
      @default_tokens ||= {}
    end

    # `data` is the raw bytes of the save body as a String (binary
    # encoding). `tokens` overrides `default_tokens` for this call.
    def parse data, tokens: nil
      new(tokens || default_tokens).parse(data)
    end
  end

  attr_reader :tokens

  def initialize tokens
    @tokens = tokens
  end

  def parse data
    @bytes = data.unpack("C*")
    read_doc
  end

  private

  attr_reader :bytes

  def integer length = nil, value: nil
    # integers have little-endian byte order, so the most significant byte is the last
    # so we reverse, then shift by 1 byte and bitwise or with the next byte
    raw = value || shift_bytes(length)
    n = raw.reverse_each.reduce(0) { |sum, byte| (sum << 8) | byte }
    Paradoxical::Elements::Primitives::Integer.new n
  end

  def string quoted:
    length = integer(2).to_i
    Paradoxical::Elements::Primitives::String.new shift_bytes(length).pack("C*"), quoted:
  end

  def float length
    shift_bytes(length).pack("C*").unpack1(length == 4 ? "e" : "E")
  end

  def fixed length, negative: false
    n = integer(length).to_i
    n *= -1 if negative
    Paradoxical::Elements::Primitives::Float.new((n / 100_000.0).to_s)
  end

  def read_scalar is_date: false
    type = integer(2).to_i

    v =
      case type
      when 0x0003 then { open: true }
      when 0x0004 then { close: true }
      when 0x0001 then { equals: true }
      when 0x0014 then integer 4                              # uint32
      when 0x029c then integer 8                              # uint64
      when 0x000c then signed_integer 4                       # int32
      when 0x000e then shift_bytes(1).first == 1              # boolean
      when 0x000f then string quoted: true                    # quoted string
      when 0x0017 then string quoted: false                   # unquoted string
      when 0x000d then float 4                                # float
      when 0x0167 then float 8                                # double
      when 0x0243 then fail "binary rgb (type 0x0243) not implemented"
      when 0x0317 then signed_integer 8                       # int64
      when 0x0d40, 0x0d43 then integer 1                      # 8 bit lookup index
      when 0x0d41         then integer 3                      # 24 bit lookup index
      when 0x0d3e, 0x0d44 then integer 2                      # 16 bit lookup index
      when 0x0d48 then fixed 1                                # 8 bit fixed
      when 0x0d49 then fixed 2                                # 16 bit fixed
      when 0x0d4a then fixed 3                                # 24 bit fixed
      when 0x0d4b then fixed 4                                # 32 bit fixed
      when 0x0d4c then fixed 5                                # 40 bit fixed
      when 0x0d4d then fixed 6                                # 48 bit fixed
      when 0x0d4e then fixed 7                                # 56 bit fixed
      when 0x0d4f then fixed 1, negative: true                # 8 bit negative fixed
      when 0x0d50 then fixed 2, negative: true                # 16 bit negative fixed
      when 0x0d51 then fixed 3, negative: true                # 24 bit negative fixed
      when 0x0d52 then fixed 4, negative: true                # 32 bit negative fixed
      when 0x0d53 then fixed 5, negative: true                # 40 bit negative fixed
      when 0x0d54 then fixed 6, negative: true                # 48 bit negative fixed
      when 0x0d55 then fixed 7, negative: true                # 56 bit negative fixed
      else { token: type }
      end

    # See the file-level comment for date conversion.
    # `Primitives::Integer#is_a?(Integer)` returns true via the
    # impersonator concern, so this catches every wrapped integer type.
    v = INITIAL_DATE + v.to_i.hours if is_date and v.is_a? Integer

    v
  end

  def read_list key:
    obj = Paradoxical::Elements::List.new key, []
    n = read_next
    (obj << n) and n = read_next until n.is_a?(Hash) and n[:close]
    obj
  end

  def read_doc
    doc = Paradoxical::Elements::Document.new
    doc << read_next until bytes.empty?
    doc
  end

  def read_next
    n = read_scalar

    return Paradoxical::Elements::Value.new n unless n.is_a? Hash

    return n if n[:close]

    fail "expected token, got: #{n}" if n[:token].nil?

    key = tokens[n[:token]] || n[:token]

    eql = read_scalar

    fail "expected `=` after key #{key.inspect}, got: #{eql}" unless eql.is_a?(Hash) and eql[:equals]

    maybe_open = read_scalar is_date: key == "date"

    if maybe_open.is_a?(Hash) and maybe_open[:open] then
      read_list key:
    elsif not maybe_open.is_a?(Hash) then
      Paradoxical::Elements::Property.new key, "=", maybe_open
    else
      fail "unexpected control token after `#{key}`: #{maybe_open}"
    end
  end

  # Two's-complement signed integer. `length` is in bytes (4 for int32,
  # 8 for int64). Returns a wrapped `Primitives::Integer`.
  def signed_integer length
    n = integer(length).to_i
    n -= (1 << (length * 8)) if n >= (1 << (length * 8 - 1))
    Paradoxical::Elements::Primitives::Integer.new n
  end

  # Front-of-array shift with truncation detection. The bare
  # `Array#shift(n)` returns `[]` when the array is shorter than `n`,
  # which would silently yield zero-valued integers / empty strings
  # downstream; raise instead so malformed input fails loudly.
  def shift_bytes length
    fail "unexpected end of input (wanted #{length} byte#{"s" if length != 1})" if bytes.length < length

    bytes.shift length
  end

  def fail msg
    raise ParseError, msg
  end
end

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
class Paradoxical::Binary::Parser
  class ParseError < StandardError
  end

  # Paradox's binary format stores dates as hours since -5000, but
  # this counts year 0. No game operates in negative years and save
  # data should not contain them (unlike game-data files), so we can
  # offset by 1 to skip year 0 and treat the epoch as -5001.
  INITIAL_DATE = Paradoxical::Elements::Primitives::Date.new "-5001.01.01"

  module TokenKind
    OPEN        = 0x0003 # open brace equivalent
    CLOSE       = 0x0004 # close brace equivalent
    EQUAL       = 0x0001 # assignment equivalent
    U32         = 0x0014 # uint32
    U64         = 0x029c # uint64
    I32         = 0x000c # int32
    BOOL        = 0x000e # boolean
    QUOTED      = 0x000f # quoted string
    UNQUOTED    = 0x0017 # unquoted string
    F32         = 0x000d # float
    F64         = 0x0167 # double
    RGB         = 0x0243 # rgb
    I64         = 0x0317 # int64
    LOOKUP_08   = 0x0d40 #  8 bit lookup index
    LOOKUP_16   = 0x0d3e # 16 bit lookup index
    LOOKUP_24   = 0x0d41 # 24 bit lookup index
    LOOKUP_08A  = 0x0d43 #  8 bit lookup index alternate
    LOOKUP_16A  = 0x0d44 # 16 bit lookup index alternate
    FIXED_U08   = 0x0d48 #  8 bit fixed
    FIXED_U16   = 0x0d49 # 16 bit fixed
    FIXED_U24   = 0x0d4a # 24 bit fixed
    FIXED_U32   = 0x0d4b # 32 bit fixed
    FIXED_U40   = 0x0d4c # 40 bit fixed
    FIXED_U48   = 0x0d4d # 48 bit fixed
    FIXED_U56   = 0x0d4e # 56 bit fixed
    FIXED_I08   = 0x0d4f #  8 bit negative fixed
    FIXED_I16   = 0x0d50 # 16 bit negative fixed
    FIXED_I24   = 0x0d51 # 24 bit negative fixed
    FIXED_I32   = 0x0d52 # 32 bit negative fixed
    FIXED_I40   = 0x0d53 # 40 bit negative fixed
    FIXED_I48   = 0x0d54 # 48 bit negative fixed
    FIXED_I56   = 0x0d55 # 56 bit negative fixed
  end

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
    # `string_lookup` is a per-save table (see `Paradoxical::Binary::StringLookup`)
    # that resolves the `LOOKUP_*`-token indices into identifier
    # strings; it's omitted for inspection-only parses or when no
    # lookup file is available. Each save has its own — there's no
    # class-level default because lookup tables aren't shareable
    # across saves.
    def parse data, tokens: nil, string_lookup: nil
      new(tokens || default_tokens, string_lookup).parse(data)
    end
  end

  attr_reader :tokens, :string_lookup

  def initialize tokens, string_lookup = nil
    @tokens = tokens
    @string_lookup = string_lookup
  end

  def parse data
    @bytes = data.unpack("C*")
    doc = read_doc
    doc.string_lookup = @string_lookup
    doc
  end

  private

  attr_reader :bytes

  # integers have little-endian byte order, so the most significant byte is the last
  # so we reverse, then shift by 1 byte and bitwise or with the next byte
  def integer length = nil, value: nil
    raw = value || shift_bytes(length)
    n = raw.reverse_each.reduce(0) { |sum, byte| (sum << 8) | byte }
    Paradoxical::Elements::Primitives::Integer.new n
  end

  # Two's-complement signed integer. `length` is in bytes (4 for int32,
  # 8 for int64). Returns a wrapped `Primitives::Integer`.
  def signed_integer length
    n = integer(length).to_i
    n -= (1 << (length * 8)) if n >= (1 << (length * 8 - 1))
    Paradoxical::Elements::Primitives::Integer.new n
  end

  # Binary strings are u16-length-prefixed raw byte sequences (length is
  # in bytes, not characters — non-ASCII handling stays at the
  # Primitives::String layer). `quoted:` tracks whether the source token
  # was 0x000f (quoted, treated as data) or 0x0017 (unquoted, treated as
  # an identifier-shaped literal) so the round-trip writer can pick the
  # right type code back out.
  def string quoted:
    length = integer(2).to_i
    Paradoxical::Elements::Primitives::String.new shift_bytes(length).pack("C*"), quoted:
  end

  # IEEE 754, little-endian. `length` is the byte width: 4 for single
  # precision (0x000d), 8 for double (0x0167). Returns a raw Ruby Float
  # rather than a Primitives::Float — the binary form carries no
  # source-string representation for us to preserve, unlike the script
  # literal where precision and trailing zeros are part of the byte
  # capture.
  def float length
    shift_bytes(length).pack("C*").unpack1(length == 4 ? "e" : "E")
  end

  # Paradox's fixed-point representation: a raw little-endian integer
  # divided by 100_000. `length` is the byte width (1..7; token IDs
  # 0x0d48..0x0d4e for positive, 0x0d4f..0x0d55 for negative). Negativity
  # is *not* two's-complement — it's conveyed by a separate token range,
  # so `negative:` simply flips the sign after reading the magnitude.
  def fixed length, negative: false
    n = integer(length).to_i
    n *= -1 if negative
    Paradoxical::Elements::Primitives::Float.new((n / 100_000.0).to_s)
  end

  # Front-of-array shift with truncation detection. The bare
  # `Array#shift(n)` returns `[]` when the array is shorter than `n`,
  # which would silently yield zero-valued integers / empty strings
  # downstream; raise instead so malformed input fails loudly.
  def shift_bytes length
    fail "unexpected end of input (wanted #{length} byte#{"s" if length != 1})" if bytes.length < length

    bytes.shift length
  end

  # Non-consuming check for the `=` token (`TokenKind::EQUAL`) at the
  # front of the byte stream. Used by `read_next` to decide whether a
  # primitive scalar should be treated as a property key or a bare
  # value. EOF or any other byte sequence returns false. See
  # MODERNIZATION.md phase 10g.
  def peek_equals?
    bytes.length >= 2 and (bytes[1] << 8 | bytes[0]) == TokenKind::EQUAL
  end

  # The body of an rgb value is `{ red <u32> green <u32> blue <u32> [alpha <u32>] }` —
  # equivalent in the script grammar to: `rgb { red N green N blue N (alpha N)? }`.
  # Two details worth knowing:
  #   * channel values are bare little-endian uint32s, with none of the 0x0014 type
  #     prefix a top-level uint32 would carry — the surrounding 0x0243 marker is
  #     enough typing context
  #   * the `red`/`green`/`blue`/`alpha` identifier tokens are game-specific, and
  #     this method does not look them up or validate them; the open/close braces
  #     plus the three-pairs-with-optional-fourth shape are enough to identify the
  #     form unambiguously
  def rgb
    open = integer 2
    fail "expected open token got: 0x#{open.to_i.to_s(16).rjust 4, "0"}" unless open == TokenKind::OPEN

    rtoken, r, gtoken, g, btoken, b = 3.times.flat_map { [integer(2), integer(4)] }

    close = integer 2
    atoken, a, close = close, integer(4), integer(2) unless close == TokenKind::CLOSE

    fail "expected close token got: 0x#{close.to_i.to_s(16).rjust 4, "0"}" unless close == TokenKind::CLOSE

    Paradoxical::Elements::Primitives::Color::RGB.from r, g, b, alpha: a
  end

  def read_scalar is_date: false
    type = integer(2).to_i

    v =
      case type
      when TokenKind::OPEN       then { open: true }
      when TokenKind::CLOSE      then { close: true }
      when TokenKind::EQUAL      then { equals: true }
      when TokenKind::U32        then integer 4
      when TokenKind::U64        then integer 8
      when TokenKind::I32        then signed_integer 4
      when TokenKind::BOOL       then shift_bytes(1).first == 1
      when TokenKind::QUOTED     then string quoted: true
      when TokenKind::UNQUOTED   then string quoted: false
      when TokenKind::F32        then float 4
      when TokenKind::F64        then float 8
      when TokenKind::RGB        then rgb
      when TokenKind::I64        then signed_integer 8
      when TokenKind::LOOKUP_08  then lookup 1
      when TokenKind::LOOKUP_24  then lookup 3
      when TokenKind::LOOKUP_16  then lookup 2
      when TokenKind::LOOKUP_08A then lookup 1
      when TokenKind::LOOKUP_16A then lookup 2
      when TokenKind::FIXED_U08  then fixed 1
      when TokenKind::FIXED_U16  then fixed 2
      when TokenKind::FIXED_U24  then fixed 3
      when TokenKind::FIXED_U32  then fixed 4
      when TokenKind::FIXED_U40  then fixed 5
      when TokenKind::FIXED_U48  then fixed 6
      when TokenKind::FIXED_U56  then fixed 7
      when TokenKind::FIXED_I08  then fixed 1, negative: true
      when TokenKind::FIXED_I16  then fixed 2, negative: true
      when TokenKind::FIXED_I24  then fixed 3, negative: true
      when TokenKind::FIXED_I32  then fixed 4, negative: true
      when TokenKind::FIXED_I40  then fixed 5, negative: true
      when TokenKind::FIXED_I48  then fixed 6, negative: true
      when TokenKind::FIXED_I56  then fixed 7, negative: true
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

    unless n.is_a? Hash then
      # A primitive in key position — PDX saves use this for shapes like
      # `duration={ 66 0=0 1=0 … 65=0 }` (length-prefixed indexed map)
      # and any other case where an integer/date/string-shaped value
      # appears as a property's key. Peek the next 2 bytes: if they're
      # the `=` marker, this scalar is a key, not a bare value. See
      # MODERNIZATION.md phase 10g.
      if peek_equals? then
        shift_bytes 2
        return read_property_with_key n
      end

      return Paradoxical::Elements::Value.new n
    end

    return n if n[:close]

    # A `{` at the position a key token would normally occupy is one
    # of two PDX-save shapes:
    #   - a compound key: `{ inner }={ value }` — the key is itself a
    #     sub-list (e.g. `{ demand=pop_demand }={ 37 43 47 … }`); see
    #     phase 10c.
    #   - a keyless list: `{ … }` standalone, as a sibling of other
    #     children inside the enclosing list (or at document top level).
    # The disambiguation is the same peek-equals lookup 10g uses for
    # primitive scalars: peek after the matching `}` — `=` next means
    # compound key, otherwise it's a keyless list.
    if n[:open] then
      inner = read_list key: nil

      if peek_equals? then
        shift_bytes 2
        return read_property_with_key inner
      end

      return inner
    end

    fail "expected token, got: #{n}" if n[:token].nil?

    resolved = resolve_token_string n[:token]

    # Same peek-equals lookup as the primitive and compound-key branches:
    # the resolved identifier is a key if `=` follows, a bare value
    # otherwise. EU5 saves carry tokens in both positions — see the
    # 10e plan's empirical question, finally answered yes by the
    # ~7.4 MB-deep failure that motivated this expansion of 10g.
    if peek_equals? then
      shift_bytes 2
      return read_property_with_key resolved
    end

    Paradoxical::Elements::Value.new resolved
  end

  # Shared tail of `read_next`: once we have a key and the trailing `=`,
  # read the value and assemble either a List (if `{ … }`) or a Property
  # (if a primitive or a bare token). The compound-key branch above and
  # the regular token-key branch both end here.
  def read_property_with_key key
    maybe_open = read_scalar is_date: key == "date"

    if not maybe_open.is_a?(Hash) then
      Paradoxical::Elements::Property.new key, "=", maybe_open
    elsif maybe_open[:open] then
      read_list key:
    elsif maybe_open[:token] then
      # Token in value position — see MODERNIZATION.md phase 10e.
      # EU5 compresses repeated RHS identifiers (`yes`/`no`, enum
      # names) as raw 2-byte tokens instead of length-prefixed
      # strings; resolve via the same `tokens:` table the key path
      # uses.
      Paradoxical::Elements::Property.new key, "=", resolve_token_string(maybe_open[:token])
    else
      fail "unexpected control token after `#{key}`: #{maybe_open}"
    end
  end

  # Look up a 2-byte token in the supplied `tokens` table and wrap the
  # resolved identifier as a `Primitives::String` carrying its source
  # `token_index` for round-trip. Unresolved tokens still produce a
  # `Primitives::String` — but with the 4-char hex form of the token
  # int (`0x2cd6`) as the text. That makes missed lookups visually
  # distinct from real string values in the parsed Document (vs.
  # surfacing as a `Primitives::Integer`, which would be indistinguishable
  # from a genuine integer value at a glance). `token_index` is set in
  # both cases, so the future binary writer can round-trip either shape
  # via the same path. See MODERNIZATION.md phase 10e.
  def resolve_token_string token_int
    name = tokens[token_int] || "0x#{token_int.to_s(16).rjust(4, "0")}"
    Paradoxical::Elements::Primitives::String.new name, quoted: false, token_index: token_int
  end

  # Read an `length`-byte little-endian index from the wire and
  # resolve it into a `Primitives::String` carrying its source
  # `lookup_index` for round-trip. `length` is 1, 2, or 3 — the three
  # widths the `LOOKUP_*` token range covers. The behavior differs
  # from `resolve_token_string`'s missing-table fallback: because
  # lookup tables are per-save (and the parser receives them via the
  # `string_lookup:` kwarg), an out-of-range index when a table *is*
  # supplied implies a mismatch between the binary and the lookup —
  # that's a hard error, not a graceful degradation. When no table is
  # supplied we emit the hex-encoded `Primitives::String` shape
  # `resolve_token_string` uses, with `lookup_index` set so round-trip
  # still knows the original wire form. See MODERNIZATION.md phase 10f.
  def lookup length
    index = integer(length).to_i
    text = string_lookup ? string_lookup.resolve(index) : "0x#{index.to_s(16).rjust(4, "0")}"
    Paradoxical::Elements::Primitives::String.new text, quoted: false, lookup_index: index
  end

  def fail msg
    raise ParseError, msg
  end
end

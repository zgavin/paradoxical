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

  # Lower bound (hours since INITIAL_DATE) for treating a date-keyed
  # integer as an actual date. ~21M hours ≈ year -2604, just under the
  # oldest date observed in real saves (a year -2560 `creation_date`).
  # Below this lies the epoch-adjacent band where small counts/flags/ids
  # would land, so it's the cutoff that keeps non-date integers under a
  # date key from being mis-converted. See `read_scalar`.
  MIN_DATE_HOURS = 21_000_000

  # Singletons for the three field-less control-token shapes
  # `read_scalar` can return. Pre-10h these were allocated fresh as
  # `{ open: true }` etc. on every read; profiling against the
  # 172 MB EU5 gamestate showed the resulting hash churn was a
  # measurable contributor to the ~30% GC overhead. Frozen constants
  # share one instance across the entire parse instead. The remaining
  # `{ token: N }` shape still allocates per call (the value varies),
  # but it's a smaller fraction of total reads.
  OPEN_MARKER   = { open: true }.freeze
  CLOSE_MARKER  = { close: true }.freeze
  EQUALS_MARKER = { equals: true }.freeze

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

    # Per-game date-token allowlist — set of identifier names whose
    # `uint32` value is interpreted as hours-since-`-5001.01.01` and
    # converted to `Primitives::Date`. Defaults to just `"date"` for
    # backward compatibility; games with multiple date-typed fields
    # (EU5 ships several beyond `date` — see the empirical sweep in
    # MODERNIZATION.md phase 10h) override via `default_date_tokens=`
    # or per-parse via the `date_tokens:` kwarg. The set semantics
    # are deliberate — repeated lookups against this in `read_next`
    # need to be `O(1)`, not `Array#include?`.
    attr_writer :default_date_tokens

    def default_date_tokens
      @default_date_tokens ||= Set.new(["date"])
    end

    # `data` is the raw bytes of the save body as a String (binary
    # encoding). `tokens` overrides `default_tokens` for this call.
    # `string_lookup` is a per-save table (see `Paradoxical::Binary::StringLookup`)
    # that resolves the `LOOKUP_*`-token indices into identifier
    # strings; it's omitted for inspection-only parses or when no
    # lookup file is available. Each save has its own — there's no
    # class-level default because lookup tables aren't shareable
    # across saves. `date_tokens` overrides `default_date_tokens` for
    # this call.
    def parse data, tokens: nil, string_lookup: nil, date_tokens: nil
      new(tokens || default_tokens, string_lookup, date_tokens || default_date_tokens).parse(data)
    end
  end

  attr_reader :tokens, :string_lookup, :date_tokens

  def initialize tokens, string_lookup = nil, date_tokens = Set.new(["date"])
    @tokens = tokens
    @string_lookup = string_lookup
    @date_tokens = date_tokens
  end

  def parse data
    @bytes = data.unpack("C*")
    @pos = 0
    doc = read_doc
    doc.string_lookup = @string_lookup
    doc
  end

  private

  attr_reader :bytes, :pos

  # Read a little-endian unsigned integer from the byte stream and
  # return it as a plain Ruby `Integer`, advancing the cursor.
  # Indexes `@bytes` directly rather than slicing — this is the
  # hottest read in the parser (the 2-byte type tag fires once per
  # scalar plus every integer/lookup/fixed magnitude), and slicing
  # allocated a throwaway Array on each call. Direct indexing with an
  # inlined bit-shift for the common 1-4 byte widths allocates
  # nothing. See MODERNIZATION.md phase 10h.
  def raw_int length
    b = @bytes
    p = @pos
    err "unexpected end of input (wanted #{length} byte#{"s" if length != 1})" if p + length > b.length

    @pos = p + length
    case length
    when 1 then b[p]
    when 2 then b[p] | (b[p + 1] << 8)
    when 3 then b[p] | (b[p + 1] << 8) | (b[p + 2] << 16)
    when 4 then b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)
    else
      n = 0
      length.times { |i| n |= b[p + i] << (i * 8) }
      n
    end
  end

  # `binary_encoding:` (when supplied by a case branch) is the source
  # `TokenKind::U32`/`U64`/etc. that produced this integer — preserved
  # on the `Primitives::Integer` for round-trip. The wrap is only
  # needed when the integer becomes a Document value; bookkeeping
  # reads (`raw_int` above) skip it. See MODERNIZATION.md phase 10h.
  def integer length, binary_encoding: nil
    Paradoxical::Elements::Primitives::Integer.new raw_int(length), binary_encoding: binary_encoding
  end

  # Two's-complement signed integer. `length` is in bytes (4 for int32,
  # 8 for int64). Returns a wrapped `Primitives::Integer`.
  def signed_integer length, binary_encoding: nil
    n = raw_int(length)
    n -= (1 << (length * 8)) if n >= (1 << (length * 8 - 1))
    Paradoxical::Elements::Primitives::Integer.new n, binary_encoding: binary_encoding
  end

  # Binary strings are u16-length-prefixed raw byte sequences (length is
  # in bytes, not characters — non-ASCII handling stays at the
  # Primitives::String layer). `quoted:` tracks whether the source token
  # was 0x000f (quoted, treated as data) or 0x0017 (unquoted, treated as
  # an identifier-shaped literal) so the round-trip writer can pick the
  # right type code back out.
  def string quoted:
    length = raw_int(2)
    Paradoxical::Elements::Primitives::String.new read_bytes(length).pack("C*"), quoted:
  end

  # IEEE 754, little-endian. `length` is the byte width: 4 for single
  # precision (0x000d), 8 for double (0x0167). Returns a
  # `Primitives::Float` carrying `binary_encoding:` for round-trip.
  # Pre-10h emitted raw `::Float` because the binary form had no
  # source-string to preserve — `Primitives::Float`'s `BigDecimal`
  # storage represents the IEEE bits exactly when constructed from a
  # `::Float` (no precision loss going `IEEE → BigDecimal`), and the
  # `binary_encoding` is what carries the F32-vs-F64 distinction the
  # raw `::Float` couldn't.
  def float length, binary_encoding: nil
    raw = read_bytes(length).pack("C*").unpack1(length == 4 ? "e" : "E")
    Paradoxical::Elements::Primitives::Float.new raw, binary_encoding: binary_encoding
  end

  # Paradox's fixed-point representation: a raw little-endian integer
  # divided by 100_000. `length` is the byte width (1..7; token IDs
  # 0x0d48..0x0d4e for positive, 0x0d4f..0x0d55 for negative). Negativity
  # is *not* two's-complement — it's conveyed by a separate token range,
  # so `negative:` simply flips the sign after reading the magnitude.
  def fixed length, negative: false, binary_encoding: nil
    n = raw_int(length)
    n *= -1 if negative
    Paradoxical::Elements::Primitives::Float.new (n / 100_000.0).to_s, binary_encoding: binary_encoding
  end

  # Read a `length`-byte slice from the cursor and advance past it,
  # with truncation detection. Used by callers that need the raw byte
  # sequence (`string`/`float` to `pack`, `bool` for its single byte);
  # integer reads go through `raw_int` instead, which indexes without
  # slicing. Raises so malformed input errs loudly rather than
  # silently yielding short/empty data downstream.
  def read_bytes length
    err "unexpected end of input (wanted #{length} byte#{"s" if length != 1})" if @pos + length > @bytes.length

    slice = @bytes[@pos, length]
    @pos += length
    slice
  end

  # Non-consuming check for the `=` token (`TokenKind::EQUAL`) at the
  # cursor. Used by `read_next` to decide whether a primitive scalar
  # should be treated as a property key or a bare value. EOF or any
  # other byte sequence returns false. See MODERNIZATION.md phase 10g.
  def peek_equals?
    @pos + 2 <= @bytes.length and (@bytes[@pos + 1] << 8 | @bytes[@pos]) == TokenKind::EQUAL
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
    err "expected open token got: 0x#{open.to_i.to_s(16).rjust 4, "0"}" unless open == TokenKind::OPEN

    rtoken, r, gtoken, g, btoken, b = 3.times.flat_map { [integer(2), integer(4)] }

    close = integer 2
    atoken, a, close = close, integer(4), integer(2) unless close == TokenKind::CLOSE

    err "expected close token got: 0x#{close.to_i.to_s(16).rjust 4, "0"}" unless close == TokenKind::CLOSE

    Paradoxical::Elements::Primitives::Color::RGB.from r, g, b, alpha: a
  end

  def read_scalar is_date: false
    type = raw_int(2)

    v =
      case type
      when TokenKind::OPEN       then OPEN_MARKER
      when TokenKind::CLOSE      then CLOSE_MARKER
      when TokenKind::EQUAL      then EQUALS_MARKER
      when TokenKind::U32        then integer 4, binary_encoding: TokenKind::U32
      when TokenKind::U64        then integer 8, binary_encoding: TokenKind::U64
      when TokenKind::I32        then signed_integer 4, binary_encoding: TokenKind::I32
      when TokenKind::BOOL       then read_bytes(1).first == 1
      when TokenKind::QUOTED     then string quoted: true
      when TokenKind::UNQUOTED   then string quoted: false
      when TokenKind::F32        then float 4, binary_encoding: TokenKind::F32
      when TokenKind::F64        then float 8, binary_encoding: TokenKind::F64
      when TokenKind::RGB        then rgb
      when TokenKind::I64        then signed_integer 8, binary_encoding: TokenKind::I64
      when TokenKind::LOOKUP_08  then lookup 1, binary_encoding: TokenKind::LOOKUP_08
      when TokenKind::LOOKUP_24  then lookup 3, binary_encoding: TokenKind::LOOKUP_24
      when TokenKind::LOOKUP_16  then lookup 2, binary_encoding: TokenKind::LOOKUP_16
      when TokenKind::LOOKUP_08A then lookup 1, binary_encoding: TokenKind::LOOKUP_08A
      when TokenKind::LOOKUP_16A then lookup 2, binary_encoding: TokenKind::LOOKUP_16A
      when TokenKind::FIXED_U08  then fixed 1, binary_encoding: TokenKind::FIXED_U08
      when TokenKind::FIXED_U16  then fixed 2, binary_encoding: TokenKind::FIXED_U16
      when TokenKind::FIXED_U24  then fixed 3, binary_encoding: TokenKind::FIXED_U24
      when TokenKind::FIXED_U32  then fixed 4, binary_encoding: TokenKind::FIXED_U32
      when TokenKind::FIXED_U40  then fixed 5, binary_encoding: TokenKind::FIXED_U40
      when TokenKind::FIXED_U48  then fixed 6, binary_encoding: TokenKind::FIXED_U48
      when TokenKind::FIXED_U56  then fixed 7, binary_encoding: TokenKind::FIXED_U56
      when TokenKind::FIXED_I08  then fixed 1, negative: true, binary_encoding: TokenKind::FIXED_I08
      when TokenKind::FIXED_I16  then fixed 2, negative: true, binary_encoding: TokenKind::FIXED_I16
      when TokenKind::FIXED_I24  then fixed 3, negative: true, binary_encoding: TokenKind::FIXED_I24
      when TokenKind::FIXED_I32  then fixed 4, negative: true, binary_encoding: TokenKind::FIXED_I32
      when TokenKind::FIXED_I40  then fixed 5, negative: true, binary_encoding: TokenKind::FIXED_I40
      when TokenKind::FIXED_I48  then fixed 6, negative: true, binary_encoding: TokenKind::FIXED_I48
      when TokenKind::FIXED_I56  then fixed 7, negative: true, binary_encoding: TokenKind::FIXED_I56
      else { token: type }
      end

    # See the file-level comment for date conversion.
    # `Primitives::Integer#is_a?(Integer)` returns true via the
    # impersonator concern, so this catches every wrapped integer type.
    #
    # Range-guard against mis-converting a non-date integer that happens
    # to sit under a date-typed key (`date_tokens`): only values plainly
    # in the date range become Dates. A date is hours since the -5001
    # epoch, so real saved dates are tens of millions of hours out
    # (year -2560 ≈ 21.4M, the game era ≈ 55M, the "never" sentinel 9999
    # ≈ 131M). Small counts/flags/ids map *near* the epoch (year ~-5001),
    # i.e. far below the threshold, so a cheap `> MIN_DATE_HOURS` compare
    # — done before allocating the Date — rejects them. No upper bound:
    # a huge non-date integer under a date key is unobserved, and a
    # wrong conversion is non-fatal and round-trips losslessly anyway.
    if is_date and v.is_a?(Integer) and (hours = v.to_i) > MIN_DATE_HOURS then
      v = INITIAL_DATE + hours.hours
    end

    v
  end

  def read_list key:
    obj = Paradoxical::Elements::List.new key, []
    n = read_next
    (obj << n) and n = read_next until n.class == Hash and n[:close]
    obj
  end

  def read_doc
    doc = Paradoxical::Elements::Document.new
    doc << read_next until @pos >= @bytes.length
    doc
  end

  def read_next
    n = read_scalar

    unless n.class == Hash then
      # A primitive in key position — PDX saves use this for shapes like
      # `duration={ 66 0=0 1=0 … 65=0 }` (length-prefixed indexed map)
      # and any other case where an integer/date/string-shaped value
      # appears as a property's key. Peek the next 2 bytes: if they're
      # the `=` marker, this scalar is a key, not a bare value. See
      # MODERNIZATION.md phase 10g.
      if peek_equals? then
        read_bytes 2
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
        read_bytes 2
        return read_property_with_key inner
      end

      return inner
    end

    err "expected token, got: #{n}" if n[:token].nil?

    resolved = resolve_token_string n[:token]

    # Same peek-equals lookup as the primitive and compound-key branches:
    # the resolved identifier is a key if `=` follows, a bare value
    # otherwise. EU5 saves carry tokens in both positions — see the
    # 10e plan's empirical question, finally answered yes by the
    # ~7.4 MB-deep failure that motivated this expansion of 10g.
    if peek_equals? then
      read_bytes 2
      return read_property_with_key resolved
    end

    Paradoxical::Elements::Value.new resolved
  end

  # Shared tail of `read_next`: once we have a key and the trailing `=`,
  # read the value and assemble either a List (if `{ … }`) or a Property
  # (if a primitive or a bare token). The compound-key branch above and
  # the regular token-key branch both end here.
  def read_property_with_key key
    maybe_open = read_scalar is_date: date_tokens.include?(key.to_s)

    if not maybe_open.class == Hash then
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
      err "unexpected control token after `#{key}`: #{maybe_open}"
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

  # Read a `length`-byte little-endian index from the wire and
  # resolve it into a `Primitives::String` carrying its source
  # `lookup_index` (for resolution) and `binary_encoding` (for
  # round-trip). `length` is 1, 2, or 3 — the three widths the
  # `LOOKUP_*` token range covers. `binary_encoding` is the specific
  # `LOOKUP_*` constant — load-bearing for round-trip because byte
  # width alone can't disambiguate `LOOKUP_08` vs `LOOKUP_08A`
  # (both 1 byte) or `LOOKUP_16` vs `LOOKUP_16A` (both 2). The
  # behavior differs from `resolve_token_string`'s missing-table
  # fallback: because lookup tables are per-save (and the parser
  # receives them via the `string_lookup:` kwarg), an out-of-range
  # index when a table *is* supplied implies a mismatch between the
  # binary and the lookup — that's a hard error, not a graceful
  # degradation. When no table is supplied we emit the hex-encoded
  # `Primitives::String` shape `resolve_token_string` uses, with
  # `lookup_index` and `binary_encoding` still set so round-trip
  # knows the original wire form. See MODERNIZATION.md phases 10f / 10h.
  def lookup length, binary_encoding:
    index = raw_int(length)
    text = string_lookup ? string_lookup.resolve(index) : "0x#{index.to_s(16).rjust(4, "0")}"
    Paradoxical::Elements::Primitives::String.new(
      text,
      quoted: false,
      lookup_index: index,
      binary_encoding: binary_encoding
    )
  end

  def err msg
    raise ParseError, msg
  end
end

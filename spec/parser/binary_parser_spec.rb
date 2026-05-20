require "paradoxical"

RSpec.describe Paradoxical::BinaryParser do
  # A few token IDs reused across examples. Real Paradox binaries use
  # whatever IDs the game's token table assigns; we pick values
  # outside the scalar-type-code ranges (any 2-byte int that isn't
  # `0x0001`/`0x0003`/`0x0004`/known scalar types acts as an
  # identifier token).
  TOKEN_KEY = 0x1000
  TOKEN_DATE = 0x1001
  TOKEN_INNER = 0x1002

  # Channel identifier tokens used inside an `rgb { ... }` block.
  # The binary parser doesn't validate these against the token table
  # (the structure of the block is enough), so they don't need to be
  # registered in TOKENS to round-trip — but real game data does
  # carry the `red`/`green`/`blue`/`alpha` mapping.
  TOKEN_RED = 0x2001
  TOKEN_GREEN = 0x2002
  TOKEN_BLUE = 0x2003
  TOKEN_ALPHA = 0x2004

  TOKENS = {
    TOKEN_KEY => "key",
    TOKEN_DATE => "date",
    TOKEN_INNER => "inner",
  }

  # --- binary-format helpers ------------------------------------------------

  def u16(v)  = [v].pack("v")
  def u32(v)  = [v].pack("V")
  def u64(v)  = [v].pack("Q<")
  def i32(v)  = [v].pack("l<")
  def i64(v)  = [v].pack("q<")
  def f32(v)  = [v].pack("e")
  def f64(v)  = [v].pack("E")
  def u8(v)   = [v].pack("C")

  def eq_marker = u16(0x0001)
  def open      = u16(0x0003)
  def close     = u16(0x0004)

  def prop(token, value_bytes) = u16(token) + eq_marker + value_bytes
  def list(token, *children)   = u16(token) + eq_marker + open + children.join + close

  def uint32(v)   = u16(0x0014) + u32(v)
  def uint64(v)   = u16(0x029c) + u64(v)
  def int32(v)    = u16(0x000c) + i32(v)
  def int64(v)    = u16(0x0317) + i64(v)
  def bool(v)     = u16(0x000e) + u8(v ? 1 : 0)
  def qstring(s)  = u16(0x000f) + u16(s.bytesize) + s
  def ustring(s)  = u16(0x0017) + u16(s.bytesize) + s
  def float32(v)  = u16(0x000d) + f32(v)
  def float64(v)  = u16(0x0167) + f64(v)

  # 24-bit fixed: stored as raw int / 100_000. 250_000 → 2.5
  def fixed24(raw) = u16(0x0d4a) + [raw].pack("V")[0, 3]

  # 0x0243 then `{ red <u32> green <u32> blue <u32> [alpha <u32>] }`.
  # Channel values are raw little-endian uint32s — no per-channel
  # 0x0014 type prefix (the outer 0x0243 marker is the typing context).
  def rgb_value(r, g, b, alpha: nil)
    inner = u16(TOKEN_RED) + u32(r) + u16(TOKEN_GREEN) + u32(g) + u16(TOKEN_BLUE) + u32(b)
    inner += u16(TOKEN_ALPHA) + u32(alpha) unless alpha.nil?
    u16(0x0243) + open + inner + close
  end

  def parse(bytes, tokens: TOKENS)
    Paradoxical::BinaryParser.parse(bytes, tokens: tokens)
  end

  # --- specs ----------------------------------------------------------------

  describe "primitives" do
    it "wraps uint32 values in Primitives::Integer" do
      doc = parse(prop(TOKEN_KEY, uint32(42)))
      property = doc.first

      expect(property).to be_a(Paradoxical::Elements::Property)
      expect(property.key).to eq("key")
      expect(property.value).to be_a(Paradoxical::Elements::Primitives::Integer)
      expect(property.value.to_i).to eq(42)
    end

    it "wraps uint64 values in Primitives::Integer" do
      doc = parse(prop(TOKEN_KEY, uint64(1 << 40)))
      expect(doc.first.value).to be_a(Paradoxical::Elements::Primitives::Integer)
      expect(doc.first.value.to_i).to eq(1 << 40)
    end

    it "wraps int32 negative values in Primitives::Integer" do
      doc = parse(prop(TOKEN_KEY, int32(-7)))
      expect(doc.first.value).to be_a(Paradoxical::Elements::Primitives::Integer)
      expect(doc.first.value.to_i).to eq(-7)
    end

    it "wraps int64 negative values in Primitives::Integer" do
      doc = parse(prop(TOKEN_KEY, int64(-(1 << 40))))
      expect(doc.first.value).to be_a(Paradoxical::Elements::Primitives::Integer)
      expect(doc.first.value.to_i).to eq(-(1 << 40))
    end

    it "returns raw Ruby booleans (intentionally not wrapped)" do
      doc = parse(prop(TOKEN_KEY, bool(true)))
      expect(doc.first.value).to be(true)

      doc = parse(prop(TOKEN_KEY, bool(false)))
      expect(doc.first.value).to be(false)
    end

    it "wraps quoted strings in Primitives::String with quoted: true" do
      doc = parse(prop(TOKEN_KEY, qstring("hi")))
      expect(doc.first.value).to be_a(Paradoxical::Elements::Primitives::String)
      expect(doc.first.value.to_s).to eq("hi")
      expect(doc.first.value.quoted?).to be(true)
    end

    it "wraps unquoted strings in Primitives::String with quoted: false" do
      doc = parse(prop(TOKEN_KEY, ustring("hi")))
      expect(doc.first.value).to be_a(Paradoxical::Elements::Primitives::String)
      expect(doc.first.value.quoted?).to be(false)
    end

    it "returns raw Ruby ::Float for IEEE float (0x000d)" do
      doc = parse(prop(TOKEN_KEY, float32(1.5)))
      expect(doc.first.value).to be_a(::Float)
      expect(doc.first.value).to be_within(1e-6).of(1.5)
    end

    it "returns raw Ruby ::Float for IEEE double (0x0167)" do
      doc = parse(prop(TOKEN_KEY, float64(1.5)))
      expect(doc.first.value).to be_a(::Float)
      expect(doc.first.value).to eq(1.5)
    end

    it "wraps 24-bit fixed-point values in Primitives::Float" do
      # 250_000 / 100_000 = 2.5
      doc = parse(prop(TOKEN_KEY, fixed24(250_000)))
      expect(doc.first.value).to be_a(Paradoxical::Elements::Primitives::Float)
      expect(doc.first.value.to_f).to eq(2.5)
    end
  end

  describe "rgb" do
    it "parses an rgb block without alpha into a Color::RGB" do
      doc = parse(prop(TOKEN_KEY, rgb_value(255, 128, 0)))
      rgb = doc.first.value

      expect(rgb).to be_a(Paradoxical::Elements::Primitives::Color::RGB)
      expect([rgb.r.to_i, rgb.g.to_i, rgb.b.to_i]).to eq([255, 128, 0])
      expect(rgb.alpha).to be_nil
    end

    it "parses the optional alpha channel as the 4th component" do
      doc = parse(prop(TOKEN_KEY, rgb_value(255, 128, 0, alpha: 200)))
      rgb = doc.first.value

      expect([rgb.r.to_i, rgb.g.to_i, rgb.b.to_i, rgb.alpha.to_i]).to eq([255, 128, 0, 200])
    end

    it "does not require the inner identifier tokens to be in the token table" do
      # Channel tokens are intentionally absent from `tokens:`; the parser still
      # accepts the block because it identifies the form by structure, not by name.
      doc = parse(prop(TOKEN_KEY, rgb_value(10, 20, 30)),
                  tokens: { TOKEN_KEY => "key" })
      rgb = doc.first.value

      expect([rgb.r.to_i, rgb.g.to_i, rgb.b.to_i]).to eq([10, 20, 30])
    end

    it "raises ParseError when the rgb body does not open with `{`" do
      # 0x0243 followed immediately by `}` (0x0004) instead of `{` (0x0003).
      malformed = prop(TOKEN_KEY, u16(0x0243) + close)

      expect { parse(malformed) }
        .to raise_error(Paradoxical::BinaryParser::ParseError, /expected open token/)
    end

    it "raises ParseError when the close `}` is missing after the alpha channel" do
      # Three channels, then a (bogus-but-shaped) alpha pair, then a bogus
      # final close token instead of 0x0004.
      bad =
        u16(0x0243) + open +
        u16(TOKEN_RED)   + u32(1) +
        u16(TOKEN_GREEN) + u32(2) +
        u16(TOKEN_BLUE)  + u32(3) +
        u16(TOKEN_ALPHA) + u32(4) +
        u16(0xDEAD)
      expect { parse(prop(TOKEN_KEY, bad)) }
        .to raise_error(Paradoxical::BinaryParser::ParseError, /expected close token/)
    end
  end

  describe "properties and lists" do
    it "parses a property at document top level" do
      doc = parse(prop(TOKEN_KEY, uint32(7)))
      expect(doc).to be_a(Paradoxical::Elements::Document)
      expect(doc.size).to eq(1)
      expect(doc.first).to be_a(Paradoxical::Elements::Property)
      expect(doc.first.operator).to eq("=")
    end

    it "parses a list of scalars" do
      doc = parse(list(TOKEN_KEY, uint32(1), uint32(2), uint32(3)))
      list = doc.first

      expect(list).to be_a(Paradoxical::Elements::List)
      expect(list.key).to eq("key")
      expect(list.size).to eq(3)
      list.each do |child|
        expect(child).to be_a(Paradoxical::Elements::Value)
      end
      expect(list.map { |c| c.value.to_i }).to eq([1, 2, 3])
    end

    it "parses nested lists with properties" do
      inner = list(TOKEN_INNER, uint32(10), uint32(20))
      doc = parse(list(TOKEN_KEY, inner))

      outer = doc.first
      expect(outer).to be_a(Paradoxical::Elements::List)
      expect(outer.key).to eq("key")
      expect(outer.size).to eq(1)

      inner_list = outer.first
      expect(inner_list).to be_a(Paradoxical::Elements::List)
      expect(inner_list.key).to eq("inner")
      expect(inner_list.map { |c| c.value.to_i }).to eq([10, 20])
    end

    it "parses multiple top-level properties" do
      doc = parse(prop(TOKEN_KEY, uint32(1)) + prop(TOKEN_INNER, uint32(2)))
      expect(doc.size).to eq(2)
      expect(doc.map { |p| [p.key, p.value.to_i] }).to eq([["key", 1], ["inner", 2]])
    end
  end

  describe "compound keys" do
    # PDX save files use a `{ … }={ … }` shape — a sub-list on the LHS of `=` —
    # for maps keyed by an object rather than an identifier. EU5 alone ships
    # 24,541 of these in one probe save. See MODERNIZATION.md phase 10.

    it "parses a compound-key Property when the value is a primitive" do
      # `{ key=42 } = 100` at document top level.
      body =
        open +
        u16(TOKEN_KEY) + eq_marker + uint32(42) +
        close +
        eq_marker +
        uint32(100)

      doc = parse(body)
      prop = doc.first

      expect(prop).to be_a(Paradoxical::Elements::Property)
      expect(prop.operator).to eq("=")
      expect(prop.key).to be_a(Paradoxical::Elements::List)
      expect(prop.key.first).to be_a(Paradoxical::Elements::Property)
      expect(prop.key.first.key).to eq("key")
      expect(prop.key.first.value.to_i).to eq(42)
      expect(prop.value.to_i).to eq(100)
    end

    it "parses a compound-key List when the value is itself a list" do
      # `{ key=1 } = { 37 43 47 }` — mirrors the EU5 demand-spec → pop-IDs
      # shape. The result is a List (compound key + list value), not a
      # Property, matching the rest of the parser's "RHS is `{…}` → List"
      # convention.
      body =
        open +
        u16(TOKEN_KEY) + eq_marker + uint32(1) +
        close +
        eq_marker +
        open + uint32(37) + uint32(43) + uint32(47) + close

      doc = parse(body)
      list = doc.first

      expect(list).to be_a(Paradoxical::Elements::List)
      expect(list.key).to be_a(Paradoxical::Elements::List)
      expect(list.key.first.key).to eq("key")
      expect(list.key.first.value.to_i).to eq(1)
      expect(list.map { |v| v.value.to_i }).to eq([37, 43, 47])
    end

    it "parses a compound-keyed pair nested inside an outer keyed list" do
      # `outer = { { key=1 }={ 37 43 47 } }` — the realistic shape, where
      # the compound pair appears as a child of an outer keyed map.
      inner =
        open +
        u16(TOKEN_KEY) + eq_marker + uint32(1) +
        close +
        eq_marker +
        open + uint32(37) + uint32(43) + uint32(47) + close

      doc = parse(u16(TOKEN_INNER) + eq_marker + open + inner + close)
      outer = doc.first

      expect(outer).to be_a(Paradoxical::Elements::List)
      expect(outer.key).to eq("inner")
      expect(outer.size).to eq(1)

      compound = outer.first
      expect(compound).to be_a(Paradoxical::Elements::List)
      expect(compound.key).to be_a(Paradoxical::Elements::List)
      expect(compound.map { |v| v.value.to_i }).to eq([37, 43, 47])
    end

    it "treats a `{ … }` not followed by `=` as a keyless list, not a compound key" do
      # `{ 42 } 100` — close brace then a value, no `=`. The leading
      # `{...}` is a keyless sub-list at the same level as the trailing
      # bare value. See MODERNIZATION.md phase 10g.
      body = open + uint32(42) + close + uint32(100)

      doc = parse(body)

      expect(doc.size).to eq(2)
      expect(doc.first).to be_a(Paradoxical::Elements::List)
      expect(doc.first.key).to be_nil
      expect(doc.first.map { |c| c.value.to_i }).to eq([42])
      expect(doc[1]).to be_a(Paradoxical::Elements::Value)
      expect(doc[1].value.to_i).to eq(100)
    end
  end

  describe "scalar-keyed properties (peek-equals lookup)" do
    # Phase 10g — `read_next` peeks for `=` after every parsed thing
    # (primitive, sub-list, token) to decide key-vs-value. See
    # MODERNIZATION.md phase 10g.

    it "treats an integer in a list as a key when followed by `=`" do
      # `key = { 0 = 1 }` — single integer-keyed property inside a
      # list. Without 10g, the `0` would be read as a bare Value and
      # the `=` would crash the parser.
      body = u16(TOKEN_KEY) + eq_marker + open +
             int32(0) + eq_marker + int32(1) +
             close

      list = parse(body).first
      expect(list).to be_a(Paradoxical::Elements::List)
      expect(list.size).to eq(1)
      expect(list.first).to be_a(Paradoxical::Elements::Property)
      expect(list.first.key.to_i).to eq(0)
      expect(list.first.value.to_i).to eq(1)
    end

    it "parses the EU5 length-prefixed indexed-map shape (`duration={ N 0=v 1=v … }`)" do
      # `duration={ 3 0=10 1=20 2=30 }` — leading bare int + three
      # integer-keyed properties. The leading int is the count; the
      # parser stays structurally neutral and represents it as the
      # literal mix.
      body = u16(TOKEN_KEY) + eq_marker + open +
             int32(3) +
             int32(0) + eq_marker + int32(10) +
             int32(1) + eq_marker + int32(20) +
             int32(2) + eq_marker + int32(30) +
             close

      list = parse(body).first
      expect(list.size).to eq(4)
      expect(list[0]).to be_a(Paradoxical::Elements::Value)
      expect(list[0].value.to_i).to eq(3)
      expect(list[1..3].map { |p| [p.key.to_i, p.value.to_i] }).to eq([[0, 10], [1, 20], [2, 30]])
    end

    it "treats a token in a list as a key when followed by `=`, value otherwise" do
      # `key = { TOKEN_INNER = 1 TOKEN_INNER }` — first occurrence is
      # a key (followed by `=`), second is a bare value (followed by
      # `}`).
      body = u16(TOKEN_KEY) + eq_marker + open +
             u16(TOKEN_INNER) + eq_marker + uint32(1) +
             u16(TOKEN_INNER) +
             close

      list = parse(body).first
      expect(list.size).to eq(2)
      expect(list[0]).to be_a(Paradoxical::Elements::Property)
      expect(list[0].key.to_s).to eq("inner")
      expect(list[0].value.to_i).to eq(1)
      expect(list[1]).to be_a(Paradoxical::Elements::Value)
      expect(list[1].value.to_s).to eq("inner")
    end

    it "parses a keyless sub-list as a sibling of other children" do
      # `key = { 1 { 2 3 } 4 }` — bare value, keyless sub-list, bare
      # value. The sub-list has key=nil and contains two values.
      body = u16(TOKEN_KEY) + eq_marker + open +
             uint32(1) +
             open + uint32(2) + uint32(3) + close +
             uint32(4) +
             close

      list = parse(body).first
      expect(list.size).to eq(3)
      expect(list[0].value.to_i).to eq(1)
      expect(list[1]).to be_a(Paradoxical::Elements::List)
      expect(list[1].key).to be_nil
      expect(list[1].map { |c| c.value.to_i }).to eq([2, 3])
      expect(list[2].value.to_i).to eq(4)
    end
  end

  describe "token resolution" do
    # Phase 10e — `Primitives::String` with `token_index:` is the shape
    # the binary parser emits for any identifier resolved via the
    # per-game `tokens:` table, regardless of whether the token appeared
    # in key or value position. See MODERNIZATION.md phase 10e.
    TOKEN_VAL = 0x3000

    it "wraps resolved keys in Primitives::String with token_index set" do
      doc = parse(prop(TOKEN_KEY, uint32(1)))
      key = doc.first.key

      expect(key).to be_a(Paradoxical::Elements::Primitives::String)
      expect(key.to_s).to eq("key")
      expect(key.token_index).to eq(TOKEN_KEY)
      expect(key).not_to be_quoted
    end

    it "renders unresolved keys as a hex-encoded Primitives::String with token_index set" do
      doc = parse(prop(0xDEAD, uint32(1)), tokens: {})
      key = doc.first.key

      expect(key).to be_a(Paradoxical::Elements::Primitives::String)
      expect(key.to_s).to eq("0xdead")
      expect(key.token_index).to eq(0xDEAD)
    end

    it "resolves a bare token in value position" do
      # `key = <token>` — EU5's compression for repeated RHS identifiers
      # like `yes`/`no` and enum names.
      doc = parse(u16(TOKEN_KEY) + eq_marker + u16(TOKEN_VAL),
                  tokens: TOKENS.merge(TOKEN_VAL => "yes"))
      value = doc.first.value

      expect(value).to be_a(Paradoxical::Elements::Primitives::String)
      expect(value.to_s).to eq("yes")
      expect(value.token_index).to eq(TOKEN_VAL)
      expect(value).not_to be_quoted
    end

    it "renders an unresolved value-position token as a hex-encoded Primitives::String" do
      doc = parse(u16(TOKEN_KEY) + eq_marker + u16(0xCAFE),
                  tokens: TOKENS)
      value = doc.first.value

      expect(value).to be_a(Paradoxical::Elements::Primitives::String)
      expect(value.to_s).to eq("0xcafe")
      expect(value.token_index).to eq(0xCAFE)
    end

    describe "Primitives::String#token_index semantics" do
      it "defaults to nil when not supplied" do
        s = Paradoxical::Elements::Primitives::String.new "foo", quoted: false
        expect(s.token_index).to be_nil
      end

      it "is round-trip metadata — equality ignores it" do
        a = Paradoxical::Elements::Primitives::String.new "foo", quoted: false, token_index: 1
        b = Paradoxical::Elements::Primitives::String.new "foo", quoted: false, token_index: 999
        c = Paradoxical::Elements::Primitives::String.new "foo", quoted: false

        expect(a).to eq(b)
        expect(a).to eq(c)
        expect(a).to eq("foo")
      end

      it "is preserved across dup" do
        original = Paradoxical::Elements::Primitives::String.new "foo", quoted: false, token_index: 42
        expect(original.dup.token_index).to eq(42)
      end
    end
  end

  describe "dates" do
    # `date = <hours since -5001.01.01>` — the integer value is converted
    # to a Primitives::Date on the property.
    it "converts integer values under the `date` key to Primitives::Date" do
      doc = parse(prop(TOKEN_DATE, uint32(0)))
      expect(doc.first.key).to eq("date")
      expect(doc.first.value).to be_a(Paradoxical::Elements::Primitives::Date)
      # 0 hours since -5001.01.01 → the epoch itself.
      expect(doc.first.value).to eq(Paradoxical::BinaryParser::INITIAL_DATE)
    end

    it "advances by one day per 24 hours" do
      doc = parse(prop(TOKEN_DATE, uint32(24)))
      date = doc.first.value
      expect(date).to be_a(Paradoxical::Elements::Primitives::Date)
      expect(date).to eq(Paradoxical::BinaryParser::INITIAL_DATE + 24.hours)
    end

    it "leaves non-`date` integers as Primitives::Integer" do
      doc = parse(prop(TOKEN_KEY, uint32(0)))
      expect(doc.first.value).to be_a(Paradoxical::Elements::Primitives::Integer)
    end
  end

  describe "token lookup" do
    it "looks keys up in the supplied table" do
      doc = parse(prop(TOKEN_KEY, uint32(1)))
      expect(doc.first.key).to eq("key")
    end

    it "renders missing tokens as the hex-encoded form for visibility" do
      doc = parse(prop(0xDEAD, uint32(1)), tokens: {})
      # The token-resolution describe covers the structural shape — this
      # one anchors the "what does an unresolved key look like" answer
      # next to its "table-hit" sibling above.
      expect(doc.first.key).to eq("0xdead")
    end

    it "respects an explicit `tokens:` kwarg over `default_tokens`" do
      Paradoxical::BinaryParser.default_tokens = { TOKEN_KEY => "from_default" }
      doc = Paradoxical::BinaryParser.parse(
        prop(TOKEN_KEY, uint32(1)),
        tokens: { TOKEN_KEY => "from_explicit" },
      )
      expect(doc.first.key).to eq("from_explicit")
    ensure
      Paradoxical::BinaryParser.default_tokens = {}
    end

    it "uses `default_tokens` when no `tokens:` is passed" do
      Paradoxical::BinaryParser.default_tokens = { TOKEN_KEY => "from_default" }
      doc = Paradoxical::BinaryParser.parse(prop(TOKEN_KEY, uint32(1)))
      expect(doc.first.key).to eq("from_default")
    ensure
      Paradoxical::BinaryParser.default_tokens = {}
    end
  end

  describe "ParseError" do
    it "raises ParseError on truncated input" do
      # Property header but value cut off mid-uint32.
      truncated = u16(TOKEN_KEY) + eq_marker + u16(0x0014) + u16(0x0102)
      expect { parse(truncated) }
        .to raise_error(Paradoxical::BinaryParser::ParseError, /end of input/)
    end

    it "treats a token not followed by `=` as a bare token-as-value, not an error" do
      # `<token> <uint32>` at top level — two siblings, no property
      # relationship. The token resolves to its identifier-shaped
      # `Primitives::String` and gets wrapped as a Value rather than
      # waiting for an `=`. See MODERNIZATION.md phase 10g.
      doc = parse(u16(TOKEN_KEY) + uint32(1))

      expect(doc.size).to eq(2)
      expect(doc[0]).to be_a(Paradoxical::Elements::Value)
      expect(doc[0].value.to_s).to eq("key")
      expect(doc[1]).to be_a(Paradoxical::Elements::Value)
      expect(doc[1].value.to_i).to eq(1)
    end
  end
end

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

    it "falls back to the raw 2-byte integer when a token is missing" do
      doc = parse(prop(0xDEAD, uint32(1)), tokens: {})
      expect(doc.first.key).to eq(0xDEAD)
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
      truncated = u16(TOKEN_KEY) + eq_marker + u16(0x0014) + "\x01\x02"
      expect { parse(truncated) }
        .to raise_error(Paradoxical::BinaryParser::ParseError, /end of input/)
    end

    it "raises ParseError when `=` is missing between key and value" do
      bad = u16(TOKEN_KEY) + uint32(1)
      expect { parse(bad) }
        .to raise_error(Paradoxical::BinaryParser::ParseError, /expected `=`/)
    end

    it "raises ParseError for the unimplemented binary-rgb type" do
      expect { parse(prop(TOKEN_KEY, u16(0x0243))) }
        .to raise_error(Paradoxical::BinaryParser::ParseError, /binary rgb/)
    end
  end
end

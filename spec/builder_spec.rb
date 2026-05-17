require "paradoxical"

RSpec.describe Paradoxical::Builder do
  let(:builder) { described_class.new.tap { |b| b.instance_variable_set(:@elements, []) } }

  describe "#date" do
    it "accepts three explicit integer components" do
      d = builder.date(1444, 11, 11)
      expect(d).to be_a(Paradoxical::Elements::Primitives::Date)
      expect(d.year).to eq(1444)
      expect(d.month).to eq(11)
      expect(d.day).to eq(11)
    end

    it "accepts a single string with `.` separator (PDX-native)" do
      d = builder.date("1444.11.11")
      expect(d.year).to eq(1444)
      expect(d.month).to eq(11)
      expect(d.day).to eq(11)
    end

    it "accepts a single string with `-` separator (ISO style)" do
      d = builder.date("1444-11-11")
      expect(d.year).to eq(1444)
      expect(d.month).to eq(11)
      expect(d.day).to eq(11)
    end

    it "accepts a single string with `/` separator" do
      d = builder.date("1444/11/11")
      expect(d.year).to eq(1444)
      expect(d.month).to eq(11)
      expect(d.day).to eq(11)
    end

    it "accepts a negative integer year (BC date)" do
      d = builder.date(-43, 1, 1)
      expect(d.year).to eq(-43)
    end

    it "accepts a BC year via a `-`-prefixed string with `.` separator" do
      d = builder.date("-43.1.1")
      expect(d.year).to eq(-43)
    end

    it "accepts a BC year via a `-`-prefixed string with `-` separator" do
      # The leading `-` is a sign, not a separator — disambiguated by
      # the split producing 4 pieces with an empty first element.
      d = builder.date("-43-1-1")
      expect(d.year).to eq(-43)
      expect(d.month).to eq(1)
      expect(d.day).to eq(1)
    end

    it "produces a date whose to_pdx is the canonical `.`-separated form" do
      expect(builder.date("1444-11-11").to_pdx).to eq("1444.11.11")
    end

    it "carries the active calendar" do
      d = builder.date(1444, 11, 11)
      expect(d.calendar).to eq(Paradoxical::Elements::Primitives::Date.default_calendar)
    end

    it "raises on the wrong number of args" do
      expect { builder.date(1444, 11) }.to raise_error(ArgumentError, /3 components or a single string/)
      expect { builder.date }.to raise_error(ArgumentError, /3 components or a single string/)
    end

    it "raises when a single-string arg doesn't split into 3 components" do
      expect { builder.date("1444.11") }.to raise_error(ArgumentError, /3 components/)
      expect { builder.date("1444.11.11.extra") }.to raise_error(ArgumentError, /3 components/)
    end
  end

  describe "#rgb" do
    it "accepts 3 integer components" do
      c = builder.rgb(255, 128, 0)
      expect(c).to be_a(Paradoxical::Elements::Primitives::Color::RGB)
      expect(c.r.to_i).to eq(255)
      expect(c.g.to_i).to eq(128)
      expect(c.b.to_i).to eq(0)
      expect(c.alpha).to be_nil
    end

    it "accepts 4 integer components (positional alpha)" do
      c = builder.rgb(255, 128, 0, 200)
      expect(c.alpha.to_i).to eq(200)
    end

    it "accepts 3 components with alpha via kwarg" do
      c = builder.rgb(255, 128, 0, alpha: 200)
      expect(c.alpha.to_i).to eq(200)
    end

    it "kwarg alpha overrides positional alpha" do
      c = builder.rgb(255, 128, 0, 50, alpha: 200)
      expect(c.alpha.to_i).to eq(200)
    end

    it "accepts a 6-digit hex string" do
      c = builder.rgb("ff8000")
      expect(c.r.to_i).to eq(0xff)
      expect(c.g.to_i).to eq(0x80)
      expect(c.b.to_i).to eq(0x00)
      expect(c.alpha).to be_nil
    end

    it "accepts hex string with `#` or `0x` prefix" do
      expect(builder.rgb("#ff8000").r.to_i).to eq(0xff)
      expect(builder.rgb("0xff8000").r.to_i).to eq(0xff)
    end

    it "accepts an 8-digit hex string (RRGGBBAA)" do
      c = builder.rgb("ff8000c0")
      expect(c.r.to_i).to eq(0xff)
      expect(c.alpha.to_i).to eq(0xc0)
    end

    it "accepts a raw integer (6-hex range = no alpha)" do
      c = builder.rgb(0xff8000)
      expect(c.r.to_i).to eq(0xff)
      expect(c.g.to_i).to eq(0x80)
      expect(c.b.to_i).to eq(0x00)
      expect(c.alpha).to be_nil
    end

    it "accepts a raw integer (>0xffffff = 8-hex form with alpha)" do
      c = builder.rgb(0xff8000c0)
      expect(c.r.to_i).to eq(0xff)
      expect(c.alpha.to_i).to eq(0xc0)
    end

    it "kwarg alpha overrides hex/integer-embedded alpha" do
      c = builder.rgb("ff8000c0", alpha: 50)
      expect(c.alpha.to_i).to eq(50)
    end

    it "accepts Float components for float-RGB" do
      c = builder.rgb(0.5, 0.3, 0.1)
      expect(c.r).to be_a(Paradoxical::Elements::Primitives::Float)
      expect(c.r.to_f).to eq(0.5)
    end

    it "raises on a too-short hex string" do
      expect { builder.rgb("ff80") }.to raise_error(ArgumentError, /6 or 8 hex digits/)
    end

    it "raises on a negative integer" do
      expect { builder.rgb(-1) }.to raise_error(ArgumentError, /0\.\.0xffffffff/)
    end

    it "raises on wrong arg count" do
      expect { builder.rgb(1, 2) }.to raise_error(ArgumentError, /1.*3.*4/)
    end
  end

  describe "#hex" do
    it "delegates to rgb then converts" do
      c = builder.hex(255, 128, 0)
      expect(c).to be_a(Paradoxical::Elements::Primitives::Color::Hex)
      expect(c.literal).to eq("0xff8000")
    end

    it "round-trips a hex string (hex(\"ff8000\") -> rgb -> hex == same bytes)" do
      c = builder.hex("ff8000")
      expect(c.literal).to eq("0xff8000")
    end

    it "preserves alpha through the rgb -> hex conversion" do
      c = builder.hex(255, 128, 0, alpha: 192)
      expect(c.literal).to eq("0xff8000c0")
    end
  end

  describe "#hsv" do
    it "accepts 3 components" do
      c = builder.hsv(0.5, 0.8, 1.0)
      expect(c).to be_a(Paradoxical::Elements::Primitives::Color::HSV)
      expect(c.h.to_f).to eq(0.5)
    end

    it "accepts 4 components (positional alpha)" do
      c = builder.hsv(0.5, 0.8, 1.0, 0.5)
      expect(c.alpha.to_f).to eq(0.5)
    end

    it "accepts alpha as a kwarg" do
      c = builder.hsv(0.5, 0.8, 1.0, alpha: 0.5)
      expect(c.alpha.to_f).to eq(0.5)
    end

    it "raises on wrong arg count" do
      expect { builder.hsv(0.5, 0.8) }.to raise_error(ArgumentError, /3 or 4/)
    end
  end

  describe "#hsv360" do
    it "accepts 3 integer components" do
      c = builder.hsv360(245, 40, 100)
      expect(c).to be_a(Paradoxical::Elements::Primitives::Color::HSV360)
      expect(c.h.to_i).to eq(245)
    end

    it "rejects 4 components (no PDX game emits 4-component hsv360)" do
      expect { builder.hsv360(245, 40, 100, 50) }.to raise_error(ArgumentError, /3 components/)
    end

    it "does not accept an alpha kwarg" do
      expect { builder.hsv360(245, 40, 100, alpha: 50) }.to raise_error(ArgumentError)
    end

    it "rejects Float components (HSV360 is all-int)" do
      expect { builder.hsv360(245.5, 40, 100) }.to raise_error(ArgumentError, /must all be Integer/)
    end
  end

  describe "#percent" do
    it "accepts a Ruby Integer and appends %" do
      p = builder.percent(50)
      expect(p).to be_a(Paradoxical::Elements::Primitives::Percentage)
      expect(p.to_pdx).to eq("50%")
      expect(p.value).to eq(BigDecimal("50"))
    end

    it "accepts a Ruby Float and routes through to_pdx (precision-capped)" do
      # Goes through `::Float#to_pdx` so output respects the active
      # game's FLOAT_PRECISION cap (default 3 — `0.50000` → `0.5`).
      p = builder.percent(12.5)
      expect(p.to_pdx).to eq("12.5%")
    end

    it "accepts a BigDecimal as plain decimal (not scientific)" do
      # Default BigDecimal#to_s would emit scientific notation
      # (`0.125e2`); `to_pdx` is the plain-decimal formatter.
      p = builder.percent(BigDecimal("12.5"))
      expect(p.to_pdx).to eq("12.5%")
    end

    it "accepts a string and appends % when missing" do
      expect(builder.percent("50").to_pdx).to eq("50%")
    end

    it "accepts a string with trailing % (no double-append)" do
      expect(builder.percent("50%").to_pdx).to eq("50%")
    end

    it "preserves multi-% strings (localization-template escape)" do
      expect(builder.percent("+10.00%%").to_pdx).to eq("+10.00%%")
    end

    it "accepts a negative number" do
      expect(builder.percent(-25).to_pdx).to eq("-25%")
    end

    it "accepts a Primitives::Float (routes through to_pdx)" do
      pf = Paradoxical::Elements::Primitives::Float.new("7.5")
      expect(builder.percent(pf).to_pdx).to eq("7.5%")
    end
  end

  describe "#var_ref" do
    it "accepts a name without leading @ and prepends it" do
      v = builder.var_ref("my_const")
      expect(v).to be_a(Paradoxical::Elements::Primitives::VariableRef)
      expect(v.to_pdx).to eq("@my_const")
      expect(v.name).to eq("my_const")
    end

    it "accepts a name with leading @ (no double-prefix)" do
      expect(builder.var_ref("@my_const").to_pdx).to eq("@my_const")
    end

    it "accepts a Symbol" do
      expect(builder.var_ref(:my_const).to_pdx).to eq("@my_const")
    end

    it "builds and pushes a definition property when a value is given" do
      prop = builder.var_ref(:scale, 100)
      expect(prop).to be_a(Paradoxical::Elements::Property)
      expect(prop.key).to be_a(Paradoxical::Elements::Primitives::VariableRef)
      expect(prop.key.name).to eq("scale")
      expect(prop.value).to eq(100)
      expect(builder.elements).to include(prop)
    end

    it "two-arg form normalizes the leading @" do
      prop = builder.var_ref("@base_rate", 50)
      expect(prop.key.to_pdx).to eq("@base_rate")
    end
  end

  describe "#property auto-coercion of @-prefixed strings" do
    it "wraps an @-prefixed string key as a VariableRef" do
      prop = builder.p("@foo", 5)
      expect(prop.key).to be_a(Paradoxical::Elements::Primitives::VariableRef)
      expect(prop.key.name).to eq("foo")
    end

    it "wraps an @-prefixed string value as a VariableRef" do
      prop = builder.p("x", "@foo")
      expect(prop.value).to be_a(Paradoxical::Elements::Primitives::VariableRef)
      expect(prop.value.name).to eq("foo")
    end

    it "wraps both key and value when both are @-prefixed" do
      prop = builder.p("@outer", "@inner")
      expect(prop.key).to be_a(Paradoxical::Elements::Primitives::VariableRef)
      expect(prop.value).to be_a(Paradoxical::Elements::Primitives::VariableRef)
    end

    it "respects an explicit operator (3-arg form)" do
      prop = builder.p("x", "=", "@foo")
      expect(prop.value).to be_a(Paradoxical::Elements::Primitives::VariableRef)
      expect(prop.operator).to eq("=")
    end

    it "leaves @@varname alone (template indirect, stays as String)" do
      prop = builder.p("@@indirect", 5)
      expect(prop.key).not_to be_a(Paradoxical::Elements::Primitives::VariableRef)
      expect(prop.key.to_s).to eq("@@indirect")
    end

    it "leaves @$NAME$_text alone (parameter splice, stays as String)" do
      prop = builder.p("x", "@$SIZE$_food")
      expect(prop.value).not_to be_a(Paradoxical::Elements::Primitives::VariableRef)
    end

    it "leaves @[expr] alone (computation, stays as String)" do
      prop = builder.p("x", "@[1 + 2]")
      expect(prop.value).not_to be_a(Paradoxical::Elements::Primitives::VariableRef)
    end

    it "leaves @_invalid alone (engine rejects, but stays as a String here)" do
      # See [[feedback_match_engine_error_behavior]] — engine logs and
      # returns 0; we don't fabricate a typed ref out of invalid input.
      prop = builder.p("@_invalid", 5)
      expect(prop.key).not_to be_a(Paradoxical::Elements::Primitives::VariableRef)
    end

    it "leaves bare @ alone (too short to be a ref)" do
      prop = builder.p("@", 5)
      expect(prop.key).not_to be_a(Paradoxical::Elements::Primitives::VariableRef)
    end

    it "leaves an @-prefixed string with whitespace alone (invalid name shape)" do
      # `"@foo bar"` is not a valid var-ref name — typing it as one
      # would lie about the AST since the engine rejects the shape.
      prop = builder.p("x", "@foo bar")
      expect(prop.value).not_to be_a(Paradoxical::Elements::Primitives::VariableRef)
    end

    it "leaves an @-prefixed string with a dot in the tail alone" do
      prop = builder.p("x", "@foo.bar")
      expect(prop.value).not_to be_a(Paradoxical::Elements::Primitives::VariableRef)
    end

    it "leaves an explicitly-typed Primitives::String alone (caller's intent)" do
      explicit = Paradoxical::Elements::Primitives::String.new("@foo", quoted: false)
      prop = builder.p("x", explicit)
      expect(prop.value).to be(explicit)
    end
  end
end

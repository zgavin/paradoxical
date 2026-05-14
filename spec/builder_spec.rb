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

    it "accepts 4 components (positional alpha)" do
      c = builder.hsv360(245, 40, 100, 50)
      expect(c.alpha.to_i).to eq(50)
    end

    it "accepts alpha as a kwarg" do
      c = builder.hsv360(245, 40, 100, alpha: 50)
      expect(c.alpha.to_i).to eq(50)
    end

    it "rejects Float components (HSV360 is all-int)" do
      expect { builder.hsv360(245.5, 40, 100) }.to raise_error(ArgumentError, /must all be Integer/)
    end
  end
end

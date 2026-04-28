require "paradoxical"

RSpec.describe Paradoxical::Parser do
  def parse(text)
    Paradoxical::Parser.parse(text)
  end

  describe "primitives" do
    describe "integer" do
      it "parses a positive integer" do
        prop = parse("foo = 42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(42)
      end

      it "parses a negative integer" do
        prop = parse("foo = -42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(-42)
      end

      it "parses a positive-prefixed integer" do
        prop = parse("foo = +42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(42)
      end

      it "parses zero" do
        prop = parse("foo = 0").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(0)
      end
    end

    describe "float" do
      it "parses a positive float" do
        prop = parse("foo = 3.14").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(3.14)
      end

      it "parses a negative float" do
        prop = parse("foo = -3.14").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(-3.14)
      end

      it "parses a leading-dot float" do
        prop = parse("foo = .5").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(0.5)
      end

      it "parses a trailing-dot float" do
        prop = parse("foo = 5.").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(5.0)
      end
    end

    describe "boolean" do
      it "parses yes as true" do
        prop = parse("foo = yes").first
        expect(prop.value).to be(true)
      end

      it "parses no as false" do
        prop = parse("foo = no").first
        expect(prop.value).to be(false)
      end
    end

    describe "date" do
      it "parses a four-digit-year date" do
        prop = parse("foo = 1444.11.11").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Date)
        expect(prop.value.to_date).to eq(::Date.new(1444, 11, 11))
      end

      it "parses a single-digit-year date" do
        prop = parse("foo = 9.1.1").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Date)
        expect(prop.value.to_date).to eq(::Date.new(9, 1, 1))
      end
    end

    describe "placeholder (---)" do
      # PDX history files use literal `---` as a "no value" sentinel
      # (e.g. `emperor = ---` for "no emperor"). Currently stored as a
      # raw String primitive; phase 8 may give it a typed Null shape
      # but for now the simple fix preserves round-trip without
      # introducing new semantics.

      it "parses --- as a String primitive" do
        prop = parse("emperor = ---").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("---")
      end

      it "parses --- inside a list" do
        list = parse("1806.7.12 = { emperor = --- }").first
        inner = list.first
        expect(inner.value.to_s).to eq("---")
      end

      it "doesn't shadow negative integer parsing" do
        prop = parse("x = -42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(-42)
      end

      it "doesn't shadow negative float parsing" do
        prop = parse("x = -3.14").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(-3.14)
      end
    end

    describe "percentage" do
      it "parses a percentage as a String primitive" do
        prop = parse("foo = 50%").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("50%")
      end

      it "parses a negative percentage" do
        prop = parse("foo = -50%").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("-50%")
      end
    end

    describe "color" do
      it "parses an rgb color" do
        prop = parse("foo = rgb { 128 64 32 }").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color)
        expect(prop.value).to be_rgb
        expect(prop.value.colors).to eq(%w[128 64 32])
      end

      it "parses an hsv color" do
        prop = parse("foo = hsv { 0.5 0.7 0.9 }").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color)
        expect(prop.value).to be_hsv
        expect(prop.value.colors).to eq(%w[0.5 0.7 0.9])
      end
    end

    describe "string" do
      it "parses an unquoted string" do
        prop = parse("foo = bar").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value).not_to be_quoted
        expect(prop.value.to_s).to eq("bar")
      end

      it "parses a quoted string" do
        prop = parse(%(foo = "hello world")).first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value).to be_quoted
        expect(prop.value.to_s).to eq("hello world")
      end

      it "parses an empty quoted string" do
        prop = parse(%(foo = "")).first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value).to be_quoted
        expect(prop.value.to_s).to eq("")
      end

      it "parses a localization string" do
        prop = parse("foo = [ROOT.GetName]").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("[ROOT.GetName]")
      end

      it "parses a computation string" do
        prop = parse("foo = @[GetSize + 1]").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("@[GetSize + 1]")
      end

      it "parses an escaped-computation string" do
        prop = parse("foo = @\\[Total]").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("@\\[Total]")
      end

      it "parses an unquoted string starting with a non-ASCII letter" do
        # PDX games (notably EU4 country files) use accented Latin and
        # other Unicode letters as identifiers.
        prop = parse("name = Élou").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("Élou")
      end

      it "parses an unquoted string containing an apostrophe" do
        # PDX leader/ship name lists include Latin apostrophe-bearing
        # forms like `d'Ambleteuse` and `O'Brien`. The leading char is
        # a regular letter; the apostrophe and following characters are
        # accepted by the tail since `'` isn't a break character.
        prop = parse("leaders = { d'Ambleteuse }").first
        expect(prop.first).to be_a(Paradoxical::Elements::Value)
        expect(prop.first.value.to_s).to eq("d'Ambleteuse")
      end

      it "parses bare `_` as an unquoted string identifier" do
        # Stellaris uses single underscore as a placeholder/wildcard
        # key in interface fonts: `_ = { 255 0 255 }`.
        prop = parse("_ = magenta").first
        expect(prop.key.to_s).to eq("_")
      end

      it "parses `_`-prefixed unquoted strings (not bare)" do
        # `_foo` and `__bar` are common identifier shapes; the leading
        # `"_"+ ~ (LETTER|NUMBER)` alternative matches the underscore(s)
        # then the alphanumeric continuation.
        prop = parse("name = _foo").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("_foo")

        prop = parse("name = __bar").first
        expect(prop.value.to_s).to eq("__bar")
      end

      it "parses a `$NAME$` parameter-substitution string" do
        # `$NAME$` parameter substitution is supported across all PDX
        # games — it's the engine's parse-time placeholder syntax.
        # Matches via `"$" ~ (LETTER|NUMBER)` for the leading; the tail
        # accepts the closing `$` since `$` isn't a break character.
        # Stellaris is the only game that uses the negative-prefixed
        # `-$NAME$` form, which is still a separate issue tracked as B5.
        prop = parse("food = $AMOUNT$").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("$AMOUNT$")
      end
    end
  end

  describe "operators" do
    %w[= >= <= > < ?= !=].each do |op|
      it "parses the #{op.inspect} operator" do
        prop = parse("foo #{op} 5").first
        expect(prop.operator).to eq(op)
        expect(prop.value.to_i).to eq(5)
      end
    end
  end
end

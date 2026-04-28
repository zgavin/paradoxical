require "paradoxical"

RSpec.describe Paradoxical::Parser do
  def parse(text)
    Paradoxical::Parser.parse(text)
  end

  describe "primitives" do
    describe "integer" do
      it "parses a positive integer" do
        prop = parse("foo = 42\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_s).to eq("42")
      end

      it "parses a negative integer" do
        prop = parse("foo = -42\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_s).to eq("-42")
      end

      it "parses a positive-prefixed integer" do
        prop = parse("foo = +42\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_s).to eq("+42")
      end

      it "parses zero" do
        prop = parse("foo = 0\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_s).to eq("0")
      end
    end

    describe "float" do
      it "parses a positive float" do
        prop = parse("foo = 3.14\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_s).to eq("3.14")
      end

      it "parses a negative float" do
        prop = parse("foo = -3.14\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_s).to eq("-3.14")
      end

      it "parses a leading-dot float" do
        prop = parse("foo = .5\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_s).to eq(".5")
      end

      it "parses a trailing-dot float" do
        prop = parse("foo = 5.\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_s).to eq("5.")
      end
    end

    describe "boolean" do
      it "parses yes as true" do
        prop = parse("foo = yes\n").first
        expect(prop.value).to be(true)
      end

      it "parses no as false" do
        prop = parse("foo = no\n").first
        expect(prop.value).to be(false)
      end
    end

    describe "date" do
      it "parses a four-digit-year date" do
        prop = parse("foo = 1444.11.11\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Date)
        expect(prop.value.to_s).to eq("1444.11.11")
      end

      it "parses a single-digit-year date" do
        prop = parse("foo = 9.1.1\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Date)
        expect(prop.value.to_s).to eq("9.1.1")
      end

      it "round-trips into Ruby Date via #to_date" do
        prop = parse("foo = 1444.11.11\n").first
        expect(prop.value.to_date).to eq(::Date.new(1444, 11, 11))
      end
    end

    describe "percentage" do
      it "parses a percentage as a String primitive" do
        prop = parse("foo = 50%\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("50%")
      end

      it "parses a negative percentage" do
        prop = parse("foo = -50%\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("-50%")
      end
    end

    describe "color" do
      it "parses an rgb color" do
        prop = parse("foo = rgb { 128 64 32 }\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color)
        expect(prop.value).to be_rgb
        expect(prop.value.colors).to eq(%w[128 64 32])
      end

      it "parses an hsv color" do
        prop = parse("foo = hsv { 0.5 0.7 0.9 }\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color)
        expect(prop.value).to be_hsv
        expect(prop.value.colors).to eq(%w[0.5 0.7 0.9])
      end
    end

    describe "string" do
      it "parses an unquoted string" do
        prop = parse("foo = bar\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.is_quoted).to be(false)
        expect(prop.value.to_s).to eq("bar")
      end

      it "parses a quoted string" do
        prop = parse(%(foo = "hello world"\n)).first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.is_quoted).to be(true)
        expect(prop.value.to_s).to eq("hello world")
      end

      it "parses an empty quoted string" do
        prop = parse(%(foo = ""\n)).first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.is_quoted).to be(true)
        expect(prop.value.to_s).to eq("")
      end

      it "parses a localization string" do
        prop = parse("foo = [ROOT.GetName]\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("[ROOT.GetName]")
      end

      it "parses a computation string" do
        prop = parse("foo = @[GetSize + 1]\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("@[GetSize + 1]")
      end

      it "parses an escaped-computation string" do
        prop = parse("foo = @\\[Total]\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("@\\[Total]")
      end
    end
  end

  describe "operators" do
    %w[= >= <= > < ?= !=].each do |op|
      it "parses the #{op.inspect} operator" do
        prop = parse("foo #{op} 5\n").first
        expect(prop.operator).to eq(op)
        expect(prop.value.to_s).to eq("5")
      end
    end
  end
end

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
end

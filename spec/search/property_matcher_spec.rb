require "paradoxical"

RSpec.describe Paradoxical::Search::PropertyMatcher do
  describe "#initialize" do
    it "downcases the key" do
      m = described_class.new("Name")
      expect(m.key).to eq("name")
    end

    it "stores operator and value" do
      m = described_class.new("name", operator: "=", value: "alice")
      expect(m.operator).to eq("=")
      expect(m.value).to eq("alice")
    end

    it "defaults operator and value to nil" do
      m = described_class.new("name")
      expect(m.operator).to be_nil
      expect(m.value).to be_nil
    end

    it "stores case_sensitivity (the trailing i/s flag, no-op for #matches? today)" do
      m = described_class.new("name", case_sensitivity: "i")
      expect(m.case_sensitivity).to eq("i")
    end
  end

  describe "#matches?" do
    def list(text)
      # `key = { … }` parses as a List directly (no enclosing Property
      # wrapper), so `doc.first` is the List we want.
      Paradoxical::Parser.parse("wrap = #{text}").first
    end

    it "returns false for non-List, non-Document nodes" do
      prop = Paradoxical::Parser.parse("name = alice").first
      m = described_class.new("name", operator: "=", value: "alice")
      expect(m.matches?(prop)).to be false
    end

    it "returns false when the key isn't present" do
      node = list("{ name = alice }")
      m = described_class.new("missing")
      expect(m.matches?(node)).to be false
    end

    it "returns true when the key is present and no operator/value supplied (key-presence mode)" do
      node = list("{ name = alice }")
      m = described_class.new("name")
      expect(m.matches?(node)).to be true
    end

    describe "operators" do
      let(:node) { list("{ age = 42 name = alice score = 3.5 }") }

      it "= with matching string" do
        expect(described_class.new("name", operator: "=", value: "alice").matches?(node)).to be true
      end

      it "= with non-matching string" do
        expect(described_class.new("name", operator: "=", value: "bob").matches?(node)).to be false
      end

      it ">= with integer (true at boundary)" do
        expect(described_class.new("age", operator: ">=", value: 42).matches?(node)).to be true
      end

      it ">= with integer (false below)" do
        expect(described_class.new("age", operator: ">=", value: 43).matches?(node)).to be false
      end

      it "> with integer" do
        expect(described_class.new("age", operator: ">", value: 41).matches?(node)).to be true
        expect(described_class.new("age", operator: ">", value: 42).matches?(node)).to be false
      end

      it "<= with integer" do
        expect(described_class.new("age", operator: "<=", value: 42).matches?(node)).to be true
        expect(described_class.new("age", operator: "<=", value: 41).matches?(node)).to be false
      end

      it "< with integer" do
        expect(described_class.new("age", operator: "<", value: 43).matches?(node)).to be true
        expect(described_class.new("age", operator: "<", value: 42).matches?(node)).to be false
      end

      it "~= with substring" do
        expect(described_class.new("name", operator: "~=", value: "lic").matches?(node)).to be true
        expect(described_class.new("name", operator: "~=", value: "zzz").matches?(node)).to be false
      end

      it "^= with prefix" do
        expect(described_class.new("name", operator: "^=", value: "ali").matches?(node)).to be true
        expect(described_class.new("name", operator: "^=", value: "ice").matches?(node)).to be false
      end

      it "$= with suffix" do
        expect(described_class.new("name", operator: "$=", value: "ice").matches?(node)).to be true
        expect(described_class.new("name", operator: "$=", value: "ali").matches?(node)).to be false
      end

      it "coerces a numeric-looking value to Integer when property is an Integer" do
        # Search.parse emits Integer values directly, but the user can
        # also build a PropertyMatcher with a string and rely on the
        # coercion path inside #matches?.
        expect(described_class.new("age", operator: "=", value: "42").matches?(node)).to be true
      end

      it "coerces to Float when property is a Float" do
        expect(described_class.new("score", operator: "=", value: "3.5").matches?(node)).to be true
      end
    end

    it "matches against a Document at the top level" do
      doc = Paradoxical::Parser.parse("name = alice")
      m = described_class.new("name", operator: "=", value: "alice")
      expect(m.matches?(doc)).to be true
    end
  end
end

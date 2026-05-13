require "paradoxical"

RSpec.describe Paradoxical::Search::FunctionMatcher do
  describe "#initialize" do
    it "stores name and arguments" do
      m = described_class.new("nth_child", arguments: [2])
      expect(m.name).to eq("nth_child")
      expect(m.arguments).to eq([2])
    end

    it "defaults arguments to an empty array" do
      m = described_class.new("list")
      expect(m.arguments).to eq([])
    end
  end

  describe "#matches?" do
    # Build a small parsed document we can reach into for each
    # node category the function matchers know about.
    let(:doc) do
      Paradoxical::Parser.parse(<<~PDX)
        # leading comment
        country = {
          name = alice
          rank = 3
          tags = { kinetic explosive }
        }
        province = paris
      PDX
    end

    let(:country)  { doc.send(:children).find { |n| n.respond_to?(:key) and n.key == "country" } }
    let(:province) { doc.send(:children).find { |n| n.respond_to?(:key) and n.key == "province" } }
    let(:comment)  { doc.send(:children).find { |n| n.is_a?(Paradoxical::Elements::Comment) } }
    let(:name_property) { country.send(:children).find { |c| c.respond_to?(:key) and c.key == "name" } }
    let(:tags_list) { country.send(:children).find { |c| c.respond_to?(:key) and c.key == "tags" } }

    describe "category predicates" do
      it "&comment matches Comment nodes" do
        m = described_class.new("comment")
        expect(m.matches?(comment)).to be true
        expect(m.matches?(country)).to be false
      end

      it "&list matches List nodes" do
        m = described_class.new("list")
        expect(m.matches?(country)).to be true
        expect(m.matches?(name_property)).to be false
      end

      it "&property matches Property nodes" do
        m = described_class.new("property")
        expect(m.matches?(name_property)).to be true
        expect(m.matches?(country)).to be false
      end

      it "&keyable matches any node responding to :key" do
        expect(described_class.new("keyable").matches?(country)).to be true
        expect(described_class.new("keyable").matches?(name_property)).to be true
        expect(described_class.new("keyable").matches?(comment)).to be false
      end
    end

    describe "position predicates" do
      it "&first_child matches the first sibling" do
        m = described_class.new("first_child")
        expect(m.matches?(comment)).to be true
        expect(m.matches?(country)).to be false
      end

      it "&last_child matches the last sibling" do
        m = described_class.new("last_child")
        expect(m.matches?(province)).to be true
        expect(m.matches?(comment)).to be false
      end

      it "&nth_child(N) matches the Nth sibling (0-indexed)" do
        expect(described_class.new("nth_child", arguments: [1]).matches?(country)).to be true
        expect(described_class.new("nth_child", arguments: [0]).matches?(country)).to be false
      end
    end

    describe "value/key matchers" do
      it "&comment with arg matches comment text substring" do
        m = described_class.new("comment", arguments: ["leading"])
        expect(m.matches?(comment)).to be true
        expect(described_class.new("comment", arguments: ["nope"]).matches?(comment)).to be false
      end

      it "&comment with regexp arg matches the comment text" do
        # Regexp branch returns Regexp#=~'s match position (Integer) or
        # nil — not strict true/false.
        m = described_class.new("comment", arguments: [/lead/])
        expect(m.matches?(comment)).to be_truthy
      end

      it "&value(literal) matches a Property's value" do
        # `&value(paris)` against the `province = paris` property
        property_with_paris = doc.send(:children).find { |n| n.respond_to?(:key) and n.key == "province" }
        m = described_class.new("value", arguments: ["paris"])
        expect(m.matches?(property_with_paris)).to be true
      end

      it "&value_matches uses substring/regex against the value" do
        property_with_paris = doc.send(:children).find { |n| n.respond_to?(:key) and n.key == "province" }
        expect(described_class.new("value_matches", arguments: ["par"]).matches?(property_with_paris)).to be_truthy
        expect(described_class.new("value_matches", arguments: [/par/]).matches?(property_with_paris)).to be_truthy
        expect(described_class.new("value_matches", arguments: ["zzz"]).matches?(property_with_paris)).to be_falsey
      end

      it "&key_matches uses substring/regex against the key" do
        expect(described_class.new("key_matches", arguments: ["coun"]).matches?(country)).to be_truthy
        expect(described_class.new("key_matches", arguments: [/^count/]).matches?(country)).to be_truthy
        expect(described_class.new("key_matches", arguments: ["zzz"]).matches?(country)).to be_falsey
      end
    end
  end
end

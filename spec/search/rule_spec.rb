require "paradoxical"

RSpec.describe Paradoxical::Search::Rule do
  describe "#initialize" do
    it "downcases the key" do
      rule = described_class.new("CountryEvent")
      expect(rule.key).to eq("countryevent")
    end

    it "substitutes wildcard for a blank key" do
      rule = described_class.new("")
      expect(rule.key).to eq("*")
    end

    it "stores the combinator" do
      rule = described_class.new("foo", combinator: ">")
      expect(rule.combinator).to eq(">")
    end

    it "appends a property_matcher for an id selector" do
      rule = described_class.new("*", id: "42")
      m = rule.property_matchers.first
      expect(m.key).to eq("id")
      expect(m.operator).to eq("=")
      expect(m.value).to eq("42")
    end

    it "appends a property_matcher for a name selector" do
      rule = described_class.new("*", name: "alice")
      m = rule.property_matchers.first
      expect(m.key).to eq("name")
      expect(m.value).to eq("alice")
    end

    it "preserves explicit property_matchers alongside id/name" do
      extra = Paradoxical::Search::PropertyMatcher.new("rank", operator: "=", value: 3)
      rule  = described_class.new("*", id: "7", property_matchers: [extra])
      keys  = rule.property_matchers.map(&:key)
      expect(keys).to contain_exactly("rank", "id")
    end
  end

  describe "#matches?" do
    let(:doc) { Paradoxical::Parser.parse("country = { name = alice }") }
    let(:country) { doc.first }

    it "matches when key == '*' (wildcard)" do
      expect(described_class.new("*").matches?(country)).to be true
    end

    it "matches when key equals the node key (case-insensitive)" do
      expect(described_class.new("COUNTRY").matches?(country)).to be true
    end

    it "does not match when key differs" do
      expect(described_class.new("province").matches?(country)).to be false
    end

    it "does not match nodes without a key (e.g. raw Value)" do
      doc = Paradoxical::Parser.parse("foo = { bar baz }")
      # `children` is private — same access shape Rule#matches? uses
      # internally via node.send(:children).
      bare_value = doc.first.send(:children).first
      expect(described_class.new("*").matches?(bare_value)).to be true
      expect(described_class.new("bar").matches?(bare_value)).to be false
    end

    it "requires every property_matcher to pass" do
      pm_pass = Paradoxical::Search::PropertyMatcher.new("name", operator: "=", value: "alice")
      pm_fail = Paradoxical::Search::PropertyMatcher.new("name", operator: "=", value: "bob")
      expect(described_class.new("country", property_matchers: [pm_pass]).matches?(country)).to be true
      expect(described_class.new("country", property_matchers: [pm_pass, pm_fail]).matches?(country)).to be false
    end

    it "requires every function_matcher to pass" do
      fm_pass = Paradoxical::Search::FunctionMatcher.new("list")
      fm_fail = Paradoxical::Search::FunctionMatcher.new("property")
      expect(described_class.new("country", function_matchers: [fm_pass]).matches?(country)).to be true
      expect(described_class.new("country", function_matchers: [fm_pass, fm_fail]).matches?(country)).to be false
    end
  end

  describe "#objects_for" do
    let(:doc) { Paradoxical::Parser.parse("outer = { inner = { leaf = 1 } sibling = 2 }") }
    let(:outer) { doc.first }

    it "returns descendents by default (nil combinator)" do
      rule = described_class.new("*")
      objs = rule.objects_for(outer)
      keys = objs.select { |o| o.respond_to?(:key) }.map(&:key)
      expect(keys).to include("inner", "leaf", "sibling")
    end

    it "returns immediate children for combinator >" do
      rule = described_class.new("*", combinator: ">")
      objs = rule.objects_for(outer)
      keys = objs.map { |o| o.respond_to?(:key) ? o.key : nil }.compact
      expect(keys).to contain_exactly("inner", "sibling")
    end

    it "returns siblings for combinator ~" do
      inner = outer.send(:children).find { |c| c.respond_to?(:key) and c.key == "inner" }
      rule  = described_class.new("*", combinator: "~")
      objs  = rule.objects_for(inner)
      keys  = objs.map { |o| o.respond_to?(:key) ? o.key : nil }.compact
      expect(keys).to contain_exactly("sibling")
    end
  end
end

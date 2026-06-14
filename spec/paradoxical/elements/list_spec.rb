require "paradoxical"

RSpec.describe Paradoxical::Elements::List do
  def parse(text) = Paradoxical::Parser.parse(text)

  describe "#dup" do
    it "returns a distinct list with distinct children" do
      original = parse("nums = { 1 2 3 }\n").first
      copy = original.dup
      expect(copy).not_to be(original)
      expect(copy.first).not_to be(original.first)
      expect(copy.to_pdx).to eq(original.to_pdx)
    end

    it "preserves a non-default operator (regression: used to reset to `=`)" do
      original = parse("foo > { a = 1 }\n").first
      expect(original.operator).to eq(">")
      expect(original.dup.operator).to eq(">")
    end

    it "preserves operator/kind/gui_type/kind_after_key set on the instance" do
      original = parse("foo = { a = 1 }\n").first
      original.operator = ">="
      original.kind = "hsv"
      original.gui_type = true
      original.instance_variable_set(:@kind_after_key, true)

      copy = original.dup
      expect(copy.operator).to eq(">=")
      expect(copy.kind).to eq("hsv")
      expect(copy.gui_type?).to be(true)
      expect(copy.instance_variable_get(:@kind_after_key)).to be(true)
    end

    it "round-trips a kind-prefixed list (e.g. `LIST { ... }`)" do
      original = parse("foo = LIST { 1 2 3 }\n").first
      expect(original.dup.to_pdx).to eq(original.to_pdx)
    end

    it "accepts override children / key" do
      original = parse("nums = { 1 2 3 }\n").first
      replacement = parse("other = { 9 }\n").first.to_a
      copy = original.dup(children: replacement, key: "renamed")
      expect(copy.key.to_s).to eq("renamed")
      expect(copy.values.map { |v| v.value.to_s }).to eq(%w[9])
    end
  end
end

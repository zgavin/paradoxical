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

  describe "#deconstruct_keys" do
    def country
      parse(<<~PDX).first
        country = {
          name = "Francia"
          capital = 123
          color = { 1 2 3 }
        }
      PDX
    end

    it "unwraps a Property to its value" do
      result = country.deconstruct_keys([:name, :capital])
      expect(result[:name].to_s).to eq("Francia")
      expect(result[:capital].to_s).to eq("123")
    end

    it "yields the node itself for a list-valued key" do
      result = country.deconstruct_keys([:color])
      expect(result[:color]).to be_a(Paradoxical::Elements::List)
      expect(result[:color].values.map { |v| v.value.to_s }).to eq(%w[1 2 3])
    end

    it "looks keys up case-insensitively, returning them under the requested symbol" do
      expect(country.deconstruct_keys([:NAME]).keys).to eq([:NAME])
      expect(country.deconstruct_keys([:NAME])[:NAME].to_s).to eq("Francia")
    end

    it "omits absent keys rather than binding nil" do
      expect(country.deconstruct_keys([:nonexistent])).to eq({})
    end

    it "returns every keyed child when passed nil (the **rest contract)" do
      result = country.deconstruct_keys(nil)
      expect(result.keys).to contain_exactly(:name, :capital, :color)
    end

    describe "in a pattern match" do
      it "binds present keys" do
        matched =
          case country
          in { name:, capital: } then [name.to_s, capital.to_s]
          else :no_match
          end

        expect(matched).to eq(["Francia", "123"])
      end

      it "fails to match on an absent key" do
        matched =
          case country
          in { totally_missing: } then :matched
          else :no_match
          end

        expect(matched).to eq(:no_match)
      end

      it "captures every keyed child via **rest" do
        matched =
          case country
          in { **rest } then rest.keys
          end

        expect(matched).to contain_exactly(:name, :capital, :color)
      end
    end
  end
end

require "paradoxical"

RSpec.describe Paradoxical::Parser do
  def parse(text)
    Paradoxical::Parser.parse(text)
  end

  describe "parameter_block" do
    # Stellaris's `[[NAME] body ]` and `[[!NAME] body ]` constructs.
    # The body is emitted only when the parameter is set (or unset, with !).
    # See common/script_values/00_script_values.txt for a real-world use.

    it "parses a positive parameter block as a list child" do
      list = parse(<<~PDX).first
        foo = {
        \tbase = 1
        \t[[BONUS]
        \t\tadd = $BONUS$
        \t]
        \tmult = 2
        }
      PDX

      expect(list).to be_a(Paradoxical::Elements::List)
      expect(list.size).to eq(3)

      block = list[1]
      expect(block).to be_a(Paradoxical::Elements::ParameterBlock)
      expect(block.name).to eq("BONUS")
      expect(block.negated?).to be(false)
      expect(block.size).to eq(1)
      expect(block.first).to be_a(Paradoxical::Elements::Property)
      expect(block.first.key.to_s).to eq("add")
    end

    it "parses a negated parameter block (`[[!NAME]`)" do
      list = parse(<<~PDX).first
        foo = {
        \t[[!POP_GROUP]
        \t\tweighted = 1
        \t]
        }
      PDX

      block = list.first
      expect(block).to be_a(Paradoxical::Elements::ParameterBlock)
      expect(block.name).to eq("POP_GROUP")
      expect(block.negated?).to be(true)
    end

    it "round-trips parameter blocks byte-identically" do
      input = "foo = {\n\tbase = 1\n\t[[BONUS]\n\t\tadd = $BONUS$\n\t]\n\tmult = 2\n}\n"
      expect(parse(input).to_pdx).to eq(input)
    end

    it "round-trips negated parameter blocks byte-identically" do
      input = "foo = {\n\t[[!POP_GROUP]\n\t\tweighted = 1\n\t]\n}\n"
      expect(parse(input).to_pdx).to eq(input)
    end

    it "parses an empty-bodied parameter block" do
      list = parse("foo = {\n\t[[X]\n\t]\n}\n").first
      block = list.first
      expect(block).to be_a(Paradoxical::Elements::ParameterBlock)
      expect(block.name).to eq("X")
      expect(block.size).to eq(0)
    end

    it "accepts bare values in the body (parameter substitutions)" do
      # EU4 scripted_effects use `[[X] $X$ ]` to splat a parameter as a
      # bare value. The body must accept values, not just expressions —
      # a bare `$X$` is grammatically a value, since there's no operator.
      input = "limit = {\n\t[[global_trigger] $global_trigger$ ]\n}\n"
      list = parse(input).first
      block = list.first
      expect(block).to be_a(Paradoxical::Elements::ParameterBlock)
      expect(block.name).to eq("global_trigger")
      expect(block.size).to eq(1)
      expect(block.first).to be_a(Paradoxical::Elements::Value)
      expect(block.first.value.to_s).to eq("$global_trigger$")
      expect(parse(input).to_pdx).to eq(input)
    end
  end
end

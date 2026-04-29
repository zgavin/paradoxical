require "paradoxical"

RSpec.describe Paradoxical::Parser do
  def parse(text)
    Paradoxical::Parser.parse(text)
  end

  describe "code_block" do
    # EU5 city_data templates use `code [[ ... ]]` (and the assignment
    # variant `code = [[ ... ]]` in DLC files). The body is regular PDX
    # script — modeled as a List subclass with the [[ ]] framing.

    it "parses the bare-keyword form `code [[ ... ]]`" do
      list = parse(<<~PDX).first
        template foo {
        \tcode [[
        \t\tbar = baz
        \t]]
        }
      PDX

      expect(list).to be_a(Paradoxical::Elements::List)
      block = list.first
      expect(block).to be_a(Paradoxical::Elements::CodeBlock)
      expect(block).to be_a(Paradoxical::Elements::List)
      expect(block.operator?).to be(false)
      expect(block.size).to eq(1)
      expect(block.first).to be_a(Paradoxical::Elements::Property)
      expect(block.first.key.to_s).to eq("bar")
    end

    it "parses the assignment form `code = [[ ... ]]`" do
      list = parse(<<~PDX).first
        block = {
        \tcode = [[
        \t\tinner_thing = ok
        \t]]
        }
      PDX

      block = list.first
      expect(block).to be_a(Paradoxical::Elements::CodeBlock)
      expect(block.operator?).to be(true)
      expect(block.size).to eq(1)
      expect(block.first.key.to_s).to eq("inner_thing")
    end

    it "round-trips bare-keyword form byte-identically" do
      input = "template foo {\n\tcode [[\n\t\tbar = baz\n\t]]\n}\n"
      expect(parse(input).to_pdx).to eq(input)
    end

    it "round-trips assignment form byte-identically" do
      input = "block = {\n\tcode = [[\n\t\tinner = ok\n\t]]\n}\n"
      expect(parse(input).to_pdx).to eq(input)
    end

    it "parses nested lists inside the code block" do
      list = parse(<<~PDX).first
        template foo {
        \tcode [[
        \t\touter = {
        \t\t\tinner = 1
        \t\t}
        \t]]
        }
      PDX
      block = list.first
      expect(block).to be_a(Paradoxical::Elements::CodeBlock)
      outer = block.first
      expect(outer).to be_a(Paradoxical::Elements::List)
      expect(outer.key.to_s).to eq("outer")
      expect(outer.first.key.to_s).to eq("inner")
    end

    it "doesn't shadow identifiers that start with `code`" do
      # `coded`, `codename`, etc. should still parse as regular keys.
      prop = parse("coded = yes\n").first
      expect(prop).to be_a(Paradoxical::Elements::Property)
      expect(prop.key.to_s).to eq("coded")
    end
  end
end

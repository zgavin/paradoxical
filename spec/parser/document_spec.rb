require "paradoxical"

RSpec.describe Paradoxical::Parser do
  def parse(text)
    Paradoxical::Parser.parse(text)
  end

  describe "document" do
    it "parses an empty document" do
      doc = parse("")
      expect(doc).to be_a(Paradoxical::Elements::Document)
      expect(doc.size).to eq(0)
    end

    it "parses a document with only a comment" do
      doc = parse("# just a comment\n")
      expect(doc.size).to eq(1)
      expect(doc.first).to be_a(Paradoxical::Elements::Comment)
      expect(doc.first.text.to_s.strip).to eq("just a comment")
    end

    it "parses mixed top-level content" do
      doc = parse(<<~PDX)
        # leading comment
        foo = 1
        bar = { x = 2 }
        # trailing comment
      PDX

      expect(doc.size).to eq(4)
      expect(doc.comments.size).to eq(2)
      expect(doc.properties.size).to eq(1)
      expect(doc.lists.size).to eq(1)
    end

    it "exposes property lookup by key" do
      doc = parse("foo = 1\nbar = 2\n")
      expect(doc["foo"].value.to_s).to eq("1")
      expect(doc["bar"].value.to_s).to eq("2")
      expect(doc["missing"]).to be_nil
    end

    it "exposes value_for(key)" do
      doc = parse("foo = 42\n")
      expect(doc.value_for("foo").to_s).to eq("42")
    end

    it "exposes keys/keyable" do
      doc = parse("a = 1\nb = 2\nc = 3\n")
      expect(doc.keys.map(&:to_s)).to eq(%w[a b c])
    end
  end

  describe "comments" do
    it "captures the full comment text including leading space" do
      comment = parse("# hello world\n").first
      # parser stores text starting from the first char after `#`
      expect(comment.text.to_s).to eq(" hello world")
    end

    it "captures a comment with no text" do
      comment = parse("#\n").first
      expect(comment).to be_a(Paradoxical::Elements::Comment)
      expect(comment.text.to_s).to eq("")
    end
  end

  describe "round-trip preservation" do
    # Parse → re-serialize via to_pdx should produce byte-identical
    # output for any well-formed input. This is the core invariant the
    # whole framework rests on.
    [
      ["empty", ""],
      ["single property", "foo = 1"],
      ["trailing newline", "foo = 1\n"],
      ["multiple properties", "a = 1\nb = 2\nc = 3\n"],
      ["nested list", "outer = {\n\tinner = {\n\t\tx = 1\n\t}\n}\n"],
      ["mixed content", "# header\nfoo = 1\nbar = { x = 2 y = 3 }\n# footer\n"],
      ["quoted strings", %{name = "Holy Roman Empire"\n}],
      ["dates", "start_date = 1444.11.11\n"],
      ["various operators", "a = 1\nb >= 2\nc < 3\nd != 4\n"],
      ["irregular indentation", "  foo  =  1\n   bar    =    2\n"],
    ].each do |label, input|
      it "round-trips #{label}" do
        doc = parse(input)
        expect(doc.to_pdx).to eq(input)
      end
    end

    it "round-trips CRLF line endings when @line_break is set" do
      input = "foo = 1\r\nbar = 2\r\n"
      doc = parse(input)
      doc.instance_variable_set(:@line_break, "\r\n")
      expect(doc.to_pdx).to eq(input)
    end
  end
end

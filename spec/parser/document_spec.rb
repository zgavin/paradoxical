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

    it "parses bare identifiers at top level (Stellaris tag-list shape)" do
      # Stellaris common/component_tags/00_tags.txt and similar are
      # documents that hold an array of bare identifiers — no operator,
      # no enclosing braces. PDX games accept these as tag declarations.
      doc = parse("weapon_type_kinetic\nweapon_type_explosive\n")
      expect(doc.size).to eq(2)
      doc.each { |c| expect(c).to be_a(Paradoxical::Elements::Value) }
      expect(doc.values.map { |v| v.value.to_s }).to eq(%w[weapon_type_kinetic weapon_type_explosive])
    end

    it "parses top-level keyless lists" do
      # EU5 decal_definitions.txt and Stellaris gamesetup_settings.txt
      # ship a sequence of unkeyed `{ ... }` blocks at the top of the
      # file. Each becomes a keyless List child with no key.
      doc = parse("{\n\tname = first\n}\n{\n\tname = second\n}\n")
      expect(doc.size).to eq(2)
      doc.each do |child|
        expect(child).to be_a(Paradoxical::Elements::List)
        expect(child.key).to be(false)
      end
      expect(doc[0][0].value.to_s).to eq("first")
      expect(doc[1][0].value.to_s).to eq("second")
    end

    it "parses nested keyless lists" do
      # EU5/Imperator gene curve data: `curve = { { 0.0 { 0.0 -0.4 0.1 } } }`.
      # Outer is array_list; first child is a keyless_list whose body
      # holds a value followed by another keyless_list.
      doc = parse("curve = {\n\t{ 0.0 { 0.0 -0.4 0.1 } }\n}\n")
      curve = doc.first
      keyless = curve.first
      expect(keyless).to be_a(Paradoxical::Elements::List)
      expect(keyless.key).to be(false)
      inner = keyless[1]
      expect(inner).to be_a(Paradoxical::Elements::List)
      expect(inner.key).to be(false)
      expect(inner.values.map { |v| v.value.to_s }).to eq(%w[0.0 -0.4 0.1])
    end

    it "parses bare identifiers mixed with properties at top level" do
      input = "foo = 1\nbare_value\nbar = 2\n"
      doc = parse(input)
      expect(doc.size).to eq(3)
      expect(doc[0]).to be_a(Paradoxical::Elements::Property)
      expect(doc[1]).to be_a(Paradoxical::Elements::Value)
      expect(doc[2]).to be_a(Paradoxical::Elements::Property)
      expect(doc.to_pdx).to eq(input)
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

    it "absorbs mid-head comments into surrounding whitespace" do
      # HOI4's `SOV_names_divisions.txt` has lines like
      # `SOV_CAV_02 = #COSSACK CAVALRY\n{` — a comment between an
      # operator and the opening `{`. EU5's `gui_base.gui` has the
      # similar `block "Foo" #note\n{` shape. PDX engine accepts
      # either; our `ws` absorbs the comment into the surrounding
      # whitespace token so round-trip preserves the bytes.
      input = "key = #note\n{\n\tx = 1\n}\n"
      doc = parse(input)
      expect(doc.first).to be_a(Paradoxical::Elements::List)
      expect(doc.first.key.to_s).to eq("key")
      expect(parse(input).to_pdx).to eq(input)
    end

    it "accepts C-style `//` comments and preserves the marker" do
      # PDX accepts both `#` (native) and `//` (a C-style holdover in
      # some EU5 defines files). The marker is captured per-comment so
      # round-trip preserves whichever form the source used.
      input = "# hash\n// slashes\nfoo = 1\n"
      doc = parse(input)
      expect(doc[0]).to be_a(Paradoxical::Elements::Comment)
      expect(doc[0].marker).to eq("#")
      expect(doc[1]).to be_a(Paradoxical::Elements::Comment)
      expect(doc[1].marker).to eq("//")
      expect(doc.to_pdx).to eq(input)
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
      ["top-level keyless list", "{\n\tname = first\n}\n"],
      ["nested keyless list", "curve = {\n\t{ 0.0 { 0.0 -0.4 0.1 } }\n}\n"],
      ["bare-keyword list", "position { x = 0 y = 0 }\n"],
      ["trailing semicolon after property", %{a = "foo";\nb = 2\n}],
      ["trailing semicolon after list value", "color = { 0.0 0.0 0.0 };\nwidth = 0.15\n"],
      ["trailing semicolon at EOF", "a = 1;"],
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

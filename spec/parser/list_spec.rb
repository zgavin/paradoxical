require "paradoxical"

RSpec.describe Paradoxical::Parser do
  def parse(text)
    Paradoxical::Parser.parse(text)
  end

  describe "lists" do
    it "parses an empty list" do
      list = parse("foo = {}\n").first
      expect(list).to be_a(Paradoxical::Elements::List)
      expect(list.key.to_s).to eq("foo")
      expect(list.operator).to eq("=")
      expect(list.kind).to be_nil
      expect(list.gui_type?).to be(false)
      expect(list.size).to eq(0)
    end

    it "parses a list with a single property child" do
      list = parse("foo = { bar = 1 }\n").first
      expect(list.size).to eq(1)
      expect(list.first).to be_a(Paradoxical::Elements::Property)
      expect(list.first.key.to_s).to eq("bar")
      expect(list.first.value.to_s).to eq("1")
    end

    it "parses a list with multiple property children" do
      list = parse("foo = { a = 1 b = 2 c = 3 }\n").first
      expect(list.size).to eq(3)
      expect(list.properties.map { |p| p.key.to_s }).to eq(%w[a b c])
      expect(list.properties.map { |p| p.value.to_s }).to eq(%w[1 2 3])
    end

    it "parses a nested list" do
      doc = parse("outer = { inner = { x = 1 } }\n")
      outer = doc.first
      expect(outer.size).to eq(1)
      inner = outer.first
      expect(inner).to be_a(Paradoxical::Elements::List)
      expect(inner.key.to_s).to eq("inner")
      expect(inner.first.key.to_s).to eq("x")
    end

    it "parses an array list (values only)" do
      list = parse("nums = { 1 2 3 }\n").first
      expect(list.size).to eq(3)
      list.each { |v| expect(v).to be_a(Paradoxical::Elements::Value) }
      expect(list.values.map { |v| v.value.to_s }).to eq(%w[1 2 3])
    end

    it "parses a mixed list (properties and values)" do
      list = parse("mix = { foo = bar 42 baz = qux }\n").first
      expect(list.size).to eq(3)
      expect(list[0]).to be_a(Paradoxical::Elements::Property)
      expect(list[0].key.to_s).to eq("foo")
      expect(list[1]).to be_a(Paradoxical::Elements::Value)
      expect(list[1].value.to_s).to eq("42")
      expect(list[2]).to be_a(Paradoxical::Elements::Property)
      expect(list[2].key.to_s).to eq("baz")
    end

    it "parses keyless lists with property children" do
      # Keyless lists (no key/operator before `{`) are only legal as
      # children of array_list, which accepts values, comments, and
      # other keyless_lists.
      list = parse("points = { { x = 1 y = 2 } { x = 3 y = 4 } }\n").first
      expect(list.size).to eq(2)
      list.each do |child|
        expect(child).to be_a(Paradoxical::Elements::List)
        expect(child.key).to be(false)
        expect(child.size).to eq(2)
        expect(child.properties.map { |p| p.key.to_s }).to eq(%w[x y])
      end
    end

    it "parses keyless lists with bare value children" do
      # Pattern used by PDX games for coordinate pairs in city_data
      # files and similar tabular data.
      list = parse("points = { { 1 2 } { 3 4 } }\n").first
      expect(list.size).to eq(2)
      list.each do |child|
        expect(child).to be_a(Paradoxical::Elements::List)
        expect(child.key).to be(false)
        expect(child.size).to eq(2)
        child.each { |v| expect(v).to be_a(Paradoxical::Elements::Value) }
      end
      expect(list[0].values.map { |v| v.value.to_s }).to eq(%w[1 2])
      expect(list[1].values.map { |v| v.value.to_s }).to eq(%w[3 4])
    end

    describe "gui_kind variants" do
      %w[types template blockoverride block layer].each do |kind|
        it "parses `#{kind}` form" do
          list = parse("#{kind} foo {}\n").first
          expect(list).to be_a(Paradoxical::Elements::List)
          expect(list.kind).to eq(kind)
          expect(list.key.to_s).to eq("foo")
          expect(list.operator).to be_nil
          expect(list.gui_type?).to be(false)
        end
      end

      it "accepts capitalized gui_kind keywords (PDX is case-insensitive)" do
        # EU5 ships gui files using `Types HUD_TopbarTypes { ... }` with
        # a capital T. PDX accepts this; we should too. Round-trip
        # preserves the original casing.
        input = "Types HUD_TopbarTypes\n{\n\tx = 1\n}\n"
        list = parse(input).first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.kind).to eq("Types")
        expect(list.key.to_s).to eq("HUD_TopbarTypes")
        expect(parse(input).to_pdx).to eq(input)
      end
    end

    describe "gui_type variant" do
      it "parses `type foo = bar { ... }`" do
        list = parse("type foo = bar { x = 1 }\n").first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.gui_type?).to be(true)
        expect(list.key.to_s).to eq("foo")
        expect(list.operator).to eq("=")
        expect(list.kind).to eq("bar")
        expect(list.size).to eq(1)
      end
    end

    describe "load_template variant" do
      it "parses `load_template foo { ... }`" do
        # EU5 city_data files use load_template as a top-level
        # directive that mirrors gui_kind / scripted_kind in shape:
        # keyword, name, body. No operator.
        list = parse("load_template player_buildings { x = 1 y = 2 }").first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.kind).to eq("load_template")
        expect(list.key.to_s).to eq("player_buildings")
        expect(list.operator).to be_nil
        expect(list.gui_type?).to be(false)
      end

      it "doesn't shadow identifiers that start with load_template_" do
        # The &whitespace_character lookahead on load_template_kind
        # ensures `load_template_foo` is treated as a regular
        # identifier, not as a load_template directive.
        prop = parse("load_template_foo = bar").first
        expect(prop).to be_a(Paradoxical::Elements::Property)
        expect(prop.key.to_s).to eq("load_template_foo")
      end
    end

    describe "local_template variant" do
      it "parses `local_template foo { ... }`" do
        # Imperator gui files (greatworkwindow.gui, reorg_window.gui)
        # use local_template — same shape as load_template, different
        # keyword. PDX games support both.
        list = parse("local_template great_work_view {\n\tlayoutpolicy_horizontal = expanding\n}\n").first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.kind).to eq("local_template")
        expect(list.key.to_s).to eq("great_work_view")
        expect(list.operator).to be_nil
      end

      it "doesn't shadow identifiers that start with local_template_" do
        prop = parse("local_template_foo = bar").first
        expect(prop).to be_a(Paradoxical::Elements::Property)
        expect(prop.key.to_s).to eq("local_template_foo")
      end
    end

    describe "list_kind (LIST keyword)" do
      it "parses `key = LIST { values }`" do
        # Imperator climate files use `key = LIST { ... }` to declare an
        # array-of-values list. The LIST token sits between the operator
        # and the opening brace.
        list = parse("mild_winter = LIST { 3700 3701 3056 }\n").first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.kind).to eq("LIST")
        expect(list.key.to_s).to eq("mild_winter")
        expect(list.operator).to eq("=")
        expect(list.gui_type?).to be(false)
        expect(list.size).to eq(3)
        list.each { |v| expect(v).to be_a(Paradoxical::Elements::Value) }
        expect(list.values.map { |v| v.value.to_s }).to eq(%w[3700 3701 3056])
      end

      it "doesn't shadow identifiers that start with LIST" do
        # The &whitespace_character lookahead on list_kind ensures
        # `LISTED` (or any token that starts with LIST and continues)
        # is treated as a regular identifier.
        prop = parse("LISTED = foo\n").first
        expect(prop).to be_a(Paradoxical::Elements::Property)
        expect(prop.key.to_s).to eq("LISTED")
      end
    end

    describe "scripted_kind variants" do
      %w[scripted_trigger scripted_effect].each do |kind|
        it "parses `#{kind} foo = { ... }`" do
          list = parse("#{kind} foo = { a = 1 }\n").first
          expect(list).to be_a(Paradoxical::Elements::List)
          expect(list.kind).to eq(kind)
          expect(list.key.to_s).to eq("foo")
          expect(list.operator).to eq("=")
          expect(list.gui_type?).to be(false)
        end
      end
    end
  end
end

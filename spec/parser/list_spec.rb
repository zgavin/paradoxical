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

      it "doesn't shadow identifiers that start with a gui_kind keyword" do
        # Without the &whitespace_character lookahead in `prefixed_kind`,
        # `template_foo { x = 1 }` would silently misparse as
        # kind=`template` + key=`_foo`. The lookahead forces it to fall
        # through to bare_head where the whole `template_foo` is the key.
        list = parse("template_foo { x = 1 }").first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.kind).to be_nil
        expect(list.key.to_s).to eq("template_foo")
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
        # `load_template` carries a &whitespace_character lookahead in
        # `prefixed_kind` so `load_template_foo` parses as a regular
        # identifier rather than `load_template` + `_foo`.
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

    describe "bare-keyword variant" do
      it "parses `name { ... }` with no operator" do
        # Pattern used by gui files (`position { x = 0 y = 0 }`),
        # gfx files (`spriteType { ... }`), and defines
        # (`NAdvanceTreeSettings\n{ ... }`). Stored as a regular
        # keyed list with no operator and no kind.
        list = parse("position { x = 0 y = 0 }\n").first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.key.to_s).to eq("position")
        expect(list.operator).to be_nil
        expect(list.kind).to be_nil
        expect(list.gui_type?).to be(false)
        expect(list.size).to eq(2)
      end

      it "round-trips byte-identically with key on a separate line" do
        input = "NAdvanceTreeSettings\n{\n\tx = 1\n}\n"
        expect(parse(input).to_pdx).to eq(input)
      end

      it "still parses `key = { ... }` as a keyed list" do
        # Operator-form alt is tried first; the bare-keyword alt only
        # kicks in after that fails. Confirm `=` doesn't accidentally
        # get absorbed.
        list = parse("foo = { x = 1 }\n").first
        expect(list.operator).to eq("=")
      end

      it "doesn't match a numeric primitive as a bare-keyword key" do
        # Inside a keyless_list (array_list child), `0.0 { ... }` is a
        # value followed by a sub-block — frame index + frame data, in
        # the EU5 gene curves case. Without the negative lookahead on
        # bare_head, it would greedily match as bare_head{key=0.0,
        # body=[values]} and lose the pair semantics.
        doc = Paradoxical::Parser.parse("curve = {\n\t{ 0.0 { 1 2 3 } }\n}\n")
        outer_keyless = doc.first.first
        expect(outer_keyless.size).to eq(2)
        expect(outer_keyless[0]).to be_a(Paradoxical::Elements::Value)
        expect(outer_keyless[0].value.to_s).to eq("0.0")
        expect(outer_keyless[1]).to be_a(Paradoxical::Elements::List)
        expect(outer_keyless[1].key).to be(false)
      end
    end

    describe "keyed_kind variant (`key = kind { body }`)" do
      it "parses the typed-list-without-`type` shape" do
        # EU5 city_data: `load_template = player_buildings { ... }`.
        # Distinct from gui_type form (no `type` keyword) and from a
        # property with a list RHS (the body is the list, not the value).
        list = parse("load_template = player_buildings {\n\tx = 1\n}\n").first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.key.to_s).to eq("load_template")
        expect(list.operator).to eq("=")
        expect(list.kind).to eq("player_buildings")
        expect(list.gui_type?).to be(false)
        expect(list.size).to eq(1)
      end

      it "round-trips byte-identically" do
        # Kind sits after the operator, so to_pdx must put it there
        # too. The kind_after_key flag set during parse drives this.
        input = "exact = not {\n\tsetting_value = { value = \"1920x1080\" }\n}\n"
        expect(parse(input).to_pdx).to eq(input)
      end

      it "doesn't shadow `key = color { ... }` shapes" do
        # True color keywords (rgb/hsv/hsv360/hex) on the RHS of `=`
        # should still parse as a color-typed property value, not as
        # a keyed_kind list with kind=`rgb` etc.
        prop = parse("foo = rgb { 128 64 32 }\n").first
        expect(prop).to be_a(Paradoxical::Elements::Property)
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color)
      end

      it "parses `cylindrical { ... }` as a list, not a color" do
        # cylindrical is a camera/coordinate construct, not a color.
        # Components are `radius height angle` (any may be negative),
        # and EU5 portrait_environments uses @-variables for them
        # which color components don't accept. Letting this fall to
        # the unified `list` rule keeps the AST honest — kind is the
        # construct name, body is the components as values.
        list = parse("position = cylindrical { 260 30 -10 }\n").first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.key.to_s).to eq("position")
        expect(list.kind).to eq("cylindrical")
        expect(list.values.map { |v| v.value.to_s }).to eq(%w[260 30 -10])
      end
    end

    describe "values inside gui_kind list bodies" do
      it "accepts bare values like `text \"\"` inside a keyable_list body" do
        # Imperator gui/diplomatic_view.gui has
        # `blockoverride "Text" { text "" }` — two adjacent values
        # inside a keyable_list (gui_kind) body. Before keyable_list's
        # body was widened to ( expression | value )*, this failed.
        list = parse("blockoverride \"Text\" {\n\ttext \"\"\n}\n").first
        expect(list).to be_a(Paradoxical::Elements::List)
        expect(list.kind).to eq("blockoverride")
        expect(list.size).to eq(2)
        expect(list[0]).to be_a(Paradoxical::Elements::Value)
        expect(list[0].value.to_s).to eq("text")
        expect(list[1]).to be_a(Paradoxical::Elements::Value)
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

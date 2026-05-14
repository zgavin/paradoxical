require "paradoxical"

RSpec.describe Paradoxical::Parser do
  def parse(text)
    Paradoxical::Parser.parse(text)
  end

  describe "primitives" do
    describe "integer" do
      it "parses a positive integer" do
        prop = parse("foo = 42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(42)
      end

      it "parses a negative integer" do
        prop = parse("foo = -42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(-42)
      end

      it "parses a positive-prefixed integer" do
        prop = parse("foo = +42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(42)
      end

      it "parses zero" do
        prop = parse("foo = 0").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(0)
      end
    end

    describe "float" do
      it "parses a positive float" do
        prop = parse("foo = 3.14").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(3.14)
      end

      it "parses a negative float" do
        prop = parse("foo = -3.14").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(-3.14)
      end

      it "parses a leading-dot float" do
        prop = parse("foo = .5").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(0.5)
      end

      it "parses a trailing-dot float" do
        prop = parse("foo = 5.").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(5.0)
      end

      it "accepts a C-style `f` suffix (EU4 gfx files)" do
        # EU4 combat_result_environment.txt: `{ 0.0f -5.5f 0.0f }`.
        prop = parse("foo = -5.5f\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(-5.5)
        expect(prop.value.to_pdx).to eq("-5.5f")
      end

      it "doesn't greedily consume `f` when followed by more identifier" do
        # `0.5fix` should parse as a string (identifier), not float `0.5f`
        # plus stranded `ix`. The trailing &break_character protects this.
        prop = parse("foo = 0.5fix\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("0.5fix")
      end
    end

    describe "boolean" do
      it "parses yes as true" do
        prop = parse("foo = yes").first
        expect(prop.value).to be(true)
      end

      it "parses no as false" do
        prop = parse("foo = no").first
        expect(prop.value).to be(false)
      end
    end

    describe "date" do
      it "parses a four-digit-year date" do
        prop = parse("foo = 1444.11.11").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Date)
        expect(prop.value.year).to eq(1444)
        expect(prop.value.month).to eq(11)
        expect(prop.value.day).to eq(11)
      end

      it "parses a single-digit-year date" do
        prop = parse("foo = 9.1.1").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Date)
        expect(prop.value.year).to eq(9)
        expect(prop.value.month).to eq(1)
        expect(prop.value.day).to eq(1)
      end

      it "parses a BC (negative-year) date" do
        # EU4's great_projects use BC dates for ancient pyramids etc.;
        # Imperator: Rome uses them throughout. The grammar's date rule
        # accepts an optional leading `-` sign.
        prop = parse("date = -2500.01.01").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Date)
        expect(prop.value.year).to eq(-2500)
      end

      it "carries the default calendar (Calendar365) and round-trips bytes" do
        prop = parse("foo = 1444.11.11").first
        expect(prop.value.calendar).to eq(Paradoxical::Calendars::Calendar365)
        expect(prop.value.to_pdx).to eq("1444.11.11")
      end

      it "permissively accepts sentinel dates (e.g. 0000.00.00) without raising" do
        # Real game data ships `0000.00.00` and `1.0.1` as engine-
        # accepted sentinels. We round-trip them faithfully — calendar
        # validity is for arithmetic, not construction.
        expect { parse("foo = 0000.00.00") }.not_to raise_error
        expect { parse("foo = 1.0.1") }.not_to raise_error
      end

      describe "arithmetic" do
        let(:date) { parse("foo = 1444.11.11").first.value }

        it "+ Integer adds days (Calendar365: no leap year)" do
          # 1444.11.11 + 20 days -> 1444.12.1
          result = date + 20
          expect(result.year).to eq(1444)
          expect(result.month).to eq(12)
          expect(result.day).to eq(1)
        end

        it "- Integer subtracts days" do
          result = date - 10
          expect(result.year).to eq(1444)
          expect(result.month).to eq(11)
          expect(result.day).to eq(1)
        end

        it "Date - Date returns day count" do
          earlier = parse("a = 1444.11.01").first.value
          expect(date - earlier).to eq(10)
        end

        it "applies ActiveSupport::Duration with month-shift + day-clamp" do
          # 1444.1.31 + 1.month -> 1444.2.28 (clamp to Feb's 28 days)
          jan31 = parse("d = 1444.1.31").first.value
          result = jan31 + 1.month
          expect(result.month).to eq(2)
          expect(result.day).to eq(28)
        end

        it "comparisons via <=> (Comparable)" do
          earlier = parse("a = 1444.01.01").first.value
          later   = parse("a = 1500.01.01").first.value
          expect(earlier).to be < date
          expect(date).to be < later
        end

        it "Stellaris (Calendar360) supports Feb 30" do
          prev = Paradoxical::Elements::Primitives::Date.default_calendar
          begin
            Paradoxical::Elements::Primitives::Date.default_calendar = Paradoxical::Calendars::Calendar360
            d = Paradoxical::Elements::Primitives::Date.new("2200.2.30")
            # 2200.2.30 + 1.day -> 2200.3.1 in Calendar360
            result = d + 1
            expect(result.month).to eq(3)
            expect(result.day).to eq(1)
          ensure
            Paradoxical::Elements::Primitives::Date.default_calendar = prev
          end
        end
      end

      it "BC date doesn't shadow negative integer parsing" do
        prop = parse("x = -42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(-42)
      end

      it "BC date doesn't shadow negative float parsing" do
        prop = parse("x = -3.14").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(-3.14)
      end
    end

    describe "placeholder (---)" do
      # PDX history files use literal `---` as a "no value" sentinel
      # (e.g. `emperor = ---` for "no emperor"). Currently stored as a
      # raw String primitive; phase 8 may give it a typed Null shape
      # but for now the simple fix preserves round-trip without
      # introducing new semantics.

      it "parses --- as a String primitive" do
        prop = parse("emperor = ---").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("---")
      end

      it "parses --- inside a list" do
        list = parse("1806.7.12 = { emperor = --- }").first
        inner = list.first
        expect(inner.value.to_s).to eq("---")
      end

      it "doesn't shadow negative integer parsing" do
        prop = parse("x = -42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        expect(prop.value.to_i).to eq(-42)
      end

      it "doesn't shadow negative float parsing" do
        prop = parse("x = -3.14").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
        expect(prop.value.to_f).to eq(-3.14)
      end
    end

    describe "percentage" do
      it "parses a percentage as a String primitive" do
        prop = parse("foo = 50%").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("50%")
      end

      it "parses a negative percentage" do
        prop = parse("foo = -50%").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("-50%")
      end
    end

    describe "color" do
      it "parses an rgb color" do
        prop = parse("foo = rgb { 128 64 32 }").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color::RGB)
        expect(prop.value).to be_rgb
        expect(prop.value.r.to_i).to eq(128)
        expect(prop.value.g.to_i).to eq(64)
        expect(prop.value.b.to_i).to eq(32)
        expect(prop.value.alpha).to be_nil
      end

      it "stores typed integer components for rgb integer values" do
        prop = parse("foo = rgb { 128 64 32 }").first
        expect(prop.value.components.map(&:class)).to all(eq(Paradoxical::Elements::Primitives::Integer))
      end

      it "parses an hsv color" do
        prop = parse("foo = hsv { 0.5 0.7 0.9 }").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color::HSV)
        expect(prop.value).to be_hsv
        expect(prop.value.h.to_f).to eq(0.5)
        expect(prop.value.s.to_f).to eq(0.7)
        expect(prop.value.v.to_f).to eq(0.9)
      end

      it "stores typed float components for hsv float values" do
        prop = parse("foo = hsv { 0.5 0.7 0.9 }").first
        expect(prop.value.components.map(&:class)).to all(eq(Paradoxical::Elements::Primitives::Float))
      end

      it "parses a 4-component (alpha) rgb color and exposes #alpha" do
        # EU5 / Stellaris use `rgb { r g b a }` in some color values.
        prop = parse("foo = rgb { 235 0 18 0 }").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color::RGB)
        expect(prop.value.r.to_i).to eq(235)
        expect(prop.value.alpha.to_i).to eq(0)
      end

      it "parses a 4-component (alpha) hsv color" do
        prop = parse("foo = hsv { 0.3 0.6 0.9 1.0 }").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color::HSV)
        expect(prop.value.alpha.to_f).to eq(1.0)
      end

      it "preserves alpha through 4-component rgb → hsv conversion" do
        prop = parse("foo = rgb { 255 0 0 128 }").first
        hsv = prop.value.to_hsv
        expect(hsv).to be_a(Paradoxical::Elements::Primitives::Color::HSV)
        # Pure red: h=0, s=1, v=1
        expect(hsv.h.to_f).to be_within(0.001).of(0.0)
        expect(hsv.s.to_f).to be_within(0.001).of(1.0)
        expect(hsv.v.to_f).to be_within(0.001).of(1.0)
        # Alpha 128/255 ≈ 0.502
        expect(hsv.alpha.to_f).to be_within(0.001).of(128.0 / 255.0)
      end

      it "justify! works on 4-component rgb" do
        prop = parse("foo = rgb { 235 0 18 0 }").first
        prop.value.justify!
        # Each component padded to 4 wide; same shape the 3-component
        # justify! already produces ("rgb { ... }" with space-after-type
        # and space-before-`}` from the to_pdx default).
        expect(prop.value.to_pdx).to eq("rgb { 235   0  18   0 }")
      end

      it "parses an hsv360 color" do
        # EU5 introduced hsv360 — hue in degrees (0..360), S/V as
        # integers (0..100), instead of hsv's 0..1 floats.
        prop = parse("foo = hsv360 { 49 35 71 }").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color::HSV360)
        expect(prop.value).to be_hsv360
        expect(prop.value).not_to be_hsv
        expect(prop.value).not_to be_rgb
        expect(prop.value.h.to_i).to eq(49)
      end

      it "does not match a 4-component hsv360 source as a color" do
        # No empirical examples in any installed PDX game ship hsv360
        # alpha, and the grammar is strict per the parser-strictness
        # principle. With color out of the running, primitive falls
        # through to string and `{ … }` parses as a keyless list — so
        # the parse succeeds in a different shape rather than producing
        # an hsv360 Color with four components.
        doc = parse("foo = hsv360 { 49 35 71 100 }")
        prop = doc.first
        expect(prop).to be_a(Paradoxical::Elements::Property)
        expect(prop.value).not_to be_a(Paradoxical::Elements::Primitives::Color)
      end

      it "converts hsv360 to hsv (h/360, s/100, v/100)" do
        prop = parse("foo = hsv360 { 180 50 100 }").first
        hsv = prop.value.to_hsv
        expect(hsv).to be_a(Paradoxical::Elements::Primitives::Color::HSV)
        expect(hsv.h.to_f).to be_within(0.001).of(0.5)
        expect(hsv.s.to_f).to be_within(0.001).of(0.5)
        expect(hsv.v.to_f).to be_within(0.001).of(1.0)
      end

      it "converts hsv360 to rgb via hsv (HDR extension preserved)" do
        # 245 → 0.68 h, 40 → 0.4 s, 150 → 1.5 v (HDR-extended brightness)
        prop = parse("foo = hsv360 { 245 40 150 }").first
        rgb = prop.value.to_rgb
        expect(rgb).to be_a(Paradoxical::Elements::Primitives::Color::RGB)
        # HDR — any normalized channel > 1 should produce Float RGB
        expect(rgb.components.first).to be_a(Paradoxical::Elements::Primitives::Float)
      end

      it "parses a hex literal color" do
        # EU5 unit_graphics/colors use hex{ 0xRRGGBBAA } as a single-
        # component literal — different body shape than the multi-
        # component types.
        prop = parse("color_leather_whitened = hex{ 0xffffffff }").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color::Hex)
        expect(prop.value).to be_hex
        expect(prop.value.literal).to eq("0xffffffff")
      end

      it "exposes per-channel #r/#g/#b/#alpha accessors on hex (4-channel literal)" do
        hex = parse("c = hex{ 0xab12cd34 }").first.value
        expect(hex.r).to eq("ab")
        expect(hex.g).to eq("12")
        expect(hex.b).to eq("cd")
        expect(hex.alpha).to eq("34")
        expect(hex.components).to eq(%w[ab 12 cd 34])
      end

      it "returns nil for #alpha on a 6-char hex literal (no alpha channel)" do
        hex = parse("c = hex{ 0xab12cd }").first.value
        expect(hex.r).to eq("ab")
        expect(hex.alpha).to be_nil
        expect(hex.components).to eq(%w[ab 12 cd])
      end

      it "allows per-channel setters that mutate the underlying literal" do
        hex = parse("c = hex{ 0xffffffff }").first.value
        hex.r = "00"
        hex.alpha = "80"
        expect(hex.literal).to eq("0x00ffff80")
      end

      it "rejects non-hex-pair component setters" do
        hex = parse("c = hex{ 0xffffffff }").first.value
        expect { hex.r = "zz" }.to raise_error(ArgumentError, /2 hex chars/)
        expect { hex.r = "f" }.to raise_error(ArgumentError, /2 hex chars/)
      end

      it "rejects #alpha= on a 6-char hex (no auto-grow)" do
        hex = parse("c = hex{ 0xab12cd }").first.value
        expect { hex.alpha = "ff" }.to raise_error(ArgumentError, /too short/)
      end

      it "converts hex to rgb (each 2-char pair to int channel)" do
        hex = parse("x = hex{ 0xff80c000 }").first.value
        rgb = hex.to_rgb
        expect(rgb).to be_a(Paradoxical::Elements::Primitives::Color::RGB)
        expect(rgb.r.to_i).to eq(0xff)
        expect(rgb.g.to_i).to eq(0x80)
        expect(rgb.b.to_i).to eq(0xc0)
        expect(rgb.alpha.to_i).to eq(0x00)
      end

      it "round-trips rgb -> hex -> rgb byte-equivalently" do
        rgb = parse("c = rgb { 235 0 18 }").first.value
        hex = rgb.to_hex
        expect(hex.literal).to eq("0xeb0012")
        back = hex.to_rgb
        expect(back.components.map(&:to_i)).to eq([0xeb, 0x00, 0x12])
      end

      it "justify! works on hex (canonicalizes whitespace)" do
        hex = parse("c = hex{ 0xab12cd34 }").first.value
        hex.justify!
        expect(hex.to_pdx).to eq("hex { 0xab12cd34 }")
      end

      it "applies per-component rule to mixed-with-bare-0 float rgb" do
        # EU5 ships `rgb { 0.502 0 0.612 }` — bare `0` is polymorphic
        # (Integer 0 reads as fraction endpoint in float context).
        prop = parse("c = rgb { 0.502 0 0.612 }").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Color::RGB)
        hsv = prop.value.to_hsv
        expect(hsv.v.to_f).to be_within(0.001).of(0.612)
      end

      it "applies per-component rule to hsv mixed percentage + fraction" do
        # `hsv { 0 100 0.8 }`: Integer 100 -> /100 = 1.0; Float 0.8 stays
        prop = parse("c = hsv { 0 100 0.8 }").first
        rgb = prop.value.to_rgb
        # s=1, v=0.8 — saturated, mid-bright. r should equal v*255.
        # h=0 -> pure red hue, so r=204 (0.8*255), g=0, b=0
        expect(rgb.r.to_i).to eq(204)
        expect(rgb.g.to_i).to eq(0)
        expect(rgb.b.to_i).to eq(0)
      end

      it "preserves HDR through hsv (v > 1) → rgb conversion" do
        # `hsv { 0.5 0.1 4.5 }` — HDR-extended v=4.5 (lighting brightness)
        prop = parse("c = hsv { 0.5 0.1 4.5 }").first
        rgb = prop.value.to_rgb
        # Any channel > 1 → output Float RGB to preserve HDR
        expect(rgb.components.first).to be_a(Paradoxical::Elements::Primitives::Float)
      end

      it "validates rgb homogeneity (Integer 0/1 ok, real Integer mixed with Float rejected)" do
        # Bare 0/1 with floats is valid (already exercised above).
        # Real Integer >= 2 with Float should raise at construction.
        rgb = Paradoxical::Elements::Primitives::Color::RGB
        i = ->(v) { Paradoxical::Elements::Primitives::Integer.new(v.to_s) }
        f = ->(v) { Paradoxical::Elements::Primitives::Float.new(v.to_s) }

        mixed = [f.call("0.5"), i.call(128), f.call("0.5")]
        expect { rgb.new(mixed) }.to raise_error(ArgumentError, /Integer >= 2 mixed with Float/)
        expect { rgb.new([f.call("0.5"), i.call(0), f.call("0.5")]) }.not_to raise_error
        expect { rgb.new([f.call("0.5"), i.call(1), f.call("0.5")]) }.not_to raise_error
      end

      it "validates hsv360 all-int (rejects float components)" do
        hsv360 = Paradoxical::Elements::Primitives::Color::HSV360
        i = ->(v) { Paradoxical::Elements::Primitives::Integer.new(v.to_s) }
        f = ->(v) { Paradoxical::Elements::Primitives::Float.new(v.to_s) }

        expect { hsv360.new([i.call(180), i.call(50), i.call(100)]) }.not_to raise_error
        mixed = [i.call(180), f.call("0.5"), i.call(100)]
        expect { hsv360.new(mixed) }.to raise_error(ArgumentError, /must all be Integer/)
      end

      it "round-trips byte-identically across all subtypes" do
        # The whitespace-capture path is the round-trip guarantee for
        # de-atomized colors; assert across each subtype.
        ["rgb { 128 64 32 }", "rgb { 235 0 18 0 }", "hsv { 0.5 0.7 0.9 }",
         "hsv { 0.3 0.6 0.9 1.0 }", "hsv360 { 49 35 71 }",
         "hex{ 0xffffffff }"].each do |body|
          input = "foo = #{body}\n"
          expect(parse(input).to_pdx).to eq(input), "round-trip differed for #{body.inspect}"
        end
      end
    end

    describe "string" do
      it "parses an unquoted string" do
        prop = parse("foo = bar").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value).not_to be_quoted
        expect(prop.value.to_s).to eq("bar")
      end

      it "parses a parameter splice mixed with literal text" do
        # Stellaris inline_scripts: `food = @$SIZE$_t$TIER$_upkeep_energy`.
        # `@$` is a distinct prefix in unquoted_string covering the
        # `@` + parameter-substitution form.
        prop = parse("food = @$SIZE$_t$TIER$_upkeep_energy\n").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("@$SIZE$_t$TIER$_upkeep_energy")
      end

      it "parses an `@@` indirect-variable reference" do
        # EU5 city_data templates: `@@rgo_contributor = @scale`. `@@`
        # resolves the @-variable's value as the name of another
        # @-variable. unquoted_string treats `@@` as a distinct sigil
        # alongside `@` and `@$`.
        prop = parse("@@rgo_contributor = @scale\n").first
        expect(prop).to be_a(Paradoxical::Elements::Property)
        expect(prop.key.to_s).to eq("@@rgo_contributor")
        expect(prop.value.to_s).to eq("@scale")
      end

      it "parses apostrophe-leading identifiers (Arabic transliterations)" do
        # EU4 cultures: `male_names = { Muhammad 'Alî 'Abd Sa'd ... }`.
        # `'` as a leading sigil anchors names like `'Alî`; mid-name
        # `'` (e.g. `Sa'd`) is already accepted by the tail.
        list = parse("male_names = { Muhammad 'Alî Sa'd 'Abd }\n").first
        expect(list.values.map { |v| v.value.to_s }).to eq(["Muhammad", "'Alî", "Sa'd", "'Abd"])
      end

      it "rejects double-sigil starts like `$$` and `-$$`" do
        # The `@$` prefix is a deliberate special case for parameter
        # splices; other `$`-sigil combos shouldn't be valid. The
        # required LETTER/NUMBER after `$` and `-$` correctly rejects
        # these. (`_$foo` does parse — via the bare-`_+` branch — but
        # that's the placeholder-identifier case, intentionally
        # permissive.)
        expect { parse("foo = $$bar\n") }.to raise_error(Paradoxical::Parser::ParseError)
        expect { parse("foo = -$$bar\n") }.to raise_error(Paradoxical::Parser::ParseError)
      end

      it "parses a quoted string" do
        prop = parse(%(foo = "hello world")).first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value).to be_quoted
        expect(prop.value.to_s).to eq("hello world")
      end

      it "parses an empty quoted string" do
        prop = parse(%(foo = "")).first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value).to be_quoted
        expect(prop.value.to_s).to eq("")
      end

      it "accepts curly quotes (“foo”) as an alternate quoted-string form" do
        # PDS content turns up with curly quotes — usually because a
        # modder pasted text from a word processor — and the engine
        # accepts them. HOI4's `BUL_ship_names.txt` and `00_names.txt`
        # both ship lines like `“Shipka”` mixed with normal
        # `"Sofia"` entries. The AST stores curly-quoted bytes
        # verbatim (vs straight-quoted, which strips the quotes and
        # sets `quoted?` true) so round-trip preserves whichever the
        # source used.
        input = %(foo = “hello”)
        prop = parse(input).first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("“hello”")
        expect(parse(input).to_pdx).to eq(input)
      end

      it "parses a localization string" do
        prop = parse("foo = [ROOT.GetName]").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("[ROOT.GetName]")
      end

      it "parses a computation string" do
        prop = parse("foo = @[GetSize + 1]").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("@[GetSize + 1]")
      end

      it "parses an escaped-computation string" do
        prop = parse("foo = @\\[Total]").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("@\\[Total]")
      end

      it "parses an unquoted string starting with a non-ASCII letter" do
        # PDX games (notably EU4 country files) use accented Latin and
        # other Unicode letters as identifiers.
        prop = parse("name = Élou").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("Élou")
      end

      it "parses an unquoted string containing an apostrophe" do
        # PDX leader/ship name lists include Latin apostrophe-bearing
        # forms like `d'Ambleteuse` and `O'Brien`. The leading char is
        # a regular letter; the apostrophe and following characters are
        # accepted by the tail since `'` isn't a break character.
        prop = parse("leaders = { d'Ambleteuse }").first
        expect(prop.first).to be_a(Paradoxical::Elements::Value)
        expect(prop.first.value.to_s).to eq("d'Ambleteuse")
      end

      it "parses bare `_` as an unquoted string identifier" do
        # Stellaris uses single underscore as a placeholder/wildcard
        # key in interface fonts: `_ = { 255 0 255 }`.
        prop = parse("_ = magenta").first
        expect(prop.key.to_s).to eq("_")
      end

      it "parses `_`-prefixed unquoted strings (not bare)" do
        # `_foo` and `__bar` are common identifier shapes; the leading
        # `"_"+ ~ (LETTER|NUMBER)` alternative matches the underscore(s)
        # then the alphanumeric continuation.
        prop = parse("name = _foo").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("_foo")

        prop = parse("name = __bar").first
        expect(prop.value.to_s).to eq("__bar")
      end

      it "parses a negative-prefixed `-$NAME$` parameter-substitution string" do
        # Stellaris's inline_scripts use this to subtract a parameter
        # value, e.g. `job_artisan_add = -$AMOUNT$`. Adds `-$` as a
        # leading-prefix alternative in unquoted_string. The phase-8
        # typed Primitives::Parameter shape will replace this when the
        # broader string-types work lands.
        prop = parse("job_artisan_add = -$AMOUNT$").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("-$AMOUNT$")
      end

      it "doesn't shadow negative number parsing" do
        # Adding `-$` to unquoted_string's prefixes shouldn't disturb
        # the integer/float matches for negative numbers — `-` followed
        # by a digit still hits integer/float first since they come
        # earlier in the primitive alternation.
        prop = parse("x = -42").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Integer)
        prop = parse("x = -3.14").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::Float)
      end

      it "parses a `$NAME$` parameter-substitution string" do
        # `$NAME$` parameter substitution is supported across all PDX
        # games — it's the engine's parse-time placeholder syntax.
        # Matches via `"$" ~ (LETTER|NUMBER)` for the leading; the tail
        # accepts the closing `$` since `$` isn't a break character.
        # Stellaris is the only game that uses the negative-prefixed
        # `-$NAME$` form, which is still a separate issue tracked as B5.
        prop = parse("food = $AMOUNT$").first
        expect(prop.value).to be_a(Paradoxical::Elements::Primitives::String)
        expect(prop.value.to_s).to eq("$AMOUNT$")
      end
    end
  end

  describe "operators" do
    %w[= >= <= > < ?= !=].each do |op|
      it "parses the #{op.inspect} operator" do
        prop = parse("foo #{op} 5").first
        expect(prop.operator).to eq(op)
        expect(prop.value.to_i).to eq(5)
      end
    end
  end
end

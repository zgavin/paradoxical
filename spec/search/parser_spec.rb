require "paradoxical"

RSpec.describe Paradoxical::Search do
  def parse text
    Paradoxical::Search.parse(text)
  end

  describe ".parse" do
    describe "key" do
      it "parses a wildcard key" do
        rules = parse("*")
        expect(rules.size).to eq(1)
        expect(rules.first.key).to eq("*")
      end

      it "parses a bare identifier key" do
        rules = parse("foo")
        expect(rules.first.key).to eq("foo")
      end

      it "downcases the key" do
        rules = parse("FooBar")
        expect(rules.first.key).to eq("foobar")
      end

      it "parses a double-quoted key (allows spaces / arbitrary chars)" do
        rules = parse('"foo bar"')
        expect(rules.first.key).to eq("foo bar")
      end

      it "parses a single-quoted key" do
        rules = parse("'foo'")
        expect(rules.first.key).to eq("foo")
      end

      it "accepts the unquoted-string sigils @ . : _" do
        rules = parse("foo.bar:baz_qux@1")
        expect(rules.first.key).to eq("foo.bar:baz_qux@1")
      end
    end

    describe "combinator" do
      it "is nil when omitted (descendent walk)" do
        rules = parse("foo")
        expect(rules.first.combinator).to be_nil
      end

      it "parses > (children only)" do
        rules = parse("> foo")
        expect(rules.first.combinator).to eq(">")
      end

      it "parses ~ (siblings only)" do
        rules = parse("~ foo")
        expect(rules.first.combinator).to eq("~")
      end
    end

    describe "selectors" do
      it "compiles a %name into a name property_matcher" do
        rule = parse("foo%alice").first
        expect(rule.key).to eq("foo")
        m = rule.property_matchers.first
        expect(m.key).to eq("name")
        expect(m.operator).to eq("=")
        expect(m.value).to eq("alice")
      end

      it "compiles a bare %name into a name property_matcher" do
        rule = parse("%alice").first
        m = rule.property_matchers.first
        expect(m.key).to eq("name")
        expect(m.operator).to eq("=")
        expect(m.value).to eq("alice")
      end

      it "compiles an #id into an id property_matcher" do
        rule = parse("foo#42").first
        expect(rule.key).to eq("foo")
        m = rule.property_matchers.first
        expect(m.key).to eq("id")
        expect(m.operator).to eq("=")
        expect(m.value).to eq("42")
      end

      it "compiles a bare #id into an id property_matcher" do
        rule = parse("#42").first
        m = rule.property_matchers.first
        expect(m.key).to eq("id")
        expect(m.operator).to eq("=")
        expect(m.value).to eq("42")
      end

      it "accepts both selectors on one rule in any order" do
        rule = parse("%alice#7").first
        keys = rule.property_matchers.map(&:key)
        expect(keys).to contain_exactly("name", "id")
        rule = parse("#7%alice").first
        keys = rule.property_matchers.map(&:key)
        expect(keys).to contain_exactly("name", "id")
      end
    end

    describe "property matchers" do
      it "parses a bare key (no operator, no value)" do
        m = parse("[foo]").first.property_matchers.first
        expect(m.key).to eq("foo")
        expect(m.operator).to be_nil
        expect(m.value).to be_nil
      end

      %w[= >= > < <= ~= ^= $=].each do |op|
        it "parses operator #{op}" do
          m = parse("[foo #{op} 1]").first.property_matchers.first
          expect(m.operator).to eq(op)
        end
      end

      it "parses the case-insensitive sensitivity flag" do
        m = parse("[name = alice i]").first.property_matchers.first
        expect(m.case_sensitivity).to eq("i")
      end

      it "parses the case-sensitive sensitivity flag" do
        m = parse("[name = alice s]").first.property_matchers.first
        expect(m.case_sensitivity).to eq("s")
      end

      it "leaves case_sensitivity nil when omitted" do
        m = parse("[name = alice]").first.property_matchers.first
        expect(m.case_sensitivity).to be_nil
      end

      describe "value types" do
        it "parses a string value" do
          m = parse("[k = bar]").first.property_matchers.first
          expect(m.value).to eq("bar")
        end

        it "parses a positive integer value" do
          m = parse("[k = 42]").first.property_matchers.first
          expect(m.value).to eq(42)
          expect(m.value).to be_a(Integer)
        end

        it "parses a negative integer value" do
          m = parse("[k = -42]").first.property_matchers.first
          expect(m.value).to eq(-42)
        end

        it "parses a float value" do
          m = parse("[k = 3.14]").first.property_matchers.first
          expect(m.value).to eq(3.14)
          expect(m.value).to be_a(Float)
        end

        it "parses boolean yes/true as true" do
          expect(parse("[k = yes]").first.property_matchers.first.value).to eq(true)
          expect(parse("[k = true]").first.property_matchers.first.value).to eq(true)
        end

        it "parses boolean no/false as false" do
          expect(parse("[k = no]").first.property_matchers.first.value).to eq(false)
          expect(parse("[k = false]").first.property_matchers.first.value).to eq(false)
        end

        it "parses a double-quoted string with escapes" do
          m = parse('[k = "ab\"cd"]').first.property_matchers.first
          expect(m.value).to eq('ab"cd')
        end

        it "parses a single-quoted string with escapes" do
          m = parse("[k = 'ab\\'cd']").first.property_matchers.first
          expect(m.value).to eq("ab'cd")
        end
      end
    end

    describe "function matchers" do
      it "parses a function with no arguments" do
        f = parse("&list").first.function_matchers.first
        expect(f.name).to eq("list")
        expect(f.arguments).to eq([])
      end

      it "parses a function with one argument" do
        f = parse("&value(42)").first.function_matchers.first
        expect(f.name).to eq("value")
        expect(f.arguments).to eq([42])
      end

      it "parses a function with multiple arguments of mixed types" do
        f = parse("&foo(1, 2.5, bar, yes)").first.function_matchers.first
        expect(f.arguments).to eq([1, 2.5, "bar", true])
      end

      it "accepts the function-name sigils _ ? ! -" do
        f = parse("&first-child").first.function_matchers.first
        expect(f.name).to eq("first-child")
      end
    end

    describe "regexp values" do
      it "parses a bare regexp" do
        v = parse("[k = /foo/]").first.property_matchers.first.value
        expect(v).to be_a(Regexp)
        expect(v.source).to eq("foo")
      end

      it "parses regexp with i flag (IGNORECASE)" do
        v = parse("[k = /foo/i]").first.property_matchers.first.value
        expect(v.options & Regexp::IGNORECASE).not_to eq(0)
      end

      it "parses regexp with m flag (MULTILINE)" do
        v = parse("[k = /foo/m]").first.property_matchers.first.value
        expect(v.options & Regexp::MULTILINE).not_to eq(0)
      end

      it "parses regexp with x flag (EXTENDED)" do
        v = parse("[k = /foo/x]").first.property_matchers.first.value
        expect(v.options & Regexp::EXTENDED).not_to eq(0)
      end

      it "parses regexp with combined flags" do
        v = parse("[k = /foo/imx]").first.property_matchers.first.value
        opts = v.options
        expect(opts & Regexp::IGNORECASE).not_to eq(0)
        expect(opts & Regexp::MULTILINE).not_to eq(0)
        expect(opts & Regexp::EXTENDED).not_to eq(0)
      end

      it "unescapes \\/ inside regexp content" do
        v = parse("[k = /a\\/b/]").first.property_matchers.first.value
        expect(v.source).to eq("a/b")
      end
    end

    describe "ruleset" do
      it "parses multiple rules separated by whitespace" do
        rules = parse("foo bar baz")
        expect(rules.map(&:key)).to eq(%w[foo bar baz])
      end

      it "parses a chained selector path with combinators" do
        rules = parse("country > province ~ building")
        expect(rules.map(&:key)).to eq(%w[country province building])
        expect(rules.map(&:combinator)).to eq([nil, ">", "~"])
      end
    end
  end
end

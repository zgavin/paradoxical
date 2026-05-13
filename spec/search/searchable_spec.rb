require "paradoxical"

# Integration: the Document#search / #find / #find_all surface that
# threads `Paradoxical::Search.parse` + `Rule#matches?` + the traversal
# logic in `Searchable#__search` / `__find` end-to-end. Built on a tiny
# parsed document so any regression in the stack (grammar → Rule
# initializer → matcher → walker) surfaces here without contortions.
RSpec.describe Paradoxical::Elements::Concerns::Searchable do
  let(:doc) do
    Paradoxical::Parser.parse(<<~PDX)
      country = {
        name = alice
        rank = 3
        province = {
          name = paris
          population = 100
        }
      }
      country = {
        name = bob
        rank = 5
      }
    PDX
  end

  describe "#find_all" do
    it "returns every descendent matching a key" do
      results = doc.find_all("country")
      expect(results.size).to eq(2)
      expect(results.all? { |r| r.is_a?(Paradoxical::Elements::List) }).to be true
    end

    it "filters by property matcher" do
      results = doc.find_all("country[name = alice]")
      expect(results.size).to eq(1)
      expect(results.first["name"].value.to_s).to eq("alice")
    end

    it "filters by numeric comparison" do
      results = doc.find_all("country[rank > 4]")
      expect(results.size).to eq(1)
      expect(results.first["name"].value.to_s).to eq("bob")
    end

    it "follows a chained selector path (descendent)" do
      results = doc.find_all("country province")
      expect(results.size).to eq(1)
      expect(results.first["name"].value.to_s).to eq("paris")
    end

    it "honors the > combinator (immediate children only)" do
      # The `province` node lives inside the first `country`, not at the
      # top level — the `> province` rule starts at doc and looks for
      # province as a direct child, which doesn't exist.
      expect(doc.find_all("> province")).to be_empty
    end

    it "accepts a pre-built array of Rule objects" do
      rule = Paradoxical::Search::Rule.new(
        "country",
        property_matchers: [
          Paradoxical::Search::PropertyMatcher.new("name", operator: "=", value: "alice"),
        ],
      )
      results = doc.find_all([rule])
      expect(results.size).to eq(1)
    end

    it "raises ArgumentError on a non-String / non-rules-array argument" do
      expect { doc.find_all(42) }.to raise_error(ArgumentError)
    end
  end

  describe "#find" do
    it "returns the first matching descendent" do
      result = doc.find("country")
      expect(result).to be_a(Paradoxical::Elements::List)
      expect(result["name"].value.to_s).to eq("alice")
    end

    it "returns nil when nothing matches" do
      expect(doc.find("nonexistent")).to be_nil
    end

    it "supports chained selectors" do
      result = doc.find("country province")
      expect(result["name"].value.to_s).to eq("paris")
    end
  end

  describe "#search" do
    it "is an alias for #find_all when passed a string" do
      results = doc.search("country")
      expect(results.size).to eq(2)
    end

    it "raises ArgumentError on a non-String / non-rules-array argument" do
      expect { doc.search(42) }.to raise_error(ArgumentError)
    end
  end
end

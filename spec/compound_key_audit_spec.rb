require "paradoxical"

# Phase 10a audit invariant. PDX save files contain compound keys —
# a List on the LHS of `=` — but no Paradoxical parser emits them yet
# (10b for script, 10c for binary). These tests synthesize the shape
# by hand and assert that every string-key-assuming call site (the
# audit's four guarded paths) handles them without crashing.
#
# When 10b / 10c land, real parsed shapes can replace the hand-built
# fixtures here, but the invariant — name lookups and string filters
# skip non-string keys — should keep holding.
RSpec.describe "compound-key audit (MODERNIZATION phase 10a)" do
  # The compound key itself: a structurally-empty List standing in
  # for `{ demand=pop_demand }` etc. The audit only cares about the
  # key's class, not its contents.
  let(:compound_key) { Paradoxical::Elements::List.new(nil, []) }
  let(:int)          { Paradoxical::Elements::Primitives::Integer.new(1) }
  let(:compound)     { Paradoxical::Elements::Property.new(compound_key, "=", int) }
  let(:string_keyed) { Paradoxical::Elements::Property.new("name", "=", Paradoxical::Elements::Primitives::Integer.new(2)) }
  let(:list)         { Paradoxical::Elements::List.new("outer", [compound, string_keyed]) }

  describe "Arrayable#value_for" do
    it "skips compound-keyed entries and returns the string-keyed value" do
      expect(list.value_for("name").to_i).to eq(2)
    end

    it "returns nil when no string-keyed entry matches" do
      expect(list.value_for("nonexistent")).to be_nil
    end
  end

  describe "Search::PropertyMatcher#matches?" do
    it "skips compound-keyed entries when matching by name" do
      m = Paradoxical::Search::PropertyMatcher.new("name", operator: "=", value: 2)
      expect(m.matches?(list)).to be true
    end

    it "doesn't crash on a list containing only compound-keyed entries" do
      compound_only = Paradoxical::Elements::List.new("outer", [compound])
      m = Paradoxical::Search::PropertyMatcher.new("anything")
      expect(m.matches?(compound_only)).to be false
    end
  end

  describe "Search::FunctionMatcher #key_matches" do
    it "returns false for compound-keyed nodes" do
      m = Paradoxical::Search::FunctionMatcher.new("key_matches", arguments: ["am"])
      expect(m.matches?(compound)).to be false
    end

    it "still matches string-keyed nodes" do
      m = Paradoxical::Search::FunctionMatcher.new("key_matches", arguments: ["am"])
      expect(m.matches?(string_keyed)).to be true
    end
  end

  describe "List#singleton?" do
    # `singleton?` short-circuits on Property children before reaching
    # the string-method calls; the guard matters when the lone child
    # is a *List* whose own key is compound.
    it "doesn't crash when the lone child has a compound key" do
      sublist_with_compound_key = Paradoxical::Elements::List.new(compound_key, [])
      outer = Paradoxical::Elements::List.new("outer", [sublist_with_compound_key])

      expect { outer.singleton? }.not_to raise_error
      expect(outer.singleton?).to be false
    end
  end
end

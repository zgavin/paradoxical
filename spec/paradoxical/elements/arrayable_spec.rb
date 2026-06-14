require "paradoxical"

# Mutation/enumeration helpers mixed into list-like elements. These exercise
# the block-taking filters specifically because a bare `block` reference (no
# `&block` parameter) silently raised NameError for `filter!`/`reject!` until
# the parameter was added.
RSpec.describe Paradoxical::Elements::Concerns::Arrayable do
  def parse(text) = Paradoxical::Parser.parse(text)

  def list(text = "nums = { 1 2 3 }\n") = parse(text).first

  describe "#filter (non-mutating)" do
    it "returns the matching children without mutating the receiver" do
      l = list
      kept = l.filter { |v| v.value.to_s != "2" }
      expect(kept.map { |v| v.value.to_s }).to eq(%w[1 3])
      expect(l.values.map { |v| v.value.to_s }).to eq(%w[1 2 3])
    end

    it "returns an Enumerator when called without a block" do
      expect(list.filter).to be_a(Enumerator)
    end
  end

  describe "#filter!" do
    it "keeps only matching children and mutates in place" do
      l = list
      result = l.filter! { |v| v.value.to_s != "2" }
      expect(result).to be(l)
      expect(l.values.map { |v| v.value.to_s }).to eq(%w[1 3])
    end

    it "detaches removed children from their parent" do
      l = list
      removed = l.values.find { |v| v.value.to_s == "2" }
      l.filter! { |v| v.value.to_s != "2" }
      expect(removed.parent).to be_nil
    end

    it "leaves kept children attached to their parent" do
      l = list
      l.filter! { |v| v.value.to_s != "2" }
      expect(l.values).to all(satisfy { |v| v.parent.equal?(l) })
    end

    it "returns an Enumerator when called without a block" do
      expect(list.filter!).to be_a(Enumerator)
    end
  end

  describe "#reject!" do
    it "removes matching children and detaches them" do
      l = list
      removed = l.values.find { |v| v.value.to_s == "2" }
      result = l.reject! { |v| v.value.to_s == "2" }
      expect(result).to be(l)
      expect(l.values.map { |v| v.value.to_s }).to eq(%w[1 3])
      expect(removed.parent).to be_nil
    end

    it "returns an Enumerator when called without a block" do
      expect(list.reject!).to be_a(Enumerator)
    end
  end

  describe "#select!" do
    it "keeps matching children and detaches the rest" do
      l = list
      removed = l.values.find { |v| v.value.to_s == "2" }
      result = l.select! { |v| v.value.to_s != "2" }
      expect(result).to be(l)
      expect(l.values.map { |v| v.value.to_s }).to eq(%w[1 3])
      expect(removed.parent).to be_nil
    end
  end
end

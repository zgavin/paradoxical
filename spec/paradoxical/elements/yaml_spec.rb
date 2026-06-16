require "paradoxical"

# Coverage for the `encoding` accessor on Yaml localization elements.
# `Mod#write` re-encodes the serialized bytes via `file.encoding`, so a
# Yaml lacking that accessor made writing one raise NoMethodError — see
# the matching regression in spec/mod_spec.rb.
RSpec.describe Paradoxical::Elements::Yaml do
  describe "#encoding" do
    it "defaults to UTF-8" do
      yaml = described_class.new({ GREETING: "hi" }, path: "loc/test_l_english.yml")
      expect(yaml.encoding).to eq(Encoding::UTF_8)
    end

    it "honors an explicit encoding" do
      yaml = described_class.new(
        { GREETING: "hi" },
        path: "loc/test_l_english.yml",
        encoding: Encoding::Windows_1252,
      )
      expect(yaml.encoding).to eq(Encoding::Windows_1252)
    end
  end
end

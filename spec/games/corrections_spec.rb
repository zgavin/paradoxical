require "paradoxical"

RSpec.describe Paradoxical::Games::Corrections do
  describe ".resolve" do
    let(:fix_a) { ->(data) { data << "[A]" } }
    let(:fix_a2) { ->(data) { data << "[A2]" } }
    let(:fix_b) { ->(data) { data << "[B]" } }
    let(:fix_c) { ->(data) { data << "[C]" } }

    it "returns the empty hash when CORRECTIONS is empty" do
      expect(described_class.resolve({}, Gem::Version.new("1.0.0"))).to eq({})
    end

    it "returns the empty hash when installed is nil but CORRECTIONS is empty" do
      expect(described_class.resolve({}, nil)).to eq({})
    end

    it "applies corrections at-or-below the installed version" do
      corrections = {
        "1.0.0" => { "a" => fix_a },
        "1.2.0" => { "b" => fix_b },
        "2.0.0" => { "c" => fix_c },
      }
      result = described_class.resolve(corrections, Gem::Version.new("1.2.0"))
      expect(result.keys).to contain_exactly("a", "b")
    end

    it "later versions override earlier ones for the same path" do
      corrections = {
        "1.0.0" => { "a" => fix_a },
        "1.2.0" => { "a" => fix_a2 },
      }
      result = described_class.resolve(corrections, Gem::Version.new("1.2.0"))
      expect(result["a"]).to be(fix_a2)
    end

    it "an explicit nil at a later version unregisters the path" do
      corrections = {
        "1.0.0" => { "a" => fix_a, "b" => fix_b },
        "1.2.0" => { "a" => nil },
      }
      result = described_class.resolve(corrections, Gem::Version.new("1.2.0"))
      expect(result.keys).to contain_exactly("b")
    end

    it "an unregistered path stays unregistered for later versions" do
      corrections = {
        "1.0.0" => { "a" => fix_a },
        "1.2.0" => { "a" => nil },
        "1.3.0" => { "b" => fix_b },
      }
      result = described_class.resolve(corrections, Gem::Version.new("1.3.0"))
      expect(result.keys).to contain_exactly("b")
    end

    it "skips corrections whose origin version is above installed" do
      corrections = {
        "1.0.0" => { "a" => fix_a },
        "2.0.0" => { "b" => fix_b },
      }
      result = described_class.resolve(corrections, Gem::Version.new("1.5.0"))
      expect(result.keys).to contain_exactly("a")
    end

    it "applies every correction when installed is nil (version-blind)" do
      corrections = {
        "1.0.0" => { "a" => fix_a },
        "99.0.0" => { "b" => fix_b },
      }
      result = described_class.resolve(corrections, nil)
      expect(result.keys).to contain_exactly("a", "b")
    end

    it "respects override semantics even with version-blind apply" do
      corrections = {
        "1.0.0" => { "a" => fix_a },
        "1.2.0" => { "a" => nil },
      }
      result = described_class.resolve(corrections, nil)
      expect(result).to be_empty
    end

    it "handles 4-component versions (HOI4-style) and orders them correctly" do
      corrections = {
        "1.18.1.0" => { "a" => fix_a },
        "1.18.2.0" => { "a" => fix_a2 },
      }
      result = described_class.resolve(corrections, Gem::Version.new("1.18.1.5"))
      expect(result["a"]).to be(fix_a)

      result = described_class.resolve(corrections, Gem::Version.new("1.18.2.0"))
      expect(result["a"]).to be(fix_a2)
    end
  end
end

require "paradoxical"

RSpec.describe Paradoxical::Binary::StringLookup do
  # Tiny helper: build a well-formed string_lookup bytes blob.
  #
  # Header is `0x01 [u16 count] [u16 max_length]`, body is repeated
  # `u16(length) + length-bytes` entries. See the class docstring
  # (and MODERNIZATION.md phase 10f) for the reverse-engineering
  # write-up.
  def lookup_bytes(entries, version: 0x01, count: entries.size, max_length: entries.map(&:bytesize).max || 0)
    body = entries.map { |e| [e.bytesize].pack("v") + e.b }.join
    [version].pack("C") + [count].pack("v") + [max_length].pack("v") + body
  end

  describe ".parse" do
    it "parses a well-formed table into an indexed entries array" do
      lookup = described_class.parse lookup_bytes(["foo", "bar", "longer_string"])

      expect(lookup.size).to eq(3)
      expect(lookup.entries.map(&:string)).to eq(["foo", "bar", "longer_string"])
      expect(lookup.entries.map(&:count)).to eq([0, 0, 0])
    end

    it "parses an empty table" do
      lookup = described_class.parse lookup_bytes([])

      expect(lookup.size).to eq(0)
      expect(lookup.entries).to eq([])
    end

    it "raises ParseError on an unknown version byte" do
      bad = lookup_bytes(["x"], version: 0x02)

      expect { described_class.parse bad }
        .to raise_error(described_class::ParseError, /unknown string_lookup version: 2/)
    end

    it "raises ParseError when the header is truncated" do
      expect { described_class.parse "\x01\x00".b }
        .to raise_error(described_class::ParseError, /header truncated/)
    end

    it "raises ParseError when an entry exceeds the header's max_length" do
      # entries ["foo"] sets the real max to 3, but we declare 2 in the
      # header — the entry's length (3) exceeds it.
      bad = lookup_bytes(["foo"], max_length: 2)

      expect { described_class.parse bad }
        .to raise_error(described_class::ParseError, /length 3 exceeds header max_length 2/)
    end

    it "raises ParseError when there are trailing bytes after the declared count" do
      # Count says 1 entry but we appended a second entry's bytes.
      bad = lookup_bytes(["foo"], count: 1) + [3].pack("v") + "bar".b

      expect { described_class.parse bad }
        .to raise_error(described_class::ParseError, /trailing bytes after 1 entries/)
    end

    it "raises ParseError when an entry's bytes run past EOF" do
      # Header claims 1 entry of length 5, body has only 2 bytes for it.
      truncated = [0x01].pack("C") + [1].pack("v") + [5].pack("v") + [5].pack("v") + "ab".b

      expect { described_class.parse truncated }
        .to raise_error(described_class::ParseError, /ran out of bytes reading entry 0/)
    end
  end

  describe "#resolve" do
    let(:lookup) { described_class.parse lookup_bytes(["alpha", "beta", "gamma"]) }

    it "returns the entry at the given index" do
      expect(lookup.resolve(0)).to eq("alpha")
      expect(lookup.resolve(2)).to eq("gamma")
    end

    it "increments the entry's count on every hit" do
      3.times { lookup.resolve(0) }
      lookup.resolve(2)

      expect(lookup.entries[0].count).to eq(3)
      expect(lookup.entries[1].count).to eq(0)
      expect(lookup.entries[2].count).to eq(1)
    end

    it "raises KeyError on an out-of-range index" do
      expect { lookup.resolve(3) }
        .to raise_error(KeyError, /string_lookup index 3 out of range \(0\.\.2\)/)
      expect { lookup.resolve(-1) }
        .to raise_error(KeyError, /string_lookup index -1 out of range/)
    end
  end
end

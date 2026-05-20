# Parser for the `string_lookup` file that ships alongside `gamestate`
# inside a PDX binary save's outer zip. The lookup table maps integer
# indices to identifier-shaped strings; binary saves use it to compress
# frequently-repeated identifier values (encoded on the wire as
# `LOOKUP_08`/`LOOKUP_16`/`LOOKUP_24` tokens carrying a 1/2/3-byte
# index into this table).
#
# Wire format (reverse-engineered empirically from an EU5 save — see
# MODERNIZATION.md phase 10f):
#
#   byte 0     : version (currently always 0x01)
#   bytes 1-2  : entry count (u16 little-endian)
#   bytes 3-4  : max entry length (u16 little-endian; pre-allocation hint)
#   body       : repeated `u16(length) + length-bytes` entries, count of them
#
# Strictness: this parser raises on any inconsistency — unknown version
# byte, entries longer than the header's max-length hint, a count that
# doesn't consume the body exactly. Lookup files are per-save and we
# control whether we feed them through, so loud failure beats silent
# best-effort.
class Paradoxical::Binary::StringLookup
  class ParseError < StandardError
  end

  HEADER_VERSION = 1
  HEADER_SIZE = 5

  # Each table entry is a `(string, count)` pair. `count` starts at 0
  # at parse time and increments on every `#resolve` hit, so callers
  # can inspect usage frequency after a parse — useful for verifying
  # "are low-index entries the most-referenced ones?" hypotheses and
  # for a future binary writer that wants to re-pack the table by
  # frequency before emitting (smaller-index entries fit in fewer
  # bytes via the `LOOKUP_08`/`LOOKUP_16`/`LOOKUP_24` token range).
  Entry = Struct.new(:string, :count)

  attr_reader :entries

  def self.parse data
    fail ParseError, "header truncated: got #{data.bytesize} bytes, need #{HEADER_SIZE}" if data.bytesize < HEADER_SIZE

    version, count, max_length = data.byteslice(0, HEADER_SIZE).unpack("Cvv")

    fail ParseError, "unknown string_lookup version: #{version} (expected #{HEADER_VERSION})" unless version == HEADER_VERSION

    strings = []
    pos = HEADER_SIZE
    count.times do |i|
      fail ParseError, "ran out of bytes reading length of entry #{i}" if pos + 2 > data.bytesize

      length = data.byteslice(pos, 2).unpack1("v")

      fail ParseError, "entry #{i}: length #{length} exceeds header max_length #{max_length}" if length > max_length

      pos += 2

      fail ParseError, "ran out of bytes reading entry #{i} (need #{length}, have #{data.bytesize - pos})" if pos + length > data.bytesize

      strings << data.byteslice(pos, length)
      pos += length
    end

    fail ParseError, "trailing bytes after #{count} entries: #{data.bytesize - pos}" unless pos == data.bytesize

    new strings
  end

  # Accepts an Array of plain Strings — counts are initialized to 0.
  # Tests and other ad-hoc callers can do
  # `StringLookup.new(["foo", "bar"])` without worrying about the
  # internal Entry struct.
  def initialize strings
    @entries = strings.map do |s| Entry.new s, 0 end
  end

  def size
    @entries.size
  end

  # Look up an integer index in the table and increment the entry's
  # `count`. Raises on out-of-range — callers that want a graceful
  # fallback handle the "no table supplied" case by not calling this
  # at all.
  def resolve index
    unless index.between?(0, @entries.size - 1) then
      raise KeyError, "string_lookup index #{index} out of range (0..#{@entries.size - 1})"
    end

    entry = @entries[index]
    entry.count += 1
    entry.string
  end
end

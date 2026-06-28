class Paradoxical::Elements::Document
  include Paradoxical::Elements::Concerns::Arrayable
  include Paradoxical::Elements::Concerns::Searchable

  attr_reader :path, :full_path, :whitespace, :owner, :encoding

  # `string_lookup` is the per-save `Paradoxical::Binary::StringLookup`
  # table that resolved this document's `LOOKUP_*` tokens, set by the
  # binary parser after construction. Carried on the Document so a
  # future binary writer can re-emit the same lookup file alongside
  # the round-tripped gamestate. Nil for plaintext-parsed docs and
  # binary parses that didn't supply a table. See MODERNIZATION.md
  # phase 10f.
  attr_accessor :string_lookup

  def initialize children = [], whitespace: nil, path: nil, owner: nil, bom: false, encoding: nil
    @children = children
    @whitespace = whitespace
    @bom = bom
    @encoding = encoding

    @children.each do |obj| obj.send(:parent=, self) end

    @path = path

    @owner = owner
  end

  def dup children: nil, path: nil
    copy = self.class.new (children or @children).map(&:dup), whitespace: @whitespace.dup,
                                                              path: path, owner: @owner, bom: @bom, encoding: @encoding
    # `full_path` and `line_break` have no initializer params (the parser
    # stamps them after construction), so carry them across by hand. A dup
    # must be a faithful copy: detach_from_cache swaps it back into the
    # parse cache, where a missing owner/encoding/line_break would silently
    # degrade later re-parses (broken `vanilla?`, lost re-encoding, CRLF
    # round-trips collapsing to LF).
    copy.instance_variable_set :@full_path, @full_path
    copy.instance_variable_set :@line_break, @line_break
    # Shallow-copy the string_lookup reference — the table itself is
    # potentially large (37k+ entries in real saves) and immutable
    # from the doc's perspective, so sharing it across dups is fine
    # for now. If a future caller mutates the lookup post-dup we can
    # revisit.
    copy.string_lookup = @string_lookup
    copy
  end

  def eql? other
    other.is_a?(Paradoxical::Elements::Document) and @children.eql?(other.send(:children))
  end

  def == other
    other.is_a?(Paradoxical::Elements::Document) and @children == other.send(:children)
  end

  def hash
    @children.hash
  end

  def line_break
    @line_break ||= "\n"
  end

  def to_pdx
    buffer = ""

    @children.each_with_index do |obj, i|
      indent = i == 0 ? "" : line_break
      obj.whitespace ||= [indent, nil, nil, nil]
      obj.to_pdx buffer: buffer
    end

    buffer << (whitespace&.first or "")
  end

  def var_refs
    properties
      .select do |p| p.key.is_a? Paradoxical::Elements::Primitives::VariableRef end
      .map do |p| [p.key, p.value] end
      .to_h
  end

  def vanilla?
    @owner.is_a? Paradoxical::Game
  end

  def bom?
    @bom
  end

  def reset_whitespace!
    @whitespace = nil

    @children.each do |object|
      if object.respond_to? :reset_whitespace! then
        object.reset_whitespace!
      end
    end

    self
  end

  def reset_line_breaks!
    descendents
      .flat_map do |n| n.whitespace end
      .compact
      .each do |s| s.gsub! /\r\n?/, "\n" end

    @line_break = "\n"

    self
  end
end

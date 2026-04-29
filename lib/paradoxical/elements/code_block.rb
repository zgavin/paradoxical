class Paradoxical::Elements::CodeBlock < Paradoxical::Elements::List
  attr_accessor :prefix

  def initialize prefix, children, whitespace: nil
    @prefix = prefix
    super false, children, operator: nil, whitespace: whitespace
  end

  # True when the source had `code = [[ ... ]]` (vs bare `code [[ ... ]]`).
  def operator?
    @prefix.include? '='
  end

  def dup
    self.class.new @prefix.dup, @children.map(&:dup), whitespace: @whitespace.dup
  end

  def to_pdx indent: 0, buffer: ""
    iter = (whitespace or []).each
    next_ws = -> (default=" ") { (iter.next or default) rescue default }

    current_indent = line_break + ("\t" * indent)

    buffer << next_ws.call(current_indent)
    buffer << 'code' << @prefix << '[['

    render_children indent: indent, current_indent: current_indent, buffer: buffer

    buffer << next_ws.call(current_indent)
    buffer << ']]'

    buffer
  end

  def inspect
    "#<Paradoxical::Elements::CodeBlock operator?=#{operator?} children=#{children.inspect}>"
  end
end

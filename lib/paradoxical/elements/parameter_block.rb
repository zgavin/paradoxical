class Paradoxical::Elements::ParameterBlock < Paradoxical::Elements::List
  def initialize name, children, negated: false, whitespace: nil
    @negated = negated
    super name, children, operator: nil, whitespace: whitespace
  end

  def negated?
    @negated
  end

  alias_method :name, :key
  alias_method :name=, :key=

  def dup
    self.class.new name.dup, @children.map(&:dup), negated: @negated, whitespace: @whitespace.dup
  end

  def eql? other
    super && other.is_a?(self.class) && @negated == other.negated?
  end

  def == other
    super && other.is_a?(self.class) && @negated == other.negated?
  end

  def hash
    [super, @negated].hash
  end

  def to_pdx indent: 0, buffer: ""
    iter = (whitespace or []).each
    next_ws = -> (default=" ") { (iter.next or default) rescue default }

    current_indent = line_break + ("\t" * indent)

    buffer << next_ws.call(current_indent)
    buffer << '[['
    buffer << '!' if negated?
    buffer << name.to_s
    buffer << ']'

    render_children indent: indent, current_indent: current_indent, buffer: buffer

    buffer << next_ws.call(current_indent)
    buffer << ']'

    buffer
  end

  def inspect
    parts = []
    parts << "negated" if negated?
    parts << "name=#{name.inspect}"
    parts << "children=#{children.inspect}"

    "#<Paradoxical::Elements::ParameterBlock #{parts.join(" ")}>"
  end
end

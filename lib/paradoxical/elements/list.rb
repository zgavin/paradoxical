class Paradoxical::Elements::List < Paradoxical::Elements::Node
  include Paradoxical::Elements::Concerns::Arrayable
  include Paradoxical::Elements::Concerns::Searchable

  attr_accessor :key, :operator, :kind

  def initialize key, children, operator: "=", whitespace: nil, gui_type: false, kind: nil, kind_after_key: false
    @key = key
    @children = children
    @operator = operator
    @whitespace = whitespace
    @kind = kind
    @gui_type = gui_type
    @kind_after_key = kind_after_key

    @children.each do |object|
      raise ArgumentError.new "Must be Paradoxical::Elements::Node: #{object.inspect}" unless object.is_a? Paradoxical::Elements::Node

      object.send(:parent=, self)
    end
  end

  def gui_type?
    @gui_type
  end

  def gui_type= value
    @gui_type = value
  end

  def operator
    # Using nil multiple times in rust seems to cause a segfault, so we use false as a placeholder and replace it the first time we see it
    @operator = nil if @operator == false
    @operator
  end

  def kind
    # Using nil multiple times in rust seems to cause a segfault, so we use false as a placeholder and replace it the first time we see it
    @kind = nil if @kind == false
    @kind
  end

  def dup children: nil, key: nil
    self.class.new((key or @key).dup, (children or @children).map(&:dup), whitespace: @whitespace.dup)
  end

  def eql? other
    other.is_a?(Paradoxical::Elements::List) and @key.eql?(other.key) and @children.eql?(other.send(:children))
  end

  def == other
    other.is_a?(Paradoxical::Elements::List) and @key == other.key and @children == other.send(:children)
  end

  def hash
    [@key, *@children].hash
  end

  def line_break
    document&.line_break or "\n"
  end

  def to_pdx indent: 0, buffer: ""
    iter = (self.whitespace or []).each
    next_ws = ->(default = " ") { (iter.next or default) rescue default }

    current_indent = line_break + ("\t" * indent)

    buffer << next_ws.call(current_indent)

    unless key == false then
      buffer << ("type#{next_ws.call}") if gui_type?
      buffer << (kind + next_ws.call) if kind && !@kind_after_key
      buffer << key.to_pdx
      buffer << next_ws.call
      buffer << (operator + next_ws.call) unless operator.nil?
      buffer << (kind + next_ws.call) if kind && @kind_after_key
    end

    buffer << "{"

    render_children indent: indent, current_indent: current_indent, buffer: buffer

    buffer << next_ws.call(current_indent)
    buffer << "}"

    buffer
  end

  protected

  def render_children indent:, current_indent:, buffer:
    @children.each do |object|
      if object.is_a? Paradoxical::Elements::List then
        object.to_pdx indent: indent + 1, buffer: buffer
      else
        object.to_pdx indent: "#{current_indent}\t", buffer: buffer
      end
    end
  end

  public

  def inspect
    parts = []
    parts << "gui_type" if gui_type?
    parts << "kind=#{kind.inspect}" if kind && !@kind_after_key
    parts << "key=#{key.inspect}"
    parts << "operator=#{operator.inspect}" unless operator.nil?
    parts << "kind=#{kind.inspect}" if kind && @kind_after_key
    parts << "children=#{children.inspect}"

    "#<Paradoxical::Elements::List #{parts.join(" ")}>"
  end

  def single_line! indent: nil
    self.whitespace = [indent, " ", " ", " "]

    @children.each do |object|
      if object.is_a? Paradoxical::Elements::List then
        object.single_line! indent: " "
      elsif object.is_a? Paradoxical::Elements::Property then
        object.whitespace = [" "] * 3
      elsif object.is_a? Paradoxical::Elements::Value then
        object.whitespace = [" "]
      elsif object.respond_to? :whitespace= then
        object.whitespace = [" "]
      end
    end

    self
  end

  def singleton?
    return false if @children.count != 1

    child = @children.first

    return false unless child.respond_to? :key

    return true if child.is_a? Paradoxical::Elements::Property
    return true if %w{add_resource resource_stockpile_compare}.include? child.key
    return true if /_variable$/ =~ child.key

    false
  end

  def reset_whitespace!
    self.whitespace = nil

    @children.each do |object|
      if object.respond_to? :reset_whitespace! then
        object.reset_whitespace!
      end
    end

    self
  end
end

class Paradoxical::Builder
  attr_reader :elements

  def build parent = nil, &block
    @parent = parent

    @elements = []

    self.instance_exec &block

    @elements.reject! do |element| element.parent.present? end

    @elements.pop while elements.last.try :empty_line?

    @elements
  end

  def ignore! *elements
    elements.each do |element|
      index = @elements.index do |other| other.equal? element end

      next if index.nil?

      @elements.delete_at index
    end

    elements.length == 1 ? elements.first : elements
  end

  def push element
    @elements.push element

    element
  end

  def push! element
    return element.map do |e| push! e end if element.is_a? Array

    raise ArgumentError.new "expected a Node or Array as argument" unless element.is_a? Paradoxical::Elements::Node

    @parent.ignore! element unless @parent.nil?

    element.remove unless element.parent.nil?

    push element

    element
  end

  def pop!
    @elements.pop
  end

  def list key, *args, **opts, &block
    args = args.flatten.map do |arg|
      arg.is_a?(Paradoxical::Elements::Node) ? arg : val(arg)
    end

    args.concat(self.class.new.build self, &block) unless block.nil?

    push Paradoxical::Elements::List.new key, args, **opts
  end
  alias_method :l, :list

  def property key, operator, value = nil, whitespace: nil
    push Paradoxical::Elements::Property.new key, operator, value, whitespace: whitespace
  end
  alias_method :p, :property

  def val value, whitespace: nil
    push Paradoxical::Elements::Value.new value, whitespace: whitespace
  end
  alias_method :v, :val

  def literal value, whitespace: nil
    val value.to_s.literal, whitespace: whitespace
  end

  def comment comment, whitespace: nil, inline: nil
    whitespace ||= [" "] if inline
    push Paradoxical::Elements::Comment.new " #{comment}", whitespace: whitespace
  end
  alias_method :c, :comment

  def string string, **opts
    Paradoxical::Elements::Primitives::String.new string, **opts
  end

  # Construct a typed `Primitives::Date` for DSL output. Accepts
  # either three explicit components (`date(1444, 11, 11)`) or a
  # single string with any of `.`, `-`, `/` separators
  # (`date("1444.11.11")` / `date("1444-11-11")` / `date("1444/11/11")`).
  # BC years can be passed as negative integers or as a leading `-`
  # in the string form (`date("-43.1.1")` / `date(-43, 1, 1)`).
  def date *args
    parts =
      if args.length == 3 then
        args.map(&:to_s)
      elsif args.length == 1 then
        pieces = args.first.to_s.split(%r{[.\-/]})
        # A leading `-` (BC-year sign) gets treated as a separator by
        # the split and adds an empty leading piece — reattach it.
        if pieces.length == 4 and pieces.first.empty? then
          ["-#{pieces[1]}", pieces[2], pieces[3]]
        else
          pieces
        end
      else
        raise ArgumentError, "date expects 3 components or a single string; got #{args.length} args"
      end

    raise ArgumentError, "date expects 3 components; got #{parts.inspect}" if parts.length != 3

    Paradoxical::Elements::Primitives::Date.new(parts.join("."))
  end

  # Construct a typed `Primitives::Color::RGB` for DSL output.
  # Accepts:
  #   rgb("ff8000") / rgb("#ff8000") / rgb("0xff8000")  — hex string (6 or 8 hex digits)
  #   rgb(0xff8000)                                     — raw integer (RGB or RRGGBBAA)
  #   rgb(255, 128, 0)                                  — 3 numeric components
  #   rgb(255, 128, 0, 200)                             — 4 numeric components (alpha)
  #   rgb(255, 128, 0, alpha: 200)                      — alpha as a kwarg
  # The `alpha:` kwarg overrides any alpha inferred from positional/
  # hex/integer forms. Float components (`rgb(0.5, 0.3, 0.1)`) flow
  # through to a Float RGB; mixing real Integer (>= 2) and Float
  # components is rejected at construction per RGB homogeneity.
  def rgb *args, alpha: nil
    components = rgb_components_from_args(args)
    components = components[0, 3] + [alpha] unless alpha.nil?
    Paradoxical::Elements::Primitives::Color::RGB.new(components.map do |c| color_component(c) end)
  end

  # `hex(...)` accepts the exact same shapes as `rgb` and returns a
  # `Primitives::Color::Hex`. Implementation is literally
  # `rgb(...).to_hex` — RGB owns the conversion math.
  def hex *args, **opts
    rgb(*args, **opts).to_hex
  end

  # `hsv(h, s, v)` or `hsv(h, s, v, alpha)`; alpha may also be passed
  # via `alpha:`. Components can be any mix of Integer / Float per
  # HSV's permissive shape (`hsv { 0 100 0.8 }` in real game data).
  def hsv *args, alpha: nil
    Paradoxical::Elements::Primitives::Color::HSV.new(color_args(args, alpha, name: "hsv"))
  end

  # `hsv360(h, s, v)` or `hsv360(h, s, v, alpha)`; alpha may also be
  # passed via `alpha:`. Components must be Integer (HSV360 rejects
  # Float at construction per the empirical all-int rule).
  def hsv360 *args, alpha: nil
    Paradoxical::Elements::Primitives::Color::HSV360.new(color_args(args, alpha, name: "hsv360"))
  end

  def empty_list k
    list k, []
  end

  def empty_line
    push Paradoxical::Elements::Value.empty_line
  end

  def pdx_not *args, &block
    obj = l "NOT", *args, &block

    obj.single_line! if obj.singleton?

    obj
  end
  alias_method :not_, :pdx_not

  def pdx_else *args, &block
    obj = l "else", *args, &block

    obj.whitespace = [" ", " ", " ", nil]

    obj
  end
  alias_method :else_, :pdx_else

  def pdx_else_if *args, &block
    obj = l "else_if", *args, &block

    obj.whitespace = [" ", " ", " ", nil]

    obj
  end
  alias_method :else_if_, :pdx_else_if
  alias_method :else_if, :pdx_else_if

  def pdx_if_else_if iterable, &block
    iterable.each_with_index.map do |value, i|
      if i == 0 then
        pdx_if do
          instance_exec value, i, &block
        end
      else
        pdx_else_if do
          instance_exec value, i, &block
        end
      end
    end
  end
  alias_method :if_else_if_, :pdx_if_else_if
  alias_method :if_else_if, :pdx_if_else_if

  def event_target key, *args, &block
    l "event_target:#{key}", *args, &block
  end

  def position x, y
    l("position", p("x", "=", x), p("y", "=", y)).single_line!
  end

  def hidden_position
    l("position", p("x", "=", -10_000), p("y", "=", -10_000)).single_line!
  end

  def off_screen
    position(-10_000, -10_000)
  end

  SIZE_KEYS = {
    container: %w{width height}
  }

  def size x, y, parent: nil
    parent = parent.key == "containerWindowType" ? :container : nil if parent.respond_to?(:key)

    x_key, y_key = parent.nil? ? %w{x y} : SIZE_KEYS[parent]

    l("size", p(x_key, "=", x), p(y_key, "=", y)).single_line!
  end

  %w{if while AND NAND OR NOR}.each do |word|
    define_method "pdx_#{word.downcase}" do |*args, &block|
      l word, *args, &block
    end

    define_method "#{word.downcase}_" do |*args, &block|
      l word, *args, &block
    end
  end

  # `set_variable` / `check_variable` / etc. — game-agnostic base.
  # Each generates a `key { which = NAME value = VALUE }` list.
  # EU4 needs a small wrinkle (uses `which` instead of `value` as
  # the second key for non-numeric values); that override lives in
  # `Paradoxical::Games::EU4::DSL`.
  %w{set check change subtract multiply divide modulo round_variable_to_closest export_to_variable}.each do |word|
    key = word.include?("variable") ? word : "#{word}_variable"

    define_method key do |which, operator, value = nil|
      value, operator = operator, "=" if value.nil?
      l(key, p("which", which), p("value", operator, value)).single_line!
    end
  end

  def export_to_variable which, value, who = nil
    l "export_to_variable" do
      p "which", which
      p "value", value
      p "who", who unless who.nil?
    end.single_line!
  end

  def country_event *args, **opts, &block
    if args.count == 1 and [::String, String].any? do |klass| args.first.is_a? klass end then
      l("country_event", p("id", args.first)).single_line!
    else
      l "country_event", *args, **opts, &block
    end
  end

  def limit *args, &block
    obj = l "limit", *args, &block

    obj.single_line! if obj.singleton?

    obj
  end

  def potential *args, &block
    obj = l "potential", *args, &block

    obj.single_line! if obj.singleton?

    obj
  end

  def pdx_obj key, *args, **opts, &block
    args = args.map do |v| v.nil? ? empty_line : v end

    if args.empty? and block.nil? then
      string key
    elsif args.all? do |obj| obj.is_a? Paradoxical::Elements::Node end then
      l key, *args, **opts, &block
    elsif args.none? do |obj| obj.is_a? Paradoxical::Elements::Node end then
      p key, *args, **opts
    else
      raise ArgumentError.new "expected all Node or all Primitive arguments"
    end
  end

  def _
    empty_line
  end

  def method_missing sym, *args, **opts, &block
    super if sym.to_s.ends_with? "="

    return empty_line if sym == :_

    pdx_obj sym.to_s, *args, **opts, &block
  end

  private

  # Dispatch for the rgb helper's 1-arg vs 3-or-4-arg forms.
  def rgb_components_from_args args
    return args if [3, 4].include?(args.length)

    if args.length != 1 then
      raise ArgumentError, "rgb expects 1 (hex/int), 3 (r,g,b), or 4 (r,g,b,alpha) args; got #{args.length}"
    end

    case (raw = args.first)
    when ::String  then rgb_components_from_hex_string(raw)
    when ::Integer then rgb_components_from_integer(raw)
    else raise ArgumentError, "rgb single-arg form expects String or Integer; got #{raw.class}"
    end
  end

  def rgb_components_from_hex_string str
    hex = str.delete_prefix("#").delete_prefix("0x")

    unless hex.match?(/\A[0-9a-fA-F]+\z/) and [6, 8].include?(hex.length)
      raise ArgumentError, "rgb hex string must be 6 or 8 hex digits, got #{str.inspect}"
    end

    hex.scan(/../).map do |pair| pair.to_i(16) end
  end

  def rgb_components_from_integer n
    raise ArgumentError, "rgb integer must be 0..0xffffffff, got #{n}" unless n.between?(0, 0xffffffff)

    if n > 0xffffff then
      [(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]
    else
      [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]
    end
  end

  # Shared dispatch for the hsv / hsv360 helpers — both take 3-or-4
  # numeric components with an optional `alpha:` kwarg override.
  def color_args args, alpha, name:
    unless [3, 4].include?(args.length)
      raise ArgumentError, "#{name} expects 3 or 4 components; got #{args.length}"
    end

    components = args
    components = components[0, 3] + [alpha] unless alpha.nil?
    components.map do |c| color_component(c) end
  end

  # Wrap a Ruby Integer / Float into the matching `Primitives::*`
  # primitive. Pass-through if already typed. Used by every color
  # helper so DSL callers can supply either plain numbers or
  # pre-built primitives.
  def color_component c
    case c
    when Paradoxical::Elements::Primitives::Integer, Paradoxical::Elements::Primitives::Float
      c
    when ::Float
      Paradoxical::Elements::Primitives::Float.new(c.to_s)
    when ::Integer
      Paradoxical::Elements::Primitives::Integer.new(c.to_s)
    else
      raise ArgumentError, "color component must be Integer or Float, got #{c.class}"
    end
  end
end

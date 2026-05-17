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
    # Mirror Property#initialize's nil-shift so we coerce the actual
    # value rather than the operator standing in for it.
    value, operator = operator, "=" if value.nil?

    push Paradoxical::Elements::Property.new(
      Paradoxical::Elements::Primitives::VariableRef.coerce(key),
      operator,
      Paradoxical::Elements::Primitives::VariableRef.coerce(value),
      whitespace: whitespace
    )
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

  # Thin DSL wrappers around the `Color::*` class-method factories.
  # The dispatch / parsing logic lives on the typed classes
  # themselves (`Color::RGB.from`, `Color.component`) so this file
  # stays free of private helper methods — Builder is extended
  # into the DSL scope and `method_missing` falls through to
  # `pdx_obj`, so any private name we'd add here would silently
  # shadow that name as a DSL reserved word.

  # See `Color::RGB.from` for the supported input shapes:
  # hex string, raw integer, or 3-4 numeric components, with an
  # optional `alpha:` kwarg override.
  def rgb *args, alpha: nil
    Paradoxical::Elements::Primitives::Color::RGB.from(*args, alpha: alpha)
  end

  # Same input shapes as `rgb`; returns a `Color::Hex` via the
  # `to_hex` conversion that RGB owns.
  def hex *args, **opts
    rgb(*args, **opts).to_hex
  end

  # `hsv(h, s, v[, alpha])` or `hsv(h, s, v, alpha: a)`. Components
  # can be any mix of Integer / Float per HSV's permissive shape
  # (`hsv { 0 100 0.8 }` in real game data).
  def hsv *args, alpha: nil
    raise ArgumentError, "hsv expects 3 or 4 components; got #{args.length}" unless [3, 4].include?(args.length)

    components = args
    components = components[0, 3] + [alpha] unless alpha.nil?

    Paradoxical::Elements::Primitives::Color::HSV.new(
      components.map do |c| Paradoxical::Elements::Primitives::Color.component(c) end
    )
  end

  # `hsv360(h, s, v)` — 3 integer components, no alpha. PDX itself
  # doesn't emit 4-component hsv360 and the parser grammar rejects
  # it, so DSL-emitting one would be write-only garbage. Components
  # must be Integer (HSV360 rejects Float at construction per the
  # empirical all-int rule).
  def hsv360 *args
    raise ArgumentError, "hsv360 expects 3 components; got #{args.length}" if args.length != 3

    Paradoxical::Elements::Primitives::Color::HSV360.new(
      args.map do |c| Paradoxical::Elements::Primitives::Color.component(c) end
    )
  end

  # Construct a typed `Primitives::Percentage` for DSL output.
  # Accepts any numeric (Ruby Integer/Float/BigDecimal or
  # `Primitives::Integer`/`Float`) or a string. Numerics route
  # through `to_pdx` so precision matches the active game's
  # `FLOAT_PRECISION` cap and BigDecimal serializes as plain decimal
  # rather than scientific. Strings pass through as-is, with a
  # trailing `%` appended if missing — so `percent("50")` and
  # `percent("50%")` both produce the same `50%`. Multi-`%` literals
  # (`"+10.00%%"`) are preserved.
  def percent value
    str = value.is_a?(::String) ? value : value.to_pdx
    str = "#{str}%" unless str.end_with?("%")
    Paradoxical::Elements::Primitives::Percentage.new(str)
  end

  # Construct a typed `Primitives::VariableRef` for DSL output.
  # Accepts the name with or without a leading `@` so DSL callers can
  # write either `var_ref("my_const")` or `var_ref("@my_const")` —
  # both produce the same `@my_const` ref. Symbols also accepted for
  # parity with other DSL helpers that read like identifiers.
  #
  # If a second argument is provided, builds a definition property
  # (`@name = value`) and pushes it. The two-arg form is the natural
  # shape for the top-of-file `@constant = 5` def block:
  #   var_ref :scale, 100
  #   var_ref :base_rate, percent(50)
  def var_ref name, value = nil
    raw = name.to_s
    raw = "@#{raw}" unless raw.start_with?("@")
    ref = Paradoxical::Elements::Primitives::VariableRef.new raw

    return ref if value.nil?

    property ref, value
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

  # Variable-arithmetic helpers (`set_variable`, `change_variable`,
  # `multiply_variable`, etc.) live in per-game DSL modules — the
  # body shape varies by game: HOI4 uses direct `key = value` bodies,
  # EU4/Stellaris use `which`/`value` keys, EU5/Imperator use
  # `name`/`value` with chainable operations. See phase 5e in
  # MODERNIZATION.md.

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
end

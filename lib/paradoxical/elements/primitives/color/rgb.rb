class Paradoxical::Elements::Primitives::Color::RGB < Paradoxical::Elements::Primitives::Color
  channels :r, :g, :b, :alpha

  def type; "rgb"; end

  def justify!
    if @components.length == 3 then
      strs = @components.map(&:to_pdx)
      @whitespace = [nil, *strs.map do |c| " " * (4 - c.length) end, nil]
    else
      raise NotImplementedError, "justify! for 4-component rgb is a phase 8 follow-up"
    end

    self
  end

  # https://en.wikipedia.org/wiki/HSL_and_HSV#From_RGB
  def to_hsv
    raise NotImplementedError, "4-component rgb -> hsv conversion is a phase 8 follow-up" if @components.length != 3

    r, g, b = @components.map do |c| c.to_i / 255.0 end

    x_max = [r, g, b].max
    x_min = [r, g, b].min

    v = x_max
    c = x_max - x_min

    h =
      if c == 0 then
        0
      elsif v == r then
        ((g - b) / c)
      elsif v == g then
        ((b - r) / c) + 2
      elsif v == b then
        ((r - g) / c) + 4
      end

    h /= 6
    h += 1 if h < 0

    s = v == 0 ? 0 : c / v

    components = [h, s, v].map do |val|
      Paradoxical::Elements::Primitives::Float.new("%.3f" % val)
    end

    Paradoxical::Elements::Primitives::Color::HSV.new(components)
  end

  def to_rgb
    dup
  end

  def to_hsv360
    raise NotImplementedError, "rgb -> hsv360 conversion is a phase 8 follow-up"
  end

  def to_hex
    raise NotImplementedError, "rgb -> hex conversion is a phase 8 follow-up"
  end
end

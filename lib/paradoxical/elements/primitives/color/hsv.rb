class Paradoxical::Elements::Primitives::Color::HSV < Paradoxical::Elements::Primitives::Color
  channels :h, :s, :v, :alpha

  def justify!
    if @components.length == 3 then
      @whitespace = []
      @components = @components.map do |val|
        Paradoxical::Elements::Primitives::Float.new("%.3f" % val.to_f)
      end
    else
      raise NotImplementedError, "justify! for 4-component hsv is a phase 8 follow-up"
    end

    self
  end

  # https://en.wikipedia.org/wiki/HSL_and_HSV#HSV_to_RGB
  def to_rgb
    raise NotImplementedError, "4-component hsv -> rgb conversion is a phase 8 follow-up" if @components.length != 3

    h, s, v = @components.map(&:to_f)

    c = v * s
    h_prime = (h * 6) % 6
    x = c * (1 - ((h_prime % 2) - 1).abs)

    r1, g1, b1 =
      if h_prime >= 0 and h_prime < 1 then
        [c, x, 0]
      elsif h_prime >= 1 and h_prime < 2 then
        [x, c, 0]
      elsif h_prime >= 2 and h_prime < 3 then
        [0, c, x]
      elsif h_prime >= 3 and h_prime < 4 then
        [0, x, c]
      elsif h_prime >= 4 and h_prime < 5 then
        [x, 0, c]
      elsif h_prime >= 5 and h_prime < 6 then
        [c, 0, x]
      end

    m = v - c

    components = [r1, g1, b1].map do |c|
      Paradoxical::Elements::Primitives::Integer.new(((c + m) * 255).to_i.to_s)
    end

    Paradoxical::Elements::Primitives::Color::RGB.new(components)
  end

  def to_hsv
    dup
  end

  def to_hsv360
    raise NotImplementedError, "hsv -> hsv360 conversion is a phase 8 follow-up"
  end

  def to_hex
    raise NotImplementedError, "hsv -> hex conversion is a phase 8 follow-up"
  end
end

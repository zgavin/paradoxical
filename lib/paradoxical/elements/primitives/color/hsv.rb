class Paradoxical::Elements::Primitives::Color::HSV < Paradoxical::Elements::Primitives::Color
  channels :h, :s, :v, :alpha

  def type; "hsv"; end

  def justify!
    @whitespace = []
    @components = @components.map do |val| make_float(val.to_f) end

    self
  end

  # https://en.wikipedia.org/wiki/HSL_and_HSV#HSV_to_RGB
  # If any normalized component exceeds 1 (HDR-extended brightness or
  # hue >= 1), output is Float RGB so the HDR value is preserved.
  # Otherwise output is Integer RGB (0..255) — the conventional shape.
  def to_rgb
    hn, sn, vn = normalized_components

    c = vn * sn
    h_prime = (hn * 6) % 6
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
      else
        [0, 0, 0]
      end

    m = vn - c
    floats = [r1 + m, g1 + m, b1 + m]
    alpha_n = normalized_alpha

    hdr = floats.any? do |f| f > 1.0 end || (!alpha_n.nil? and alpha_n > 1.0)

    components =
      if hdr then
        floats.map do |f| make_float(f) end
      else
        floats.map do |f| make_int((f * 255).round) end
      end

    if !alpha_n.nil? then
      components << (hdr ? make_float(alpha_n) : make_int((alpha_n * 255).round))
    end

    Paradoxical::Elements::Primitives::Color::RGB.new(components)
  end

  def to_hsv
    dup
  end

  # HSV → HSV360 multiplies into degrees (h × 360) and percentages
  # (s × 100, v × 100). HDR-extended HSV maps to HDR-extended HSV360
  # (s/v > 100, real-data example: `hsv360 { 245 40 150 }`). Alpha
  # is dropped — HSV360 doesn't carry alpha in any observed file.
  def to_hsv360
    hn, sn, vn = normalized_components

    components = [
      make_int((hn * 360).round),
      make_int((sn * 100).round),
      make_int((vn * 100).round),
    ]

    Paradoxical::Elements::Primitives::Color::HSV360.new(components)
  end

  def to_hex
    to_rgb.to_hex
  end

  private

  # Per-component interpretation rule:
  #   Integer -> /100 (percentage style — `hsv { 0 100 0.8 }` form)
  #   Float   -> as-is (0..1 fraction, HDR-extended above 1 ok)
  # HSV is the most permissive subtype — empirically ships mixed
  # types in real game data (Stellaris light colors etc.), so no
  # homogeneity validation.
  def normalized_components
    @components.first(3).map do |c| normalize(c) end
  end

  def normalized_alpha
    a = @components[3]
    a.nil? ? nil : normalize(a)
  end

  def normalize c
    c.instance_of?(Paradoxical::Elements::Primitives::Float) ? c.to_f : c.to_i / 100.0
  end
end

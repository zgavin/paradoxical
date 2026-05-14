class Paradoxical::Elements::Primitives::Color::RGB < Paradoxical::Elements::Primitives::Color
  channels :r, :g, :b, :alpha

  def type; "rgb"; end

  def justify!
    strs = @components.map(&:to_pdx)
    @whitespace = [nil, *strs.map do |c| " " * (4 - c.length) end, nil]

    self
  end

  # https://en.wikipedia.org/wiki/HSL_and_HSV#From_RGB
  # Always emits Float HSV (the canonical math form); HDR-extended
  # inputs (Float RGB with components > 1) flow through unclamped so
  # downstream code can see the brightness multiplier.
  def to_hsv
    rn, gn, bn = normalized_components

    x_max = [rn, gn, bn].max
    x_min = [rn, gn, bn].min

    v = x_max
    c = x_max - x_min

    h =
      if c == 0 then
        0
      elsif v == rn then
        ((gn - bn) / c)
      elsif v == gn then
        ((bn - rn) / c) + 2
      elsif v == bn then
        ((rn - gn) / c) + 4
      end

    h /= 6
    h += 1 if h < 0

    s = v == 0 ? 0 : c / v

    components = [h, s, v].map do |val| make_float(val) end
    components << make_float(normalized_alpha) unless normalized_alpha.nil?

    Paradoxical::Elements::Primitives::Color::HSV.new(components)
  end

  def to_rgb
    dup
  end

  # HSV360 is integer-only. Route via HSV so the math lives in one
  # place; HSV → HSV360 rounds the components to degrees / percents.
  # Alpha is dropped — HSV360 doesn't carry one (no empirical
  # 4-component hsv360 in any installed game).
  def to_hsv360
    to_hsv.to_hsv360
  end

  # Hex packs each channel into a 2-char hex pair (channel value
  # clamped to 0..255). HDR Float inputs > 1 saturate at "ff" — hex
  # is a fixed 0..255 representation and can't carry HDR.
  def to_hex
    pairs = normalized_components.map do |c|
      (c.clamp(0, 1) * 255).round.to_s(16).rjust(2, "0")
    end
    pairs << ((normalized_alpha.clamp(0, 1) * 255).round.to_s(16).rjust(2, "0")) unless normalized_alpha.nil?

    Paradoxical::Elements::Primitives::Color::Hex.new("0x#{pairs.join}")
  end

  private

  # RGB components are either all Integer (0..255 channels) or all
  # Float (0..1 fractions, HDR-extended allowed) — with one wrinkle.
  # Integer 0 and 1 are polymorphic: they're written without a decimal
  # in the source (so the parser types them as Integer), but they're
  # valid endpoints of the 0..1 fraction range too. EU5 ships e.g.
  # `rgb { 0.502 0 0.612 }`, mixing float fractions with a bare `0`.
  # So we only reject when a *real* integer (>= 2) appears alongside
  # a float — that's the unambiguous shape mismatch.
  def validate!
    has_real_int = @components.any? do |c|
      c.instance_of?(Paradoxical::Elements::Primitives::Integer) and c.to_i > 1
    end
    has_float = @components.any? do |c|
      c.instance_of?(Paradoxical::Elements::Primitives::Float)
    end

    return unless has_real_int and has_float

    raise ArgumentError,
          "rgb components must all be Integer (0..255) or all Float (0..1, HDR allowed); " \
          "Integer 0/1 ride along with floats, but Integer >= 2 mixed with Float is invalid: " \
          "#{@components.map(&:to_pdx).inspect}"
  end

  # Per-component interpretation rule for conversion math:
  #   Integer -> /255 (channel value in 0..255)
  #   Float   -> as-is (fraction in 0..1, HDR-extended above 1 ok)
  # See the phase-8b discussion in the decision log for why this beats
  # an all-or-nothing rule — real game data ships `rgb { 0.5 0 0.7 }`
  # where the bare `0` is polymorphically a fraction endpoint.
  def normalized_components
    @components.first(3).map do |c| normalize(c) end
  end

  def normalized_alpha
    a = @components[3]
    a.nil? ? nil : normalize(a)
  end

  def normalize c
    c.instance_of?(Paradoxical::Elements::Primitives::Float) ? c.to_f : c.to_i / 255.0
  end
end

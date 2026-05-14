class Paradoxical::Elements::Primitives::Color::HSV360 < Paradoxical::Elements::Primitives::Color
  channels :h, :s, :v

  def type; "hsv360"; end

  def justify!
    # Hue tops out at 360 (3 digits); s/v at 100 (3 digits) but can
    # extend higher for HDR. Pad each component to width 3 so the
    # canonical form is `hsv360 { 245  40 150 }` style.
    strs = @components.map(&:to_pdx)
    @whitespace = [nil, *strs.map do |c| " " * [4 - c.length, 1].max end, nil]

    self
  end

  # All conversions route through HSV — HSV360 is just HSV with
  # different scales (degrees / percentages), so converting via
  # the 0..1 fraction form keeps the math in one place.
  def to_rgb
    to_hsv.to_rgb
  end

  def to_hsv
    hn, sn, vn = normalized_components

    components = [hn, sn, vn].map do |val| make_float(val) end

    Paradoxical::Elements::Primitives::Color::HSV.new(components)
  end

  def to_hsv360
    dup
  end

  def to_hex
    to_hsv.to_rgb.to_hex
  end

  private

  # HSV360 is integer-only across all observed PDX data (826 unique
  # values in EU5 alone, zero floats). Values can extend above the
  # natural (0..360, 0..100, 0..100) ranges for HDR brightness
  # (`hsv360 { 245 40 150 }` etc.) so we don't range-check, but we
  # do refuse float components.
  def validate!
    return if @components.all? do |c| c.instance_of?(Paradoxical::Elements::Primitives::Integer) end

    names = @components.map do |c| c.class.name.split("::").last end.join(", ")
    raise ArgumentError, "hsv360 components must all be Integer; got #{names}"
  end

  # h is 0..360 → /360; s, v are 0..100 → /100. HDR-extended values
  # (s/v > 100) ride through and produce normalized values > 1.
  def normalized_components
    h, s, v = @components.first(3).map(&:to_i)
    [h / 360.0, s / 100.0, v / 100.0]
  end
end

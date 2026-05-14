class Paradoxical::Elements::Primitives::Color::HSV360 < Paradoxical::Elements::Primitives::Color
  def h       ; @components[0]      end
  def h= v    ; @components[0] = v  end
  def s       ; @components[1]      end
  def s= v    ; @components[1] = v  end
  def v       ; @components[2]      end
  def v= v    ; @components[2] = v  end

  def justify!
    raise NotImplementedError, "justify! for hsv360 is a phase 8 follow-up"
  end

  def to_rgb
    raise NotImplementedError, "hsv360 -> rgb conversion is a phase 8 follow-up"
  end

  def to_hsv
    raise NotImplementedError, "hsv360 -> hsv conversion is a phase 8 follow-up"
  end

  def to_hsv360
    self
  end

  def to_hex
    raise NotImplementedError, "hsv360 -> hex conversion is a phase 8 follow-up"
  end
end

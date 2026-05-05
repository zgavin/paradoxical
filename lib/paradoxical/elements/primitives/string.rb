class Paradoxical::Elements::Primitives::String
  include Paradoxical::Elements::Concerns::Impersonator

  impersonate ::String

  impersonate_infix_methods %i{!~ % * + =~ <<}

  def initialize string, quoted: nil
    if quoted.nil? then
      @quoted = (string.start_with? '"' and string.end_with? '"')

      super @quoted ? string[1..-2] : string
    else
      @quoted = quoted

      super string
    end
  end

  def quoted?
    @quoted
  end

  def dup
    self.class.new @value, quoted: @quoted
  end

  def to_pdx
    @quoted ? %{"#{self}"} : self
  end

  def coerce something
    case something
    when String
      [@value.to_s, something]
    else
      super
    end
  end
end

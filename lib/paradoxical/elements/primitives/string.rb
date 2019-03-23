class Paradoxical::Elements::Primitives::String
  include Paradoxical::Elements::Concerns::Impersonator
  
  impersonate ::String
  
  impersonate_infix_methods %i{ !~ % * + =~ << }
  
  attr_reader :is_quoted
  
  def initialize string, is_quoted: nil
    if is_quoted.nil? then
      @is_quoted = ( string.start_with? '"' and string.end_with? '"' ) 
      
      super @is_quoted ? string[1..-2] : string
    else
      @is_quoted = is_quoted
      
      super string
    end
  end

  def dup
    self.class.new @value, is_quoted: @is_quoted
  end
  
  def to_pdx
    @is_quoted ? %{"#{self}"} : self
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
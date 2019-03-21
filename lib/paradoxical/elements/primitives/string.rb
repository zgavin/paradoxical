class Paradoxical::Elements::Primitives::String
  include Paradoxical::Elements::Concerns::Impersonator
  
  impersonate ::String
  
  impersonate_infix_methods %i{ !~ % * + =~ << }
  
  def initialize string
    @is_quoted = ( string.start_with? '"' and string.end_with? '"' )
    
    super( @is_quoted ? string[1..-2] : string )
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
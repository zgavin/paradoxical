class Paradoxical::Elements::Primitives::Float 
  include Paradoxical::Elements::Concerns::Impersonator
  
  impersonate ::Float
  
  impersonate_infix_methods %i{ !~ % * ** + - / =~ }
  
  def coerce something
    case something
    when Float
      [@value.to_f, something]
    when Integer
      [@value.to_i, something]
    else
      super
    end
  end
end
class Paradoxical::Transformer < Parslet::Transform
  def self.s s
    simple( s )
  end

  # primitives
  rule boolean: s(:x) do x == 'yes' and true or false end
		
  %i{ date float integer string }.each do |key|
    rule key => s(:x) do Paradoxical::Elements::Primitives.const_get( key.to_s.classify ).new x end
  end

	rule string: simple(:x), quote: simple(:quote) do Paradoxical::Elements::Primitives::String.new %{"#{x.to_s}"} end

	# value
	rule value: simple(:value), whitespace: simple(:whitespace) do Paradoxical::Elements::Value.new value, whitespace: [whitespace] end

  # comments 
  rule comment: simple(:comment), whitespace: simple(:whitespace) do Paradoxical::Elements::Comment.new comment.to_s[1..-1], whitespace: [whitespace] end

  # properties
  rule( %i{key value operator whitespace leading trailing}.map do |k| [k, simple(k)] end.to_h ) do 
		ws = [ whitespace, leading, trailing ]
		
		Paradoxical::Elements::Property.new key, operator, value, whitespace: ws
	end
	
  # lists    
  rule( %i{key operator whitespace leading trailing closing}.map do |k| [k, simple(k)] end.to_h.merge list: sequence(:list) ) do
    list = self.list rescue []
    
		ws = [ whitespace, leading, trailing, closing ]
		
    Paradoxical::Elements::List.new key, list, operator: operator, whitespace: ws
	end
  
  rule list: sequence(:list), whitespace: simple(:whitespace) do Paradoxical::Elements::Document.new list, whitespace: [whitespace] end
  
  rule keyless_list: sequence(:keyless_list), whitespace: simple(:whitespace), closing: simple(:closing) do 
		ws = [ whitespace, closing ]
		
		Paradoxical::Elements::List.new false, keyless_list, whitespace: ws
  end
end
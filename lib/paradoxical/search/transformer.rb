class Paradoxical::Search::Transformer < Parslet::Transform
  # primitives
  rule date:    simple(:x) do s = x.to_s.split('.').map(&:to_i); Date.new(*s, Date::JULIAN) end
  rule float:   simple(:x) do Float(x) end
  rule integer: simple(:x) do Integer(x) end
  rule boolean: simple(:x) do ( x == 'yes' or x == 'true' ) ? true : false end
	
	# strings
	rule string:  simple(:x) do x.to_s end
    
  rule argument: simple(:x) do x end

  
    
  rule regexp: simple(:regexp) do Regexp.new regexp.to_s end
  rule regexp: simple(:regexp), options: simple(:string_options) do 
    options = string_options.to_s.split('').reduce(0) do |value, option| value | { m: Regexp::MULTILINE, i: Regexp::IGNORECASE, x: Regexp::EXTENDED }[option.to_sym] end 
    Regexp.new regexp.to_s, options
  end
  
  rule rule_key: simple(:key) do Paradoxical::Search::Rule.new key end
   
  (1..5).map do |i| %i{combinator id name property_matchers function_matchers}.combination(i).to_a end.flatten(1).each do |fields|
    opts = { rule_key: simple(:key) }
    
    opts.merge!( fields.map do |field| [ field, %i{combinator id name}.include?(field) ? simple(field) : subtree(field) ] end.to_h )
    
    rule opts do 
      rule_opts = fields.map do |field| 
        value = eval(field.to_s)
        
        value = Array(value) unless %i{combinator id}.include? field
        
        [field, value] 
      end.to_h
        
      Paradoxical::Search::Rule.new key.to_s, rule_opts
    end
  end
  
  rule key: simple(:key) do Paradoxical::Search::PropertyMatcher.new key end
  rule key: simple(:key), operator: simple(:operator), value: simple(:value) do Paradoxical::Search::PropertyMatcher.new key.to_s, operator: operator.to_s, value: value end 
    
  rule name: simple(:name) do Paradoxical::Search::FunctionMatcher.new name end
  rule name: simple(:name), arguments: subtree(:arguments) do Paradoxical::Search::FunctionMatcher.new name, arguments: Array(arguments) end

  rule rules: sequence(:rules) do rules end
end
class Paradoxical::Parser < Parslet::Parser
  rule :document do
    expression.repeat.as(:list) >> whitespace.as(:whitespace)
  end

  rule :expression do
    comment | property | list | array_list
  end

  rule :comment do 
    whitespace.as(:whitespace) >> ( str('#') >> (end_of_line.absent? >> any).repeat ).as(:comment)
  end
	
	rule :value do
		whitespace.as(:whitespace) >> primitive.as(:value)
	end

  rule :property do 
    whitespace.as(:whitespace) >> primitive.as(:key) >> whitespace.as(:leading) >> operator.as(:operator) >> whitespace.as(:trailing) >> primitive.as(:value)
  end

  rule :list do 
    whitespace.as(:whitespace) >> primitive.as(:key) >> whitespace.as(:leading) >> operator.as(:operator) >> whitespace.as(:trailing) >> str('{') >> expression.repeat.as(:list) >> whitespace.as(:closing) >> str('}')
  end
	
	rule :array_list do
		whitespace.as(:whitespace) >> primitive.as(:key) >> whitespace.as(:leading) >> operator.as(:operator) >> whitespace.as(:trailing) >> str('{') >> ( value | comment | keyless_list ).repeat.as(:list) >> whitespace.as(:closing) >> str('}')
	end
  
  rule :keyless_list do
    whitespace.as(:whitespace) >> str('{') >> expression.repeat.as(:keyless_list) >> whitespace.as(:closing) >> str('}')
  end

  rule :primitive do
    percentage_string | date.as(:date) | float.as(:float) | integer.as(:integer) | boolean | empty_string | string_literal | character 
  end

	rule :operator do
		( str('=') | str('>=') | str('<=') | str('>') | str('<') )
	end

  rule :date do
    match['\\d'].repeat(1,4) >> str('.') >> match['\\d'].repeat(1,2) >> str('.') >> match['\\d'].repeat(1,2) 
  end

  rule :numeric do
    match['\\d'].repeat(1)
  end

  rule :float do
    ( integer.maybe >> str('.') >> numeric ) | ( integer >> str('.') >> numeric.maybe )
  end

  rule :integer do 
    str('-').maybe >> numeric
  end

  rule :boolean do
     ( str('yes') | str('no') ).as(:boolean)  >> match['\\w'].absent? 
  end

  rule :character do
    (match('\\w') >> match['\\w'].absent?).as(:string)
  end

  rule :string_literal do
    ( ( str('@') | match['\\w'] ) >> (match['\\s'].absent? >> match['=><'].absent? >> match('[\\{\\}]').absent? >> any).repeat(1)).as(:string) | ( str('"').as(:quote) >> (str('"').absent? >> any).repeat.as(:string) >> str('"') )
  end
  
  rule :empty_string do
    str('"').as(:quote) >> str('').as(:string) >> str('"')
  end
  
  rule :percentage_string do
    ( numeric >> str('%').repeat(1) ).as(:string)
  end

  rule :whitespace do
    match[' \\t\\r\\n'].repeat(1) | str("")
  end

  rule :end_of_line do
    str("\r").maybe >> str("\n")
  end

  root :document
end
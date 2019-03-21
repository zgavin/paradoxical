class Paradoxical::Search::Parser < Parslet::Parser
  rule :ruleset do
    rule.repeat.as(:rules) >> whitespace
  end

  rule :rule do
    whitespace >> ( str('>').as(:combinator) >> whitespace ).maybe >> ( with_key | without_key ) >> property_matchers.maybe >> function_matchers.maybe
  end
  
  rule :with_key do
    ( str('*') | key_name ).as(:rule_key) >> name_or_id.maybe
  end
  
  rule :without_key do
    str('').as(:rule_key) >> name_or_id
  end
  
  rule :name_or_id do
    ( id >> name ) | ( name >> id ) | id | name
  end
  
  rule :id do
    str('#') >> string.as(:id)
  end
  
  rule :name do
    str('.') >> string.as(:name)
  end
  
  rule :property_matchers do
    str('[') >>  ( ( property_matcher >>  str(',') ).repeat >> property_matcher  ).as(:property_matchers) >> str(']') 
  end
  
  rule :property_matcher do
    whitespace >> unquoted_string.as(:key) >> ( whitespace >> operator.as(:operator) >> whitespace >> value.as(:value) ).maybe
  end
  
  rule :function_matchers do
    function_matcher.repeat(1).as(:function_matchers)
  end
  
  rule :function_matcher do
    match[':'] >> unquoted_string.as(:name) >> ( str('(') >> ( argument >> str(',') ).repeat >> argument  >> str(')') ).as(:arguments).maybe 
  end
  
  rule :argument do
    whitespace >> (value | regexp).as(:argument) >> whitespace
  end

	rule :operator do
		str('=') | str('>=') | str('>') | str('<') | str('<=') | str('~=') | str('^=') | str('$=')
	end
  
  rule :value do
    date.as(:date) | float.as(:float) | integer.as(:integer) | boolean | string 
  end

  rule :date do
    match['\\d'].repeat(1,4) >> str('.') >> match['\\d'].repeat(1,2) >> str('.') >> match['\\d'].repeat(1,2) 
  end

  rule :numeric do
    match['\\d'].repeat(1)
  end

  rule :float do
    integer >> str('.') >> numeric 
  end

  rule :integer do 
    str('-').maybe >> numeric
  end

  rule :boolean do
     ( str('yes') | str('no') | str('true') | str('false') ).as(:boolean)
  end

  rule :string do
    ( unquoted_string | single_quoted_string | double_quoted_string )
  end
  
  rule :key_name do
    ( match['A-Za-z_'] >> match['\\w\\-'].repeat ).as :string
  end
  
  rule :unquoted_string do
    ( match['A-Za-z_'] >> match['\\w\\-\\.'].repeat ).as :string
  end

  rule :single_quoted_string do
    str("'") >> ( ( str('\\') >> any ) |  ( str("'").absent? >> any ) ).repeat.as(:string) >> str("'")
  end

  rule :double_quoted_string do
    str('"') >> ( ( str('\\') >> any ) |  ( str('"').absent? >> any ) ).repeat.as(:string) >> str('"')
  end
  
  rule :regexp do
    str('/') >> ( ( str('\\') >> any ) |  ( str('/').absent? >> any ) ).repeat.as(:regexp) >> str('/') >> match['mxi'].repeat.maybe.as(:options)
  end

  rule :whitespace do
    match[' \\t\\r\\n'].repeat
  end

  root :ruleset
end
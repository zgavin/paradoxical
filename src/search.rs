
use rutie::{ Object, RString, VM, Array, Hash, Symbol, AnyObject, Class, Module, Boolean, Integer, Float };

extern crate pest;
use pest::Parser;
use pest::iterators::Pairs;
use pest::iterators::Pair;

extern crate regex;
use self::regex::Regex;



#[derive(Parser)]
#[grammar = "search.pest"]
struct SearchParser;

class!(ParadoxicalParser);

methods!(
    ParadoxicalParser,
    _itself,

    fn parse(data: RString) -> Array {
        let string = data.map_err(|e| VM::raise_ex(e) ).unwrap().to_string();

        let pairs = SearchParser::parse(Rule::ruleset, &string ).map_err(|e|  
            VM::raise( Module::from_existing("Paradoxical").get_nested_module("Search").get_nested_module("Parser").get_nested_class("ParseError"), &e.to_string()  )  
        ).unwrap();

        return ruleset(pairs)
    }
);

fn ruleset( pairs: Pairs<Rule> ) -> Array {
    let mut rules = Array::new();

    for pair in pairs {
        match pair.as_rule() {
            Rule::rule => {
                rules.push( rule( pair ) );
            }
            Rule::EOI => {}
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        }
    }

    return rules
}

fn rule( pair:Pair<Rule> ) -> AnyObject {
    let mut options = Hash::new();

    let mut key = s("*");
    let mut property_matchers = Array::new();
    let mut function_matchers = Array::new();

    for pair in pair.into_inner() {
        match pair.as_rule() {
            Rule::key => { 
                if pair.as_str() != "*" {
                    let mut iter = pair.into_inner();

                    let inner = iter.next().unwrap();

                    key = string( inner ); 
                } 
            }
            Rule::name | Rule::id  => {
                let rule = pair.as_rule();

                let mut iter = pair.into_inner();

                let inner = iter.next().unwrap();

                let string = string( inner ).to_any_object();

                let key = k( if rule == Rule::name { "name" } else { "id"} );

                options.store( key, string );
            }
            Rule::property_matcher => { 
                property_matchers.push( property_matcher( pair ) ); 
            }
            Rule::function_matcher => {
                function_matchers.push( function_matcher( pair ) );
            }
            Rule::combinator => {
                options.store( k("combinator"), p( pair ) );
            }
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        };
    }

    options.store( k("property_matchers"), property_matchers.to_any_object() );
    options.store( k("function_matchers"), function_matchers.to_any_object() );

    let class = Module::from_existing("Paradoxical").get_nested_module("Search").get_nested_class("Rule");

    let arguments = [key.to_any_object(), options.to_any_object()];

    return class.new_instance(&arguments);
}

fn property_matcher( pair:Pair<Rule> ) -> AnyObject {
    let mut options = Hash::new();

    let mut key:Option<AnyObject> = None;

    for pair in pair.into_inner() {
        match pair.as_rule() {
            Rule::string => {
                key = Some( string( pair ).to_any_object() );
            }
            Rule::pm_operator => {
                options.store( k("operator"), p( pair ) );
            }
            Rule::pm_sensitivity => {
                options.store( k("case_sensitivity"), p( pair ) );
            }
            Rule::value => {
                options.store( k("value"), value( pair ) );
            }
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        }
    }

    let class = Module::from_existing("Paradoxical").get_nested_module("Search").get_nested_class("PropertyMatcher");

    let arguments = [ key.unwrap(), options.to_any_object()];

    return class.new_instance(&arguments);
}

fn function_matcher( pair:Pair<Rule> ) -> AnyObject {
    let mut options = Hash::new();

    let mut name:Option<AnyObject> = None;
    let mut function_arguments = Array::new();    

    for pair in pair.into_inner() {
        match pair.as_rule() {
            Rule::function_name => { 
                name = Some( p( pair ).to_any_object() );  
            }
            Rule::value => {
                function_arguments.push( value( pair ) );
            }
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        }
    }

    options.store( k("arguments"), function_arguments );

    let class = Module::from_existing("Paradoxical").get_nested_module("Search").get_nested_class("FunctionMatcher");

    let arguments = [ name.unwrap(), options.to_any_object()];

    return class.new_instance(&arguments);
}

fn value( pair:Pair<Rule> ) -> AnyObject {
    let mut iter = pair.into_inner();

    let inner = iter.next().unwrap();

    match inner.as_rule() {
        Rule::string => { 
            string( inner ).to_any_object() 
        }
        Rule::integer => { 
            Integer::new( inner.as_str().parse::<i64>().unwrap() ).to_any_object() 
        }
        Rule::float => { 
            Float::new( inner.as_str().parse::<f64>().unwrap() ).to_any_object() 
        }
        Rule::boolean => { 
            let string = inner.as_str();

            Boolean::new( string == "yes" || string == "true" ).to_any_object()
        }
        Rule::regexp => { regexp( inner ) }
        _ => {
            println!("rule: {:?}", inner.as_rule());
            unreachable!()
        }
    }
}

lazy_static! {
    static ref REGEXP_REGEX:Regex = Regex::new(r"\\/").unwrap();
}

fn regexp ( pair:Pair<Rule> ) -> AnyObject {
    let class = Class::from_existing("Regexp");

    let mut contents:Option<AnyObject> = None;
    let mut flag = 0;
    
    for pair in pair.into_inner() {
        match pair.as_rule() {
            Rule::regexp_content => { 
                let replaced  = REGEXP_REGEX.replace_all( pair.as_str(), "/" );

                contents = Some( s( &replaced ).to_any_object() );
            },
            Rule::regexp_flag => {
                let s = pair.as_str();
                flag = flag | match s {
                    "m" => 4,
                    "i" => 1,
                    "x" => 2,
                    _ => { unreachable!() }
                };
            }
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        }
    }

    let arguments = [ contents.unwrap(), Integer::new( flag ).to_any_object() ];

    return class.new_instance(&arguments);
}

lazy_static! {
    static ref STRING_REGEX:Regex = Regex::new(r"\\(.)").unwrap();
}

fn string( pair:Pair<Rule>) -> RString {
    let mut iter = pair.into_inner();

    let inner = iter.next().unwrap();

    match inner.as_rule() {
        Rule::unquoted_string => p( inner ),
        Rule::single_quoted_string | Rule::double_quoted_string => {
            let mut string = inner.as_str();

            string = &string[1..(string.len()-1)];
            
            let replaced = STRING_REGEX.replace_all(&string, "$1");

            s( &replaced )
        }
        _ => {
            println!("rule: {:?}", inner.as_rule());
            unreachable!()
        }
    }

}

fn p( pair:Pair<Rule> ) -> RString {
    RString::new_utf8( pair.as_str() )
}

fn s( s:&str ) -> RString {
    RString::new_utf8( s )
}

fn k( s:&str ) -> Symbol {
    Symbol::new(s)
}
#[macro_use]
extern crate rutie;
use rutie::{ Object, RString, VM, Array, Hash, Symbol, AnyObject, Module, Boolean };

extern crate pest;
use pest::Parser;
use pest::iterators::Pairs;
use pest::iterators::Pair;

#[macro_use]
extern crate pest_derive;

#[macro_use]
extern crate lazy_static;

#[derive(Parser)]
#[grammar = "script.pest"]
struct ScriptParser;

mod search;

class!(ParadoxicalParser);

methods!(
    ParadoxicalParser,
    _itself,

    fn parse(data: RString) -> AnyObject {
        let string = data.map_err(|e| VM::raise_ex(e) ).unwrap().to_string_unchecked();


        let pairs = ScriptParser::parse(Rule::document, &string ).map_err(|e|  
            VM::raise( Module::from_existing("Paradoxical").get_nested_module("Parser").get_nested_class("ParseError"), &e.to_string()  )  
        ).unwrap();

        return document( pairs )
    }
);

fn document( pairs: Pairs<Rule> ) -> AnyObject {
    let mut hash = Hash::new();
    let mut children = Array::new();
    let mut whitespace = Array::new();

    for pair in pairs {
        match pair.as_rule() {
            Rule::comment => { children.push( comment(pair) ); },
            Rule::property => { children.push( property(pair) ); },
            Rule::list => { children.push( list(pair) ); },
            Rule::ws => { whitespace.push( p( pair ) ); },
            Rule::EOI => {},
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        };
    }

    hash.store( k( "whitespace" ), whitespace );

    let class = Module::from_existing("Paradoxical").get_nested_module("Elements").get_nested_class("Document");

    let arguments = [children.to_any_object(), hash.to_any_object()];

    return class.new_instance(Some(&arguments));
}

fn comment( pair:Pair<Rule> ) -> AnyObject {
    let mut hash = Hash::new();
    let mut whitespace = Array::new();

    let mut key = s("");

    for pair in pair.into_inner() {
        match pair.as_rule() {
            Rule::ws => { whitespace.push( p( pair ) ); },
            Rule::comment_text => { key = p(pair); },
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        };
    }

    hash.store( k( "whitespace" ), whitespace );

    let class = Module::from_existing("Paradoxical").get_nested_module("Elements").get_nested_class("Comment");

    let arguments = [key.to_any_object(), hash.to_any_object()];

    return class.new_instance(Some(&arguments));
}

fn value( pair:Pair<Rule> ) -> AnyObject {
    let mut hash = Hash::new();
    let mut whitespace = Array::new();

    let mut value = s("").to_any_object();

    for pair in pair.into_inner() {
        match pair.as_rule() {
            Rule::ws => { whitespace.push( p( pair ) ); },
            Rule::primitive => { value = primitive(pair); },
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        };
    }

    hash.store( k( "whitespace" ), whitespace );

    let class = Module::from_existing("Paradoxical").get_nested_module("Elements").get_nested_class("Value");

    let arguments = [value.to_any_object(), hash.to_any_object()];

    return class.new_instance(Some(&arguments));
}

fn property( pair:Pair<Rule> ) -> AnyObject {
    let mut hash = Hash::new();
    let mut whitespace = Array::new();
    
    let mut key = s("").to_any_object();
    let mut value = s("").to_any_object();
    let mut operator = s("");

    let mut did_set_key = false;

    for pair in pair.into_inner() {
        match pair.as_rule() {
            Rule::ws => { whitespace.push( p( pair ) ); },
            Rule::operator => { operator = p( pair ) },
            Rule::primitive => { 
                if did_set_key { 
                    value = primitive(pair);   
                } else { 
                    key = primitive(pair); 
                    did_set_key = true;  
                }
            },
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        };
    }

    hash.store( k( "whitespace" ), whitespace );

    let class = Module::from_existing("Paradoxical").get_nested_module("Elements").get_nested_class("Property");

    let arguments = [key.to_any_object(), operator.to_any_object(), value.to_any_object(), hash.to_any_object()];

    return class.new_instance(Some(&arguments));
}

fn list( pair:Pair<Rule> ) -> AnyObject {
    let mut hash = Hash::new();
    let mut children = Array::new();
    let mut whitespace = Array::new();

    let mut key = s("").to_any_object();
    let mut operator = s("");

    for pair in pair.into_inner() {
        match pair.as_rule() {
            Rule::primitive => { key = primitive( pair ) },
            Rule::operator => { operator = p( pair ) },
            Rule::ws => { whitespace.push( p( pair ) ); },
            _ => {
                let child = match pair.as_rule() {
                    Rule::comment => comment(pair),
                    Rule::property => property(pair),
                    Rule::list => list(pair),
                    Rule::value => value( pair ),
                    Rule::keyless_list => keyless_list( pair ),
                    _ => {
                        println!("rule: {:?}", pair.as_rule());
                        unreachable!()
                    }
                };

                children.push( child );
            }
        };
    }

    hash.store( k( "whitespace" ), whitespace );
    hash.store( k( "operator" ), operator );

    let class = Module::from_existing("Paradoxical").get_nested_module("Elements").get_nested_class("List");

    let arguments = [key.to_any_object(), children.to_any_object(), hash.to_any_object()];

    return class.new_instance(Some(&arguments));
}

fn keyless_list( pair:Pair<Rule> ) -> AnyObject {
    let mut hash = Hash::new();
    let mut children = Array::new();
    let mut whitespace = Array::new();

    for pair in pair.into_inner() {
        match pair.as_rule() {
            Rule::ws => { whitespace.push( p( pair ) ); },
            _ => {
                let child = match pair.as_rule() {
                    Rule::comment => comment(pair),
                    Rule::property => property(pair),
                    Rule::list => list(pair),
                    _ => {
                        println!("rule: {:?}", pair.as_rule());
                        unreachable!()
                    }
                };

                children.push( child );
            }
        };
    }

    hash.store( k( "whitespace" ), whitespace );

    let class = Module::from_existing("Paradoxical").get_nested_module("Elements").get_nested_class("List");

    let arguments = [Boolean::new(false).to_any_object(), children.to_any_object(), hash.to_any_object()];

    return class.new_instance(Some(&arguments));
}

fn primitive( pair:Pair<Rule> ) -> AnyObject {
    let mut class_name = "String";

    let mut value = s("");

    for pair in pair.into_inner() {
        class_name = match pair.as_rule() {
            Rule::date => "Date",
            Rule::float => "Float",
            Rule::integer => "Integer",
            Rule::string | Rule::percentage => "String",
            Rule::boolean => "Boolean",
            _ => {
                println!("rule: {:?}", pair.as_rule());
                unreachable!()
            }
        };

        value = p(pair);
    }

    if class_name == "Boolean"  {
         let bool_value = if value.to_str_unchecked() == "yes" { true } else { false };

        return Boolean::new(bool_value).to_any_object();
    } else {
        let class = Module::from_existing("Paradoxical").get_nested_module("Elements").get_nested_module("Primitives").get_nested_class(class_name);

        let arguments = [ value.to_any_object() ];

        return class.new_instance(Some(&arguments));
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
    
#[allow(non_snake_case)]
#[no_mangle]
pub extern "C" fn Init_Rust_Parser() {
    Module::from_existing("Paradoxical").get_nested_module("Parser").define(|itself| {
        itself.def_self("parse", parse);
    });

    Module::from_existing("Paradoxical").get_nested_module("Search").get_nested_module("Parser").define(|itself| {
        itself.def_self("parse", search::parse);
    });
}
    

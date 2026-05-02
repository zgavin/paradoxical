use magnus::{
    function, kwargs,
    prelude::*,
    value::{Lazy, ReprValue},
    Error, ExceptionClass, IntoValue, RArray, RClass, RModule, RString, Ruby, Value,
};

use pest::iterators::{Pair, Pairs};
use pest::Parser;
use pest_derive::Parser;

#[derive(Parser)]
#[grammar = "script.pest"]
struct ScriptParser;

mod search;

fn paradoxical(ruby: &Ruby) -> RModule {
    ruby.class_object().const_get("Paradoxical").unwrap()
}

fn elements(ruby: &Ruby) -> RModule {
    paradoxical(ruby).const_get("Elements").unwrap()
}

fn primitives(ruby: &Ruby) -> RModule {
    elements(ruby).const_get("Primitives").unwrap()
}

static DOCUMENT_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| elements(ruby).const_get("Document").unwrap());
static COMMENT_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| elements(ruby).const_get("Comment").unwrap());
static VALUE_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| elements(ruby).const_get("Value").unwrap());
static PROPERTY_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| elements(ruby).const_get("Property").unwrap());
static LIST_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| elements(ruby).const_get("List").unwrap());
static PARAMETER_BLOCK_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| elements(ruby).const_get("ParameterBlock").unwrap());
static CODE_BLOCK_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| elements(ruby).const_get("CodeBlock").unwrap());

static COLOR_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| primitives(ruby).const_get("Color").unwrap());
static DATE_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| primitives(ruby).const_get("Date").unwrap());
static FLOAT_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| primitives(ruby).const_get("Float").unwrap());
static INTEGER_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| primitives(ruby).const_get("Integer").unwrap());
static STRING_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| primitives(ruby).const_get("String").unwrap());

fn parse(ruby: &Ruby, data: String) -> Result<Value, Error> {
    let pairs = ScriptParser::parse(Rule::document, &data).map_err(|e| {
        let parser: RModule = paradoxical(ruby).const_get("Parser").unwrap();
        let parse_error: ExceptionClass = parser.const_get("ParseError").unwrap();
        Error::new(parse_error, e.to_string())
    })?;

    Ok(document(ruby, pairs))
}

fn document(ruby: &Ruby, pairs: Pairs<Rule>) -> Value {
    let children = RArray::new();
    let whitespace = RArray::new();

    for pair in pairs {
        match pair.as_rule() {
            Rule::comment => children.push(comment(ruby, pair)).unwrap(),
            Rule::property => children.push(property(ruby, pair)).unwrap(),
            Rule::list => children.push(list(ruby, pair)).unwrap(),
            Rule::parameter_block => children.push(parameter_block(ruby, pair)).unwrap(),
            Rule::code_block => children.push(code_block(ruby, pair)).unwrap(),
            Rule::value => children.push(value(ruby, pair)).unwrap(),
            Rule::keyless_list => children.push(keyless_list(ruby, pair)).unwrap(),
            Rule::ws => whitespace.push(p(ruby, pair)).unwrap(),
            Rule::EOI => {}
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    ruby.get_inner(&DOCUMENT_CLASS)
        .new_instance((children, kwargs!(ruby, "whitespace" => whitespace)))
        .unwrap()
}

fn comment(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let whitespace = RArray::new();
    let mut key = s(ruby, "");

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::ws => whitespace.push(p(ruby, inner)).unwrap(),
            Rule::comment_text => key = p(ruby, inner),
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    ruby.get_inner(&COMMENT_CLASS)
        .new_instance((key, kwargs!(ruby, "whitespace" => whitespace)))
        .unwrap()
}

fn value(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let whitespace = RArray::new();
    let mut val: Value = s(ruby, "").as_value();

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::ws => whitespace.push(p(ruby, inner)).unwrap(),
            Rule::primitive => val = primitive(ruby, inner),
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    ruby.get_inner(&VALUE_CLASS)
        .new_instance((val, kwargs!(ruby, "whitespace" => whitespace)))
        .unwrap()
}

fn property(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let whitespace = RArray::new();

    let mut key: Value = s(ruby, "").as_value();
    let mut val: Value = s(ruby, "").as_value();
    let mut operator: RString = s(ruby, "");

    let mut did_set_key = false;

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::ws => whitespace.push(p(ruby, inner)).unwrap(),
            Rule::operator => operator = p(ruby, inner),
            Rule::primitive => {
                if did_set_key {
                    val = primitive(ruby, inner);
                } else {
                    key = primitive(ruby, inner);
                    did_set_key = true;
                }
            }
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    ruby.get_inner(&PROPERTY_CLASS)
        .new_instance((key, operator, val, kwargs!(ruby, "whitespace" => whitespace)))
        .unwrap()
}

fn list(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let children = RArray::new();
    let whitespace = RArray::new();

    let mut kind: Value = ruby.qfalse().as_value();
    let mut key: Value = s(ruby, "").as_value();
    let mut operator: Value = ruby.qfalse().as_value();
    let mut gui_type = false;

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::primitive => key = primitive(ruby, inner),
            Rule::operator => operator = p(ruby, inner).as_value(),
            Rule::ws => whitespace.push(p(ruby, inner)).unwrap(),
            Rule::prefixed_kind | Rule::gui_type_kind | Rule::scripted_kind | Rule::list_kind => {
                kind = p(ruby, inner).as_value()
            }
            Rule::gui_type => gui_type = true,
            _ => {
                let child = match inner.as_rule() {
                    Rule::comment => comment(ruby, inner),
                    Rule::property => property(ruby, inner),
                    Rule::list => list(ruby, inner),
                    Rule::value => value(ruby, inner),
                    Rule::keyless_list => keyless_list(ruby, inner),
                    Rule::parameter_block => parameter_block(ruby, inner),
                    Rule::code_block => code_block(ruby, inner),
                    r => unreachable!("unexpected rule: {:?}", r),
                };
                children.push(child).unwrap();
            }
        }
    }

    ruby.get_inner(&LIST_CLASS)
        .new_instance((
            key,
            children,
            kwargs!(
                ruby,
                "kind" => kind,
                "whitespace" => whitespace,
                "operator" => operator,
                "gui_type" => gui_type
            ),
        ))
        .unwrap()
}

fn keyless_list(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let children = RArray::new();
    let whitespace = RArray::new();

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::ws => whitespace.push(p(ruby, inner)).unwrap(),
            _ => {
                let child = match inner.as_rule() {
                    Rule::comment => comment(ruby, inner),
                    Rule::property => property(ruby, inner),
                    Rule::list => list(ruby, inner),
                    Rule::value => value(ruby, inner),
                    Rule::keyless_list => keyless_list(ruby, inner),
                    Rule::parameter_block => parameter_block(ruby, inner),
                    Rule::code_block => code_block(ruby, inner),
                    r => unreachable!("unexpected rule: {:?}", r),
                };
                children.push(child).unwrap();
            }
        }
    }

    ruby.get_inner(&LIST_CLASS)
        .new_instance((false, children, kwargs!(ruby, "whitespace" => whitespace)))
        .unwrap()
}

fn parameter_block(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let children = RArray::new();
    let whitespace = RArray::new();

    let mut name: RString = s(ruby, "");
    let mut negated = false;

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::ws => whitespace.push(p(ruby, inner)).unwrap(),
            Rule::negated => negated = true,
            Rule::parameter_name => name = p(ruby, inner),
            Rule::comment => children.push(comment(ruby, inner)).unwrap(),
            Rule::property => children.push(property(ruby, inner)).unwrap(),
            Rule::list => children.push(list(ruby, inner)).unwrap(),
            Rule::parameter_block => children.push(parameter_block(ruby, inner)).unwrap(),
            Rule::code_block => children.push(code_block(ruby, inner)).unwrap(),
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    ruby.get_inner(&PARAMETER_BLOCK_CLASS)
        .new_instance((
            name,
            children,
            kwargs!(ruby, "negated" => negated, "whitespace" => whitespace),
        ))
        .unwrap()
}

fn code_block(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let children = RArray::new();
    let whitespace = RArray::new();
    let mut prefix: RString = s(ruby, "");

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::ws => whitespace.push(p(ruby, inner)).unwrap(),
            Rule::code_block_prefix => prefix = p(ruby, inner),
            Rule::comment => children.push(comment(ruby, inner)).unwrap(),
            Rule::property => children.push(property(ruby, inner)).unwrap(),
            Rule::list => children.push(list(ruby, inner)).unwrap(),
            Rule::parameter_block => children.push(parameter_block(ruby, inner)).unwrap(),
            Rule::code_block => children.push(code_block(ruby, inner)).unwrap(),
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    ruby.get_inner(&CODE_BLOCK_CLASS)
        .new_instance((
            prefix,
            children,
            kwargs!(ruby, "whitespace" => whitespace),
        ))
        .unwrap()
}

fn primitive(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let mut class: Option<RClass> = None;
    let mut text: RString = s(ruby, "");

    for inner in pair.into_inner() {
        let rule = inner.as_rule();
        text = p(ruby, inner);

        let cls: Option<RClass> = match rule {
            Rule::color => Some(ruby.get_inner(&COLOR_CLASS)),
            Rule::date => Some(ruby.get_inner(&DATE_CLASS)),
            Rule::float => Some(ruby.get_inner(&FLOAT_CLASS)),
            Rule::integer => Some(ruby.get_inner(&INTEGER_CLASS)),
            Rule::string | Rule::percentage | Rule::placeholder => Some(ruby.get_inner(&STRING_CLASS)),
            Rule::boolean => None,
            r => unreachable!("unexpected rule: {:?}", r),
        };

        if cls.is_none() {
            return (text.to_string().unwrap() == "yes").into_value_with(ruby);
        }

        class = cls;
    }

    class
        .expect("primitive had no inner rule")
        .new_instance((text,))
        .unwrap()
}

fn p(_ruby: &Ruby, pair: Pair<Rule>) -> RString {
    RString::new(pair.as_str())
}

fn s(_ruby: &Ruby, text: &str) -> RString {
    RString::new(text)
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let paradoxical: RModule = ruby.class_object().const_get("Paradoxical")?;

    let parser: RModule = paradoxical.const_get("Parser")?;
    parser.define_singleton_method("parse", function!(parse, 1))?;

    let search_module: RModule = paradoxical.const_get("Search")?;
    let search_parser: RModule = search_module.const_get("Parser")?;
    search_parser.define_singleton_method("parse", function!(search::parse, 1))?;

    Ok(())
}

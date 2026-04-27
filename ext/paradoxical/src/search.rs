use std::sync::LazyLock;

use magnus::{
    prelude::*,
    value::{Lazy, ReprValue},
    Error, ExceptionClass, IntoValue, RArray, RClass, RHash, RModule, RString, Ruby, Symbol, Value,
};

use pest::iterators::{Pair, Pairs};
use pest::Parser;
use pest_derive::Parser;

use regex::Regex;

#[derive(Parser)]
#[grammar = "search.pest"]
struct SearchParser;

fn paradoxical(ruby: &Ruby) -> RModule {
    ruby.class_object().const_get("Paradoxical").unwrap()
}

fn search(ruby: &Ruby) -> RModule {
    paradoxical(ruby).const_get("Search").unwrap()
}

static RULE_CLASS: Lazy<RClass> = Lazy::new(|ruby| search(ruby).const_get("Rule").unwrap());
static PROPERTY_MATCHER_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| search(ruby).const_get("PropertyMatcher").unwrap());
static FUNCTION_MATCHER_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| search(ruby).const_get("FunctionMatcher").unwrap());
static REGEXP_CLASS: Lazy<RClass> =
    Lazy::new(|ruby| ruby.class_object().const_get("Regexp").unwrap());

static REGEXP_ESCAPED_SLASH: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\\/").unwrap());
static STRING_ESCAPE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\\(.)").unwrap());

pub fn parse(ruby: &Ruby, data: String) -> Result<RArray, Error> {
    let pairs = SearchParser::parse(Rule::ruleset, &data).map_err(|e| {
        let parser_module: RModule = search(ruby).const_get("Parser").unwrap();
        let parse_error: ExceptionClass = parser_module.const_get("ParseError").unwrap();
        Error::new(parse_error, e.to_string())
    })?;

    Ok(ruleset(ruby, pairs))
}

fn ruleset(ruby: &Ruby, pairs: Pairs<Rule>) -> RArray {
    let rules = RArray::new();

    for pair in pairs {
        match pair.as_rule() {
            Rule::rule => rules.push(rule(ruby, pair)).unwrap(),
            Rule::EOI => {}
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    rules
}

fn rule(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let options = RHash::new();
    let mut key: Value = s("*").as_value();
    let property_matchers = RArray::new();
    let function_matchers = RArray::new();

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::key => {
                if inner.as_str() != "*" {
                    let next = inner.into_inner().next().unwrap();
                    key = string(next).as_value();
                }
            }
            Rule::name | Rule::id => {
                let r = inner.as_rule();
                let next = inner.into_inner().next().unwrap();
                let val = string(next);
                let key_name = if r == Rule::name { "name" } else { "id" };
                options.aset(k(key_name), val).unwrap();
            }
            Rule::property_matcher => {
                property_matchers
                    .push(property_matcher(ruby, inner))
                    .unwrap();
            }
            Rule::function_matcher => {
                function_matchers
                    .push(function_matcher(ruby, inner))
                    .unwrap();
            }
            Rule::combinator => {
                options.aset(k("combinator"), p(inner)).unwrap();
            }
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    options
        .aset(k("property_matchers"), property_matchers)
        .unwrap();
    options
        .aset(k("function_matchers"), function_matchers)
        .unwrap();

    ruby.get_inner(&RULE_CLASS)
        .new_instance((key, options))
        .unwrap()
        .as_value()
}

fn property_matcher(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let options = RHash::new();
    let mut key: Option<RString> = None;

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::string => key = Some(string(inner)),
            Rule::pm_operator => {
                options.aset(k("operator"), p(inner)).unwrap();
            }
            Rule::pm_sensitivity => {
                options.aset(k("case_sensitivity"), p(inner)).unwrap();
            }
            Rule::value => {
                options.aset(k("value"), value(ruby, inner)).unwrap();
            }
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    ruby.get_inner(&PROPERTY_MATCHER_CLASS)
        .new_instance((key.unwrap(), options))
        .unwrap()
        .as_value()
}

fn function_matcher(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let options = RHash::new();
    let mut name: Option<RString> = None;
    let function_arguments = RArray::new();

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::function_name => name = Some(p(inner)),
            Rule::value => {
                function_arguments.push(value(ruby, inner)).unwrap();
            }
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    options.aset(k("arguments"), function_arguments).unwrap();

    ruby.get_inner(&FUNCTION_MATCHER_CLASS)
        .new_instance((name.unwrap(), options))
        .unwrap()
        .as_value()
}

fn value(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let inner = pair.into_inner().next().unwrap();

    match inner.as_rule() {
        Rule::string => string(inner).as_value(),
        Rule::integer => inner.as_str().parse::<i64>().unwrap().into_value_with(ruby),
        Rule::float => inner.as_str().parse::<f64>().unwrap().into_value_with(ruby),
        Rule::boolean => {
            let text = inner.as_str();
            (text == "yes" || text == "true").into_value_with(ruby)
        }
        Rule::regexp => regexp(ruby, inner),
        r => unreachable!("unexpected rule: {:?}", r),
    }
}

fn regexp(ruby: &Ruby, pair: Pair<Rule>) -> Value {
    let mut contents: Option<RString> = None;
    let mut flag: i64 = 0;

    for inner in pair.into_inner() {
        match inner.as_rule() {
            Rule::regexp_content => {
                let replaced = REGEXP_ESCAPED_SLASH.replace_all(inner.as_str(), "/");
                contents = Some(s(&replaced));
            }
            Rule::regexp_flag => {
                let text = inner.as_str();
                flag |= match text {
                    "m" => 4,
                    "i" => 1,
                    "x" => 2,
                    _ => unreachable!(),
                };
            }
            r => unreachable!("unexpected rule: {:?}", r),
        }
    }

    ruby.get_inner(&REGEXP_CLASS)
        .new_instance((contents.unwrap(), flag))
        .unwrap()
        .as_value()
}

fn string(pair: Pair<Rule>) -> RString {
    let inner = pair.into_inner().next().unwrap();

    match inner.as_rule() {
        Rule::unquoted_string => p(inner),
        Rule::single_quoted_string | Rule::double_quoted_string => {
            let text = inner.as_str();
            let trimmed = &text[1..(text.len() - 1)];
            let replaced = STRING_ESCAPE.replace_all(trimmed, "$1");
            s(&replaced)
        }
        r => unreachable!("unexpected rule: {:?}", r),
    }
}

fn p(pair: Pair<Rule>) -> RString {
    RString::new(pair.as_str())
}

fn s(text: &str) -> RString {
    RString::new(text)
}

fn k(name: &str) -> Symbol {
    Symbol::new(name)
}

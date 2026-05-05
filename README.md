# Paradoxical

A Ruby gem for parsing, editing, and re-serializing the proprietary script
files used by Paradox Interactive games — EU4, Stellaris, Imperator: Rome,
and EU5. The parser is Rust (a [`pest`](https://pest.rs) grammar exposed as
a native extension via [`magnus`](https://github.com/matsadler/magnus)); the
rest is Ruby, including a small DSL for writing mods that compile down to
Paradox's script format.

## Status

This is a personal long-term project, not a published library. The gem
isn't on RubyGems — install it locally (instructions below). Current
state:

- Runs on Ruby 3.2.0 + Rust 1.95.0 (pinned in `.tool-versions`).
- Round-trip preserves the original bytes — whitespace, comments, BOMs,
  CRLF line endings — so editing is non-destructive.
- The parser regression suite walks every script file in EU4 / EU5 /
  Stellaris / Imperator and their engine-default sibling dirs (16,727
  files total) — all parse cleanly. HOI4 parses ~99.3% of its 5,342
  files; the 37 known gaps are baselined in
  `spec/fixtures/parse_smoke_allow_hoi4.yml` for incremental triage.
- See [`MODERNIZATION.md`](MODERNIZATION.md) for the phased plan and
  decision log.

## Supported games

The "validated versions" column lists every patch level the parse
smoke has been run against without regression. New entries get added
as Paradox ships patches; older entries stay so users on a back
version can still tell if they're covered.

| game | validated versions | regression-suite coverage |
|---|---|---|
| **Europa Universalis IV** | 1.37.5 | full |
| **Stellaris** | 4.3.5 | full |
| **Imperator: Rome** | 2.0.5 | full |
| **Europa Universalis V** | 1.1.0 | full |
| **Hearts of Iron IV** | 1.18.1.0 | ~99.3% (37 known gaps allowlisted) |
| **Crusader Kings II** | 3.3.5.1 (EOL since Sep 2021) | parser-only; ~10% files fail (older pre-Jomini script conventions, not triaged). CK2's legacy launcher format means mod selection is also unsupported; only direct parse / round-trip works. |
| **Crusader Kings III** | — | placeholder — game module exists, no install validation yet |
| **Victoria 3** | — | placeholder — game module exists, no install validation yet |

## Installation

The gem isn't published, so build and install it locally:

```sh
git clone https://github.com/zgavin/paradoxical.git
cd paradoxical

# Pin to the project's Ruby and Rust. The .tool-versions file is read
# by mise, asdf, rtx, etc.
mise install   # or: asdf install

bundle install
bundle exec rake compile   # builds the Rust extension via rb_sys
bundle exec rake install   # installs the gem into your local gemset
```

Then in a consuming mod's `Gemfile`:

```ruby
gem 'paradoxical'
```

## Quick example

A mod-script that overrides one entry in EU5's auto-modifiers file:

```ruby
require "paradoxical"

paradoxical! game: "eu5", playset: "Standard", mod: "My Mod"

modifiers = parse_files "in_game/common/auto_modifiers/country.txt"

write "in_game/common/auto_modifiers/~my_overrides.txt" do
  lack = modifiers["lack_of_rivals"].dup.reset_whitespace!.single_line!
  lack.clear
  lack.key = "REPLACE:#{lack.key}"
  push! lack
end
```

What this does:

1. `paradoxical!` resolves the game slug to the matching
   `Paradoxical::EU5` module (which carries the steam id, executable,
   and jomini-version constants), builds a `Paradoxical::Game`,
   selects the active playset and mod, and pulls the helper methods
   into scope so the rest of the script can use them directly.
2. `parse_files` reads `country.txt` from the base game (or whichever
   earlier mod in the playset overrides it).
3. `write` emits a new file under your mod with the modified entry.
   The `~` prefix matters — PDS reads files in lexical order, so a
   `~` filename takes effect last.

Supported game slugs: `eu4`, `eu5`, `stellaris`, `imperator`, `hoi4`,
`ck2`, `ck3`, `v3`. Pass `root:` and/or `user_directory:` to
`paradoxical!` to override the default install / user paths. CK2's
legacy launcher format isn't supported, so passing `mod:` / `playset:`
silently no-ops on that game.

## Parser-only usage

If you just want the parser without the mod scaffolding:

```ruby
require "paradoxical"

doc = Paradoxical::Parser.parse(File.read("foo.txt"))

doc.each do |element|
  case element
  when Paradoxical::Elements::Property
    puts "property: #{element.key} = #{element.value}"
  when Paradoxical::Elements::List
    puts "list: #{element.key} (#{element.size} children)"
  end
end

# Edit and re-serialize. Round-trip is byte-identical for well-formed input.
puts doc.to_pdx
```

## Development

```sh
bundle exec rspec               # unit tests
bundle exec rake compile        # rebuild the Rust extension after grammar changes
bin/console                     # interactive REPL with paradoxical loaded
```

The parser regression smoke is env-var-gated. Point it at a real game
install to walk every parseable file:

```sh
PARADOXICAL_PARSE_SMOKE="$HOME/.steam/steam/steamapps/common/Europa Universalis IV" \
  bundle exec rspec --tag parse_smoke
```

## License

MIT — see [`LICENSE.txt`](LICENSE.txt).

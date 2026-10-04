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

- Runs on Ruby 4.0.3 + Rust 1.95.0 (pinned in `.tool-versions`).
- Round-trip preserves the original bytes — whitespace, comments, BOMs,
  CRLF line endings — so editing is non-destructive.
- The parser regression suite walks every script file in EU4 / EU5 /
  Stellaris / Imperator / HOI4 and their engine-default sibling dirs
  (22,646 files total) — all parse cleanly.
- See [`MODERNIZATION.md`](MODERNIZATION.md) for the phased plan and
  decision log.

## Supported games

Each row lists the game versions we test against. Older versions are
shown as a range; versions in the current minor line are listed
individually. Every listed version parses in the parse smoke, and is
kept in a local regression corpus so parser changes are re-checked
against all of them.

| game | supported versions | coverage |
|---|---|---|
| **Europa Universalis IV** | 1.37.5 | 100% |
| **Stellaris** | 2.4.1 – 4.4.6 <sup>[1](#note-1)</sup>, 4.5.0, 4.5.1 | 100% |
| **Imperator: Rome** | 2.0.5 | 100% |
| **Europa Universalis V** | 1.0.0 – 1.3.11 <sup>[2](#note-2)</sup>, 1.4.0 | 100% |
| **Hearts of Iron IV** | 1.8.2 – 1.18.3.0 <sup>[1](#note-1)</sup>, 1.19.0.0, 1.19.0.1, 1.19.1.0, 1.19.2.0, 1.19.3.0 | 100% |
| **Crusader Kings II** | 3.3.5.1 | ~90% <sup>[3](#note-3)</sup> |
| **Crusader Kings III** | 1.0.3 – 1.19.0.6 <sup>[1](#note-1)</sup>, 1.20.0.2, 1.20.0.3 | 100% |
| **Victoria 3** | 1.0.6 – 1.12.5 <sup>[1](#note-1)</sup>, 1.13.0, 1.13.1, 1.13.2, 1.13.3, 1.13.4, 1.13.5, 1.13.6, 1.13.7, 1.13.8, 1.13.9, 1.13.10, 1.13.11 | 100% |

1. <a id="note-1"></a> Within the range, only the final patch of each minor version is tested: the build a returning player would land on. Beta patches aren't tested. The range starts at the first build that ships `launcher-settings.json`, which is how the game's version is detected.
2. <a id="note-2"></a> Every build in the range is tested, including open-beta patches.
3. <a id="note-3"></a> EOL since Sep 2021. Parser-only; the ~10% of files that fail use older pre-Jomini script conventions, not yet triaged. CK2's legacy launcher format means mod selection is also unsupported; only direct parse / round-trip works.

Paradox's version numbering has its quirks (skipped numbers, unlisted
hotfixes, reused checksums). [PATCH_DISCREPANCIES.md](PATCH_DISCREPANCIES.md)
records the ones we've run into.

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
`paradoxical!` to override the default install / user paths. If your
Steam library lives somewhere other than the platform default, pass
`steam_dir:` (the folder containing `steamapps`, e.g.
`steam_dir: "/var/.steam"`); game installs and workshop mods are both
found under it. CK2's
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

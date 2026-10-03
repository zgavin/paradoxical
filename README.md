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

The "supported versions" column lists every patch level we know
about. New entries get added as Paradox ships patches; older entries
stay so users on a back version can still tell if they're covered.
Completed minor lines are collapsed to `<minor>.x`; an in-progress
line lists its individual builds instead, and footnotes carve out any
builds within a range that weren't run or can no longer be restored.

| game | supported versions | coverage |
|---|---|---|
| **Europa Universalis IV** | 1.37.5 | 100% |
| **Stellaris** | 2.4.1, 2.5.1, 2.6.3, 2.7.2, 2.8.1, 3.0.4, 3.1.2, 3.2.2, 3.3.4, 3.4.5, 3.5.3, 3.6.1, 3.7.4, 3.8.4, 3.9.3, 3.10.4, 3.11.3, 3.12.5, 3.13.2, 3.14.1592653, 4.0.23, 4.1.7, 4.2.4 <sup>[1](#note-1)</sup><br>4.3.x <sup>[1](#note-1)</sup><br>4.4.x <sup>[2](#note-2)</sup><br>4.5.0, 4.5.1 <sup>[3](#note-3)</sup> | 100% |
| **Imperator: Rome** | 2.0.5 | 100% |
| **Europa Universalis V** | 1.0.x <sup>[4](#note-4)</sup><br>1.1.x <sup>[5](#note-5)</sup><br>1.2.x<br>1.3.0, 1.3.2, 1.3.4, 1.3.6, 1.3.8, 1.3.10, 1.3.11 <sup>[6](#note-6)</sup><br>1.4.0 <sup>[6](#note-6)</sup> | 100% |
| **Hearts of Iron IV** | 1.8.2, 1.9.3, 1.10.8, 1.11.13, 1.12.14, 1.13.7, 1.14.10, 1.15.4, 1.16.10, 1.17.5.2 <sup>[7](#note-7)</sup><br>1.18.x.x<br>1.19.0.0 <sup>[8](#note-8)</sup>, 1.19.0.1, 1.19.1.0, 1.19.2.0, 1.19.3.0 | 100% |
| **Crusader Kings II** | 3.3.5.1 | ~90% <sup>[9](#note-9)</sup> |
| **Crusader Kings III** | 1.20.0.3 | 100% |
| **Victoria 3** | 1.13.11 | 100% |

Every listed version is smoke-validated except where a note says otherwise.

1. <a id="note-1"></a> Before 4.3, only the final patch of each minor version is covered: the build a returning player would land on. 2.4.1 is the floor, the first build that ships `launcher-settings.json`, which is how the version is detected. Some final patches are missing from the wiki's patch list: 3.0.4, and 3.14.1592653 (3.14 patches add a digit of pi rather than incrementing). Within 4.3.x, smoked coverage spans 4.3.5–4.3.7; 4.3.6 itself was not run — a same-day emergency hotfix superseded it with 4.3.7 first.
2. <a id="note-2"></a> Within 4.4.x, smoked coverage is 4.4.1, 4.4.3, 4.4.4, 4.4.5, and 4.4.6; 4.4.0 was skipped by Paradox and the 4.4.2 hotfix wasn't run — 4.4.3 superseded it shortly after and the same files parse clean, so those builds are claimed against 4.4.3/4.4.4/4.4.5.
3. <a id="note-3"></a> 4.5.x is an in-progress line, so its builds are listed individually. The 4.5 "Cygnus" open beta wasn't run.
4. <a id="note-4"></a> Every public 1.0.x build is smoked: the 1.0.0 launch build and 1.0.2–1.0.11. Paradox never shipped a 1.0.1.
5. <a id="note-5"></a> Includes the 1.1.0–1.1.8 open beta, all on Steam's `1.1.0` branch, as well as the 1.1.9–1.1.10 releases. 1.1.3's forum post repeats 1.1.2's checksum; its build is `d568`, the only branch build between 1.1.2 and 1.1.4.
6. <a id="note-6"></a> 1.3.x builds are listed individually rather than as a range: 1.3.0–1.3.10 were the open beta, with 1.3.10 doubling as the first official (non-beta) release, and subsequent releases are official builds. Within the beta, 1.3.0 was the initial open beta; 1.3.1, 1.3.3, 1.3.5, 1.3.7, and 1.3.9 were skipped by Paradox; and 1.3.2, 1.3.4, 1.3.6, 1.3.8, and 1.3.10 are the smoked beta patches. Every 1.2.0+ `BUILD_VERSION_MAP` entry keys on the disk-checksum suffix read from the install, since Paradox obfuscates the publicly-displayed checksum from 1.2.0 on (1.3.6 had no official checksum at all — in-game value `872e`; 1.3.8's is `98b8`, 1.3.10's is `c764`, 1.3.11's is `b08d`). 1.4.0 opens the open beta for the eventual 1.4 release (public checksum `592b`), so 1.4.x builds are listed individually the same way.
7. <a id="note-7"></a> Before 1.18, only the final patch of each minor version is covered: the build a returning player would land on. 1.8.2 is the floor, the first build that ships `launcher-settings.json`, which is how the version is detected. Smoked 1.18 builds are 1.18.1.0, 1.18.2.0, and 1.18.3.0.
8. <a id="note-8"></a> 1.19.0.0 shipped for ~2 days before the 1.19.0.1 hotfix replaced it. It can't be restored through Steam's beta branches, but its depot manifests can still be downloaded directly, which is how it was smoked.
9. <a id="note-9"></a> EOL since Sep 2021. Parser-only; the ~10% of files that fail use older pre-Jomini script conventions, not yet triaged. CK2's legacy launcher format means mod selection is also unsupported; only direct parse / round-trip works.

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

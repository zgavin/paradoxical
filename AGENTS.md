# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this project is

Paradoxical is a Ruby gem for parsing, editing, and re-serializing the proprietary script files used by Paradox Interactive games (EU4, Stellaris, Imperator: Rome, EU5). It exposes a Ruby DSL for writing mods that compile to those script files. The parser is Rust (pest grammar); the rest is Ruby.

This is a personal long-term project, not a production library. Quality, consistency, and the maintainer's enjoyment matter more than ship-fast pragmatism. Deep refactors are welcome where they pay down real fragility.

## Repo layout

```
ext/paradoxical/           Rust extension (built via rb_sys)
  Cargo.toml               Rust crate manifest
  Cargo.lock               Pinned Rust deps
  extconf.rb               rb_sys/mkmf bridge — generates Makefile that runs cargo
  src/
    lib.rs                 FFI entry point + script parser glue
    script.pest            Grammar for the Paradox script language
    search.rs / search.pest  Secondary parser for the search DSL
lib/paradoxical/
  parser.rb                Thin Ruby module the Rust extension binds onto
  file_parser.rb           File IO, caching, encoding/BOM handling
  game.rb                  Game-level entry: install/user dirs, mod loading
  mod.rb                   A single mod (zipped or directory)
  builder.rb               The DSL surface (`l`, `p`, `v`, `pdx_if`, …)
  editor.rb                Higher-level mutation helpers
  helper.rb                Misc helpers
  search.rb / search/      Search DSL implementation
  elements/                AST node classes, with whitespace preservation
    document.rb, list.rb, property.rb, value.rb, comment.rb, node.rb
    primitives/            String, Integer, Float, Date, Color, etc.
    concerns/              Shared mixins (Arrayable, Searchable, Impersonator)
  paradoxical.so           Compiled native extension (output of `rake compile`)
paradoxical.gemspec        Ruby gem manifest (declares `ext/paradoxical/extconf.rb`)
Rakefile                   `rake compile` builds the extension via rb_sys
MODERNIZATION.md           The current plan and decision log
```

## Off-repo references

These are not in this repository but are essential context. Never copy their contents in.

- **Game installs** (read-only references for understanding script syntax):
  `~/.steam/steam/steamapps/common/{Europa Universalis IV, Stellaris, ImperatorRome, Europa Universalis V}` — chronological order; EU5 has the newest dialect.
- **Example consumer of the gem:**
  `~/.pdx/Europa Universalis V/mod/PancakeTaco's Mod` — Ruby in `scripts/ruby/`, generated `.txt` output in the other top-level directories. Used as a manual integration smoke test today; will become the off-repo integration corpus in MODERNIZATION.md phase 1.

## Current state

The codebase is fragile by the maintainer's own assessment:

- Pinned to **rutie 0.0.4** for Ruby↔Rust FFI; rutie is abandoned and Ruby 3 support is held together by local hacks.
- `ext/paradoxical/Cargo.toml` has unpinned `pest = "*"` and `pest_derive = "*"`.
- Rust pinned to **1.67.1** in `.tool-versions` — newer rustc hard-errors on `let rule = pair.as_rule()` shadowing in `ext/paradoxical/src/search.rs`.
- Ruby deps lag several majors (activesupport 5, rubyzip 1, rake 10).
- No unit tests yet (just a trivial version spec); the PancakeTaco round-trip harness is local-only. No type signatures. README is the gem template boilerplate.

See **MODERNIZATION.md** for the phased plan to address all of the above. Read it before starting non-trivial work.

## Conventions

- Match the existing terse, informal commit message style (e.g. "Europa Universalis V updates", "Stellaris 3.6 updates").
- The Ruby code uses `do … end` blocks, `then` after multi-line conditionals, and tabs in some files / spaces in others — match each file's existing style rather than reformatting.
- `activesupport` idioms (`present?`, `blank?`, `try`) are used throughout; keep them.
- The Rust extension constructs Ruby class instances via `Module::from_existing(...).get_nested_module(...).get_nested_class(...)`. This is rutie-specific and will simplify when phase 2 lands.

## Workflow rules

- **PR-driven flow.** All non-trivial work goes through a PR against `master`. The agent opens the PR with `gh pr create`; the maintainer reviews and merges. Strict serial — wait for each PR to merge before starting the next sub-phase.
- **Branch naming.** Use `phase-N/letter/description` for MODERNIZATION.md phase work (e.g. `phase-2/a/rb-sys-build`). For ad-hoc work that isn't tied to a phase, use `chore/description`, `feat/description`, or `fix/description` — semver-style prefixes. In a professional context the maintainer would use a ticket ID prefix instead (e.g. `SC-1234/refactor-foo`); this project's MODERNIZATION.md plays that role.
- **Don't commit Paradox-owned files.** Game data and game-format files belong off-repo regardless of how convenient they'd be as fixtures. PancakeTaco's Mod is the maintainer's authorship but its inputs/outputs are too entangled with game data to ship safely.
- **Tests first for non-trivial migrations.** The whitespace/BOM/encoding round-trip behavior is easy to break silently. If MODERNIZATION.md phase 1 isn't done yet, raise it before starting phases 2+.
- **One concern per PR.** Especially for dependency bumps — they should land individually, low-risk first, so regressions stay bisectable.
- **Don't type the DSL.** The `method_missing` surface in `builder.rb` resists static typing; the public API classes are where types pay off.
- **Touching `script.pest`, `search.pest`, or YAML parsing?** Once the parser smoke from MODERNIZATION.md phase 1 lands, run it (`PARADOXICAL_PARSE_SMOKE=<game-root>`) against at least one real install before declaring the change done. Grammar regressions silently affect the long tail of game files we never look at directly.

## Open bugs worth knowing about

Fixed in MODERNIZATION.md phase 4, but worth flagging if encountered earlier:

- `lib/paradoxical/builder.rb:196` and `:201` both define `check_galaxy_setup_value`; the second silently overrides the first.
- `lib/paradoxical/builder.rb:221` and `:229` reference a bare `mult` identifier; should be the string `'mult'`.

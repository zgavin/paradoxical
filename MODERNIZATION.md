# Modernization Plan

A long-term plan for modernizing Paradoxical, written down so we can pick it up across sessions without re-deriving it. This is a living document — update phases as they finish and adjust ordering when reality intervenes.

## Goal

Bring Paradoxical to a state where it:

- Compiles and runs cleanly on current Ruby and Rust toolchains, without the rutie/Ruby-3 hacks that currently hold it together.
- Has a real test suite (unit + integration) so future changes can land with confidence.
- Has typed public APIs and runnable, documented examples.
- Has internally consistent APIs, with game-specific helpers scoped to game-specific namespaces instead of polluting the global builder.

## Current state (2026-04)

- Ruby gem with a Rust extension (parser + search parser).
- Rust→Ruby FFI uses **rutie 0.0.4** (Ruby gem) + **rutie 0.8.4** (Rust crate). Rutie is effectively abandoned; Ruby 3 support exists only via local hacks.
- Pest grammar versions are unpinned (`pest = "*"`, `pest_derive = "*"` in `Cargo.toml`).
- `Rakefile` still references `helix_runtime`, a leftover from before the Rust rewrite.
- Ruby deps lag several majors: activesupport 5, rubyzip 1.x, rake 10, sqlite3 1.3.
- No tests. No type signatures. README is the boilerplate gem template.
- The DSL is `method_missing`-driven and game-aware via a `Paradoxical.game` global; some game-specific behavior (e.g. `check_galaxy_setup_value` for Stellaris, `is? "eu4"` checks in the variable DSL) is mixed into the shared builder.

## Phases

Numbering reflects intended ordering; each phase is its own PR (or PR series). Phase 4 is intentionally empty — Rust idiom changes ride along with phase 2.

### 1. Test harness

Land before any migration so we have a regression net.

- **Unit tests**, in-repo, against hand-written synthetic fixtures under `spec/fixtures/`. Cover every `script.pest` rule explicitly: each operator, each primitive (color, percentage, date, float, integer, boolean, every string variant), `gui_kind` / `gui_type` / `scripted_kind` branches, mixed/array/keyless lists, BOM, CRLF/LF, and round-trip whitespace preservation.
- **Integration tests**, off-repo, against a real install. The path is supplied via env var (e.g. `PARADOXICAL_INTEGRATION_ROOT` for game data, `PARADOXICAL_EXAMPLE_MOD` for `~/.pdx/Europa Universalis V/mod/PancakeTaco's Mod`); tests `skip` when unset. CI runs unit tests only.
- Treat PancakeTaco as a regression baseline, not a correctness baseline — it was written for gameplay, not to exhaust the grammar.
- **Never commit Paradox files.** Even snippets risk being derivative. Hand-written synthetic fixtures only.

### 2. rutie → magnus

The single biggest unlock for Ruby 3 compatibility without hacks.

- Replace the `rutie` Rust crate with [`magnus`](https://github.com/matsadler/magnus) (and `rb-sys` for the build glue).
- Drop the `rutie` Ruby gem dependency from `paradoxical.gemspec`.
- Pin `pest` and `pest_derive` to a specific 2.x minor in `Cargo.toml`.
- Delete the `helix_runtime` reference from `Rakefile` and replace the build task with `rb_sys`-driven equivalents.
- Keep Rust logic identical; this is an FFI swap, not a rewrite. Idiomatic-Rust improvements come along for free (one-time class lookups instead of `Module::from_existing(...).get_nested_module(...).get_nested_class(...)` chains everywhere).

### 3. Dependency bumps

One PR per dependency, in roughly increasing order of risk:

1. `rake` 10 → 13
2. `sqlite3` 1.3 → current
3. `rubyzip` 1.x → 2.x
4. `activesupport` 5 → 7/8 (highest deprecation surface; do last with everything else green).

Bundler and Ruby itself bump alongside as needed.

### 4. (Reserved — folded into phase 2)

Rust idiom uplift was originally a separate phase; the magnus port subsumes most of it. Don't add work here for its own sake.

### 5a. Bug fixes and dead code

Cleanup that's safe once we have tests but doesn't change shape:

- `lib/paradoxical/builder.rb:196` and `:201` both define `check_galaxy_setup_value`; the second silently overrides the first.
- `lib/paradoxical/builder.rb:221` and `:229` reference a bare `mult` identifier in `add_resource` / `remove_resource`; almost certainly meant to be the string `'mult'`.
- `Rakefile`'s `helix_runtime` import (handled in phase 2 if not earlier).
- Boilerplate `README.md` content.

### 5b. Game-namespaced DSLs

Restructuring, not just cleanup. Larger and worth its own PR.

- Move game-specific DSL helpers into `Paradoxical::Stellaris::DSL`, `Paradoxical::EU4::DSL`, `Paradoxical::EU5::DSL`, `Paradoxical::ImperatorRome::DSL` modules.
- The shared `Paradoxical::Builder` extends the appropriate module based on `Paradoxical.game`, mirroring the existing `extend(jomini_version == 1 ? SqliteConfig : JsonConfig)` pattern in `lib/paradoxical/game.rb:33`.
- `check_galaxy_setup_value`, `resource_stockpile_compare`, `add_resource`/`remove_resource` (Stellaris); the `is? "eu4"` branch in the `set_variable` family (EU4); etc., move into their respective modules.
- The global builder stops carrying every game's vocabulary.

### 6. RBS types

- Type the public surface: `Paradoxical::Game`, `Paradoxical::Mod`, `Paradoxical::Elements::Document`, `Paradoxical::Elements::Node` and subclasses, `Paradoxical::Elements::Primitives::*`.
- Leave the builder/DSL as `untyped` — `method_missing` fundamentally resists static typing and forcing it gives users no real value.
- Use Steep with strict mode on the typed files only.

### 7. Documentation

- YARD `@example` blocks throughout the public API and the DSL. Where practical, run them as tests (yard-doctest or a small custom runner) so docs and tests can't drift.
- A real README (replace boilerplate) covering installation, supported games, a small worked example, and pointers to deeper docs.

## Decision log

Captured here so we don't re-litigate them.

- **Tests before migration.** Without a regression net, FFI/dep migrations silently break subtle behavior (whitespace preservation, BOM, `single_line!`, encoding round-trips, `method_missing` dispatch).
- **magnus over rutie or rolling our own.** rutie is abandoned; rolling our own reinvents what magnus already solved.
- **Synthetic fixtures + env-var-gated integration.** Avoids any question of shipping Paradox-owned data.
- **One PR per dep bump.** Activesupport especially is high-risk; isolating the changes makes regressions trivially bisectable.
- **No type coverage on the DSL.** The metaprogramming-heavy `method_missing` surface costs more in friction than it returns in safety.
- **Game-namespaced DSL via mixin.** Mirrors the existing jomini-version dispatch in `Game`, avoids inheritance gymnastics.

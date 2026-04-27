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

Originally a single phase intended to land entirely before phase 2. Reordered to interleave with phase 2 once we realized that exercising the test suite in CI requires the Rust extension to load, which is exactly what phase 2 fixes. See decision log.

#### 1a. Scaffolding (landed)

RSpec wired up, `.tool-versions` pinning Ruby 3.2.0, GitHub Actions CI, a trivial version spec that sidesteps the rutie load. CI green.

#### 1b. PancakeTaco round-trip harness — local-only baseline before phase 2

- Walks every parseable file under `PARADOXICAL_EXAMPLE_MOD` (`~/.pdx/Europa Universalis V/mod/PancakeTaco's Mod`), skipping `scripts/ruby/`; for each: parse → re-serialize → assert byte-equal with the original. `.txt` / `.gui` / `.gfx` go through `Paradoxical::Parser`; `.yml` through `Paradoxical::Elements::YAML`.
- Strictest assertion that doesn't require AST-shape correctness — directly exercises the parse/serialize boundary that phase 2 is about to swap.
- `:integration` tagged, env-var-gated, skipped in default `rspec`. CI never sees it. Run locally before the magnus port to baseline, then again after to confirm parity.
- Allowlist hook (`spec/fixtures/round_trip_allow.yml`) for files that genuinely don't round-trip today; populate lazily.

#### 1c. Unit fixtures + parser smoke — after phase 2

Both require the Rust extension to be loadable in CI, which phase 2 enables.

- **Unit tests**, in-repo, against hand-written synthetic fixtures under `spec/fixtures/`. Cover every `script.pest` rule explicitly: each operator, each primitive (color, percentage, date, float, integer, boolean, every string variant), `gui_kind` / `gui_type` / `scripted_kind` branches, mixed/array/keyless lists, BOM, CRLF/LF, and round-trip whitespace preservation. CI default suite.
- **Parser smoke**, off-repo, env-var-gated (e.g. `PARADOXICAL_PARSE_SMOKE=<game-root>`). Walks every script file under a game install and reports parse success/failure. No assertions beyond "did it raise" — purely a canary against grammar regressions in our code and patch-day drift in the games. Implementation rules:
  - Collect-don't-fail-fast: aggregate all failures into a single report (path + first line of error) instead of bailing on the first.
  - Parallelize per-game and per-file; install trees are tens of thousands of files.
  - Filter strictly by extension *and* location — game data ships non-script `.txt` files in places like `music/`.
  - Plumb `encoding:` the same way real callers do, otherwise we'll get false negatives on Latin-1-flavored files.
  - Run as a separate rake task or RSpec tag, never the default suite. CI never sees it.
  - Expect to need a per-game allowlist (`spec/fixtures/parse_smoke_allow_<game>.yml`) for genuinely unparseable files — build it lazily as cases come up. A previously-failing file that *starts* passing is also signal: update the allowlist and note the cause.

#### Caveats (apply to all of the above)

- Treat PancakeTaco as a regression baseline, not a correctness baseline — it was written for gameplay, not to exhaust the grammar.
- **Never commit Paradox files.** Even snippets risk being derivative. Hand-written synthetic fixtures only.

### 2. rutie → magnus

The single biggest unlock for Ruby 3 compatibility without hacks. Originally split into 2a/2b/2c/2d; 2c absorbed into 2b once we realized Cargo can't carry both `rutie` and `magnus` at the same time without ABI conflicts and `Init_paradoxical` initializes both the script and search parsers in one call. See decision log.

#### 2a. rb_sys build system, standard native-ext loading (landed)

Build-system-only swap. `helix_runtime` Rakefile and `Rutie.new(:paradoxical).init` loader replaced with `rb_sys` + standard `require 'paradoxical/paradoxical'`. Rust pinned to 1.67.1 via `rust-toolchain.toml`. No FFI changes — `rutie` still the underlying crate.

#### 2b. Port the Rust extension to magnus (absorbs 2c)

- Replace the `rutie` Rust crate with [`magnus`](https://github.com/matsadler/magnus) in `ext/paradoxical/Cargo.toml`. magnus uses `rb-sys` underneath, which is already there via the build system.
- Bump Rust toolchain to a current stable (rutie's pin was the source-level constraint; magnus has no such issue).
- Pin `pest` and `pest_derive` to a specific 2.x minor in `Cargo.toml` (Cargo.lock will refresh as part of this PR anyway).
- Port `ext/paradoxical/src/lib.rs` and `ext/paradoxical/src/search.rs` together — they share the Cargo.toml dep on rutie/magnus, so they have to flip together. Cache class lookups (one-time `const_get` instead of repeated `Module::from_existing(...).get_nested_module(...).get_nested_class(...)` chains).
- Acceptance: round-trip harness still 16/16.

#### 2d. Drop rutie remnants and tidy

- Drop the `rutie` Ruby gem dependency from `paradoxical.gemspec` (already inert post-2a).
- Drop any leftover `extern crate rutie` / unused imports.
- Any other small cleanup the magnus port flushed out.

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
- **Phase 1 split, interleaved with phase 2.** The original plan had phase 1 finish before phase 2. After landing the scaffolding (1a) we hit a wall: any further phase-1 work needs the Rust extension loadable in CI, which means reproducing the rutie/Ruby-3 hacks — i.e. fighting exactly what phase 2 deletes. New ordering is 1a → 1b (PancakeTaco round-trip, local-only, run before+after magnus) → phase 2 → 1c (unit fixtures + parse smoke, now CI-capable). Risk acceptance: the magnus port is more likely to break wholesale than to drift subtly on untouched paths, so a round-trip canary against the example mod is sufficient pre-migration coverage. If something breaks beyond what the harness catches, `git revert` to a working commit is the fallback.
- **magnus over rutie or rolling our own.** rutie is abandoned; rolling our own reinvents what magnus already solved.
- **2c absorbed into 2b.** Original plan split the magnus port across two PRs (lib.rs in 2b, search.rs in 2c). Cargo can't carry both `rutie` and `magnus` simultaneously without ABI conflicts (they're competing bindings to the same Ruby C API), and `Init_paradoxical` sets up both `Paradoxical::Parser` and `Paradoxical::Search::Parser` in one init call — so a half-ported state isn't really expressible. Cleaner to flip both files in one PR.
- **Synthetic fixtures + env-var-gated integration.** Avoids any question of shipping Paradox-owned data.
- **One PR per dep bump.** Activesupport especially is high-risk; isolating the changes makes regressions trivially bisectable.
- **No type coverage on the DSL.** The metaprogramming-heavy `method_missing` surface costs more in friction than it returns in safety.
- **Game-namespaced DSL via mixin.** Mirrors the existing jomini-version dispatch in `Game`, avoids inheritance gymnastics.

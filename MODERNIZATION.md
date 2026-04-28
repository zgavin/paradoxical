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

#### 1c. Parser smoke — after phase 2

Off-repo, env-var-gated (`PARADOXICAL_PARSE_SMOKE=<game-root>`). Walks every parseable file under a game install and reports parse success/failure — no assertions beyond "did it raise." Acts as a regression canary against grammar drift in our code and patch-day drift in the games.

Implementation choices:

- RSpec spec tagged `:parse_smoke`, gated in `spec/spec_helper.rb` so the default suite never runs it. One aggregated example walks all files; output is a summary line plus per-failure path + first-line-of-error.
- Builds on `Paradoxical::FileParser#parse_file` via a small wrapper class — same code path real callers use. (`FileParser#parse` previously rescued `ParseError` and called `exit`; the same PR fixed that to re-raise instead, since the rescue was development-time scaffolding from before the test suite existed.)
- **Basename exclusions** for non-script files that share an extension: `OFL.txt` (font licenses), `caesar_branch.txt`/`caesar_rev.txt`/`clausewitz_branch.txt`/`clausewitz_rev.txt` (engine version metadata), `credits.txt`, `license-fi.txt`, `checksum_manifest.txt`. The same basenames recur across PDX games.
- **Path-substring exclusions** for whole non-script directories: `/sound/banks/` (FMOD bank files: `Init.txt`, `MasteringSuite.txt`, `sb_*.txt`).
- **Per-game allowlist** at `spec/fixtures/parse_smoke_allow_<game>.yml` for real script files we don't parse yet. Different category from the basename/path exclusions: those are "not script"; allowlist is "script we don't handle." Baselines at landing:
  - `europa_universalis_iv`: 118 entries
  - `europa_universalis_v`: 60 entries
  - `stellaris`: 53 entries
  - `imperatorrome`: 16 entries
- **Per-game encoding fallback chain.** EU4 (jomini v1, 2013) is mostly Windows-1252 but a handful of files with non-Latin characters (Korean province names, Tengri events, Mamluk missions) are actually UTF-8 — so the smoke tries UTF-8 first and falls back to the per-game encoding (`Windows-1252` for EU4). Newer games stay UTF-8-only since they have no fallback configured. `PARADOXICAL_PARSE_SMOKE_ENCODING` overrides to a single forced encoding for diagnostic runs.
- Sequential walk; ~10s for EU5's 3000+ files, ~30s for EU4's 8000+. Parallelism deferred — the bottleneck is the parser itself which holds the GVL.
- `PARADOXICAL_PARSE_SMOKE_DUMP=<path>` writes every failing path to a YAML-shaped list. Useful for refreshing allowlist baselines without scraping truncated rspec output.

##### Known coverage gaps (future smoke enhancements)

- **Parse-only, no round-trip.** The smoke just calls `parse_file` and catches exceptions — it doesn't verify that parse → serialize → bytes-on-disk is byte-identical the way the PancakeTaco round-trip harness does for one mod. So a grammar change that turns out to alter serialization for some untouched file would slip past the smoke until someone hits that file in their actual workflow. Cost of fixing is roughly 2x runtime per file plus a separate "round-trip allowlist" for files that genuinely don't round-trip. Worth doing when grammar work surfaces a serialization-divergence regression we wish we'd caught.
- **YAML smoke not implemented.** Original phase-1c plan had `.yml` files going through `Paradoxical::Elements::Yaml` as a parallel smoke target. Deferred because the YAML path is pure Ruby (no Rust extension; no rutie→magnus risk surface), so the regression-canary motivation was weaker. Worth revisiting if the YAML serializer surface gets touched.

#### 1d. Unit fixtures + CI Rust build (landed)

- CI workflow now installs Rust 1.95.0 (`dtolnay/rust-toolchain` reads `rust-toolchain.toml`), uses `Swatinem/rust-cache@v2` for incremental cargo, and runs `bundle exec rake compile` before specs. ~50s per run after caching warms up. The `BINDGEN_EXTRA_CLANG_ARGS=-include stdbool.h` from `.cargo/config.toml` is still applied but is a no-op on `ubuntu-latest`'s default clang.
- Per-rule unit tests live in `spec/parser/` (not `spec/fixtures/` — fixtures are inline strings; small enough that source-of-truth is more readable next to the assertion). 71 examples across four files:
  - `primitive_spec.rb` (30): every primitive type — integer (positive, negative, +-prefixed, zero), float (positive, negative, leading-dot, trailing-dot), boolean, date (4-digit and 1-digit years, `to_date` round-trip), percentage, color (rgb + hsv with type/colors assertions), all string variants (unquoted, quoted, empty, localization, computation, escaped-computation). Plus all 7 operators.
  - `list_spec.rb` (15): empty, single-property, multi-property, nested, array (values only), mixed, keyless, all `gui_kind` keywords (types/template/blockoverride/block/layer), `gui_type`, `scripted_trigger`/`scripted_effect`.
  - `document_spec.rb` (19): top-level shape (empty, comment-only, mixed), accessor methods (`[]` by key, `value_for`, `keys`), comment text capture, byte-identical round-trip for ten well-formed inputs covering operators / nested lists / quoted strings / dates / irregular whitespace, plus a CRLF case.
  - `file_parser_spec.rb` (7): BOM stamping, CRLF/LF detection, path/encoding pass-through, re-raise-with-path-prefix on `ParseError` (covering the phase-1c FileParser fix).

#### Caveats (apply to all of the above)

- Treat PancakeTaco as a regression baseline, not a correctness baseline — it was written for gameplay, not to exhaust the grammar.
- **Never commit Paradox files.** Even snippets risk being derivative. Hand-written synthetic fixtures only.

### 2. rutie → magnus

The single biggest unlock for Ruby 3 compatibility without hacks. Originally split into 2a/2b/2c/2d; 2c absorbed into 2b once we realized Cargo can't carry both `rutie` and `magnus` at the same time without ABI conflicts and `Init_paradoxical` initializes both the script and search parsers in one call. See decision log.

#### 2a. rb_sys build system, standard native-ext loading (landed)

Build-system-only swap. `helix_runtime` Rakefile and `Rutie.new(:paradoxical).init` loader replaced with `rb_sys` + standard `require 'paradoxical/paradoxical'`. Rust pinned to 1.67.1 via `rust-toolchain.toml`. No FFI changes — `rutie` still the underlying crate.

#### 2b. Port the Rust extension to magnus, absorbs 2c (landed)

`rutie` Rust crate → `magnus` 0.7. Rust bumped 1.67.1 → 1.95.0 (rutie's source-level pin was the only thing holding us back). `pest`/`pest_derive` pinned to 2.7. `lazy_static` dropped in favor of `std::sync::LazyLock`. Class lookups go through cached `Lazy<RClass>` statics resolved via `ruby.get_inner(&LAZY)`. `.cargo/config.toml` sets `BINDGEN_EXTRA_CLANG_ARGS=-include stdbool.h` so rb-sys's bindgen step parses Ruby 3.2 headers cleanly. Round-trip harness 16/16 byte-equal post-port.

#### 2d. Drop rutie remnants and migrate to kwargs

- Migrate the `ivar_set` chains in `ext/paradoxical/src/lib.rs` to `magnus::kwargs!()` calls in `new_instance` so element constructors thread their data through Ruby's proper `initialize` signatures. This was rutie cruft — rutie had no kwargs support, so the original code worked around it by mutating ivars from outside. Net: Ruby `ArgumentError: unknown keyword` now fires loudly at construction time if anyone changes a Ruby class's signature without updating the Rust caller.
- Drop the `rutie` Ruby gem dependency from `paradoxical.gemspec` (inert since 2a).
- Refresh stale rutie-era comments in `spec/spec_helper.rb`.

#### Out of scope for 2d, deferred

- Search submodule kwargs migration. `ext/paradoxical/src/search.rs` still passes a positional `RHash` to `Paradoxical::Search::{Rule,PropertyMatcher,FunctionMatcher}` — the same rutie-era pattern. Migrating it requires changes on both Rust and Ruby sides, and there's no regression test for the search DSL today (PancakeTaco round-trip doesn't exercise `Paradoxical::Search`). Defer until phase 1c lands unit tests, then migrate with confidence.
- The "false-as-no-operator/no-kind" placeholder in `List`. The `operator`/`kind` getters on `Paradoxical::Elements::List` translate `false` to `nil` per a comment that blames rutie segfaults on nil. magnus handles nil fine, so the workaround is vestigial — but flipping it touches the Ruby side and warrants its own PR.

### 3. Dependency bumps

One PR per dependency, in roughly increasing order of risk:

1. `rake` 10 → 13
2. `sqlite3` 1.3 → current
3. `rubyzip` 1.x → 2.x
4. `activesupport` 5 → 7/8 (highest deprecation surface; do last with everything else green).

Bundler and Ruby itself bump alongside as needed.

### 4. Bug fixes, dead code, and parser-gap triage

Phase 1c's smoke captured 247 known parser failures across the four PDX games. Phase 4 attempts to shrink that baseline iteratively — fix a grammar issue, re-run the smoke, watch the per-game allowlists shrink, repeat — alongside the small Ruby/doc cleanups already on the list. Each grammar fix is its own PR with smoke re-run before merge.

#### 4a. Small Ruby cleanups

One small PR, mechanical edits:

- `lib/paradoxical/builder.rb:196` and `:201` both define `check_galaxy_setup_value`; the second silently overrides the first.
- `lib/paradoxical/builder.rb:221` and `:229` reference a bare `mult` identifier in `add_resource` / `remove_resource`; almost certainly meant to be the string `'mult'`.
- `Paradoxical::Elements::Primitives::String#is_quoted` is an `attr_reader` named like a flag rather than a predicate. Rename to `quoted?` for Ruby-idiomatic style; update callers and `RSpec.matcher`-friendly `be_quoted` assertions.

#### 4b. Grammar bugs already identified

One PR each. Smoke re-run after landing; per-game allowlists shrink for files that newly pass.

- **Keyless lists with bare values** — `points = { { 1 2 } { 3 4 } }` currently fails because `keyless_list` only accepts `expression*`. PDX city_data files (and likely several other patterns) use the bare-value form. Fix by widening `keyless_list` to accept values, or introducing a separate value-only keyless rule. Used to parse, likely regressed during EU5 grammar updates.
- **`&break_character` lookahead doesn't accept EOI** — `integer`/`boolean` rules silently fall through to `string` for fixtures without trailing whitespace. The trailing-`\n` fixtures in `spec/parser/primitive_spec.rb` are load-bearing for this reason. Fix by adding `EOI` to `break_character`.

#### 4c. Triage pass on remaining allowlists (landed)

Output: [MODERNIZATION_4C_TRIAGE.md](MODERNIZATION_4C_TRIAGE.md) — full per-cluster breakdown across all 222 remaining allowlist entries.

Categories used: (A) mis-categorized non-script (move to filters), (B) high-value grammar fixes that unblock many files at once, (C) game-specific grammar additions, (D) tricky / probably-won't-fix.

Top of the suggested 4d sequence:
1. Filter cleanup (~10 files). One small PR.
2. Non-ASCII identifiers in `unquoted_string` (~68 EU4 files; biggest single win).
3. `---` placeholder primitive (~37 EU4 files).
4. `hsv360` color format (22 EU5 files).
5. 4-component RGB / alpha channel (9 Stellaris files).

If items 1–5 land, total drops 222 → ~80. Diminishing returns thereafter. Triage doc has the full sequence and per-cluster reasoning.

#### 4d. Continue fixing root causes

Driven by 4c. Each fix is its own PR with smoke re-run. Continue while the effort/impact ratio stays good — typically "one PR unblocks 5+ files across 2+ games."

#### 4e. README rewrite

Independent of grammar work; can land any time. Replace the boilerplate gem template with a real README covering installation, supported games, a small worked example, and pointers to deeper docs (`AGENTS.md`, `MODERNIZATION.md`).

#### Exit condition

Phase 4 ends when remaining allowlist entries are either categorized as won't-fix or qualify as a new dedicated phase. The smoke baseline at exit becomes the new normal — anything that fails after isn't a phase-4 concern.

### 5. Game-namespaced DSLs

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

### 8. Richer primitive types

Open-ended and explicitly gated on "concrete need surfaces" — none of these are urgent. Stdlib-only by design: no third-party calendar/decimal/etc. gems, and no custom abstractions that downstream mod authors have to learn. See memory.

#### Float → fixed-precision (moved from former 4f)

`Paradoxical::Elements::Primitives::Float` stores Ruby `Float` (binary floating point). PDX games actually store decimals as base-10 fixed-precision integers with 3 decimal places (i.e. `1.234` is internally `1234`). DSL math on parsed decimals can drift due to binary-FP rounding. Real-world DSL math is rare so it hasn't bitten in practice. The right shape if/when this is tackled is a wrapper using stdlib `BigDecimal` (or just `Integer` × scale), with arithmetic operators preserving precision.

#### Game-aware `Date#to_pdx`

Add `Date#to_pdx` to `core_extensions.rb` so users can write a Ruby `Date` straight into a property and get a PDX-formatted string. Game-aware: validates per the current `Paradoxical.game`'s calendar rules and raises clearly on representable-but-invalid dates.

PDX calendar landscape (worth recording so future-us doesn't re-derive):

- **EU4 / EU5 / CK3 / HOI4 / Imperator: Rome** all use *Gregorian without leap years*. Stdlib `Date.new(1444, 2, 29)` succeeds but represents an in-game-invalid date; `Date#to_pdx` should `raise` for `month == 2 && day == 29`. Imperator additionally uses BC-shifted years (`-50`-style negatives), which `Date` represents fine.
- **Stellaris** uses 12 × 30 = 360 days. `Date` can't represent Feb 30, so `Date#to_pdx` for Stellaris dates beyond the stdlib-valid subset has to either: (a) raise with a clear "use `Primitives::Date` raw string" message, or (b) be served by a `Stellaris::Date` helper that lives in the game-namespaced module from phase 5. Honest asymmetry rather than a custom calendar abstraction.
- HOI4 and EU5 have hour-level granularity in-game but the script language doesn't expose it (per the maintainer), so date primitives stay day-resolution.

The implementation likely dispatches via the phase-5 game-namespaced modules — per-game calendar rules want to live with the rest of each game's quirks rather than as a switch in `core_extensions.rb`.

## Decision log

Captured here so we don't re-litigate them.

- **Tests before migration.** Without a regression net, FFI/dep migrations silently break subtle behavior (whitespace preservation, BOM, `single_line!`, encoding round-trips, `method_missing` dispatch).
- **Phase 1 split, interleaved with phase 2.** The original plan had phase 1 finish before phase 2. After landing the scaffolding (1a) we hit a wall: any further phase-1 work needs the Rust extension loadable in CI, which means reproducing the rutie/Ruby-3 hacks — i.e. fighting exactly what phase 2 deletes. New ordering is 1a → 1b (PancakeTaco round-trip, local-only, run before+after magnus) → phase 2 → 1c (unit fixtures + parse smoke, now CI-capable). Risk acceptance: the magnus port is more likely to break wholesale than to drift subtly on untouched paths, so a round-trip canary against the example mod is sufficient pre-migration coverage. If something breaks beyond what the harness catches, `git revert` to a working commit is the fallback.
- **magnus over rutie or rolling our own.** rutie is abandoned; rolling our own reinvents what magnus already solved.
- **2c absorbed into 2b.** Original plan split the magnus port across two PRs (lib.rs in 2b, search.rs in 2c). Cargo can't carry both `rutie` and `magnus` simultaneously without ABI conflicts (they're competing bindings to the same Ruby C API), and `Init_paradoxical` sets up both `Paradoxical::Parser` and `Paradoxical::Search::Parser` in one init call — so a half-ported state isn't really expressible. Cleaner to flip both files in one PR.
- **Phases renumbered after phase 4 went empty.** The original plan had phase 4 as "Rust idiom uplift" and 5a/5b as bug-fixes / game-namespaced DSLs. The magnus port (phase 2b) subsumed the Rust idiom work, leaving 4 reserved-but-empty next to 5a/5b. After 1a-d and 2a-d landed, 5a was renamed to 4 and 5b to 5 so the remaining work proceeds in clean numerical order. References to "5a"/"5b" in pre-renumber commits/PRs/AGENTS.md are historical.
- **Phase 8 added; Float deferral moved out of phase 4.** Phase 4 was originally going to absorb the "Float → fixed-precision" cleanup as a deferred 4f item, but the calendar-support discussion surfaced a parallel concern (game-aware `Date#to_pdx`) with the same shape — a primitive type wanting richer representation. Both moved to a new phase 8 explicitly gated on "concrete need surfaces," and explicitly stdlib-only (no external gems, no custom calendar/decimal abstractions). The reasoning: external gems can be abandoned (lesson from rutie), and downstream mod authors shouldn't have to learn a `Paradoxical::Calendar` abstraction when stdlib `Date` is what they already know.
- **Synthetic fixtures + env-var-gated integration.** Avoids any question of shipping Paradox-owned data.
- **One PR per dep bump.** Activesupport especially is high-risk; isolating the changes makes regressions trivially bisectable.
- **No type coverage on the DSL.** The metaprogramming-heavy `method_missing` surface costs more in friction than it returns in safety.
- **Game-namespaced DSL via mixin.** Mirrors the existing jomini-version dispatch in `Game`, avoids inheritance gymnastics.

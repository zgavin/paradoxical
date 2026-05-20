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

- Drives `paradoxical!` against an installed game's playset+mod (env vars: `PARADOXICAL_EXAMPLE_MOD`=mod display name, `PARADOXICAL_EXAMPLE_PLAYSET` defaults to `Standard`, `PARADOXICAL_EXAMPLE_GAME` defaults to `eu5`), then walks every parseable file under the resolved mod path (skipping `scripts/ruby/`); for each: parse → re-serialize → assert byte-equal. `.txt` / `.gui` / `.gfx` go through `Paradoxical::Parser`; `.yml` through `Paradoxical::Elements::YAML`. Going through `paradoxical!` rather than a hand-rolled FileParser wrapper means regressions in Game / Mod / launcher construction surface here too.
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
- ~~Sequential walk; ~10s for EU5's 3000+ files, ~30s for EU4's 8000+. Parallelism deferred — the bottleneck is the parser itself which holds the GVL.~~ Parallelized in a follow-up: pest's parse phase now runs inside `rb_thread_call_without_gvl` (via a small `nogvl` shim in `ext/paradoxical/src/nogvl.rs`), and the smoke spec uses a bounded `Etc.nprocessors` thread pool. Aggregate wall-clock 155s → 113s (~1.4x). Per-game speedup varies — Imperator/Stellaris/EU5/HOI4 hit ~1.8-2x, EU4 only ~1.1x. The bottleneck on EU4 isn't Ruby-side wrapper work (the surrounding `FileParser#parse_file` overhead is < 1 ms per file; pest parse averages ~9.5 ms per file) — it's the `document()` phase inside `Paradoxical::Parser.parse` itself, which reacquires the GVL to construct Ruby AST objects (Document, List, Property, etc.). For EU4's file mix that phase apparently dominates pest, capping parallel scaling. Override worker count with `PARADOXICAL_PARSE_SMOKE_WORKERS=N` (1 to bisect failures serially).
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

#### 2e. Search submodule kwargs migration (landed)

The Rust caller in `ext/paradoxical/src/search.rs` was still passing a positional `RHash` to `Paradoxical::Search::{Rule,PropertyMatcher,FunctionMatcher}` — the rutie-era pattern preserved through 2d. Each Ruby-side `initialize` carried the workaround `def initialize key, opts = {}, **kwargs` plus a `defaults.merge(opts).merge(kwargs)` deconstruction and a rutie-blaming comment.

Migration shape:
- Rust caller wraps the existing dynamically-built `RHash` in `KwArgs(options)` at each of the three `new_instance` sites. Conditional-presence semantics (e.g. `id` only set when there's an `#id` selector) preserved unchanged — Ruby-side defaults kick in via `id: nil` keyword defaults.
- Ruby `initialize` signatures replaced with native keyword args. Shape-mismatch errors now fire loudly via Ruby's `ArgumentError: unknown keyword` at construction time, per [[feedback_construct_via_initializer]].
- `Paradoxical::Search::PropertyMatcher` gained `attr_accessor :case_sensitivity` — the grammar parses the trailing `i`/`s` flag inside `[ … ]` and the Rust caller has been passing it for years, but the old Ruby initializer was silently dropping it (only destructured `operator:` and `value:`). Storing the field preserves the parsed information and keeps the Rust kwargs and Ruby signature in sync. `#matches?` still doesn't branch on it; case-folding lookups are a separate concern.

Discoveries along the way (folded into the same PR since they were surfaced by the new test coverage):
- **`pm_operator` grammar ordering bug.** `<=` was unreachable because pest tried `<` first in the alternation and greedily matched. Reordered so all two-char operators precede their one-char prefixes; mirrored the existing `>=` / `>` ordering. Caught by `spec/search/parser_spec.rb`.
- **`Paradoxical::Search.parse` `puts/exit` scaffolding removed.** Same shape that `FileParser#parse` carried until phase 1c — ParseError swallowed and `exit` called. Now re-raises. The integration tests rely on this to assert ArgumentError from `Searchable#search` with bad input.

Test coverage added at `spec/search/`: 105 examples across 5 files (parser end-to-end, Rule, PropertyMatcher, FunctionMatcher, Searchable integration). Full suite 288 → 393 examples post-PR.

#### 2f. List `false→nil` shim removal (landed)

`Paradoxical::Elements::List` carried a getter shim that translated `@operator == false` and `@kind == false` to `nil` on first read, per a comment blaming rutie segfaults on `Qnil` being reused as a Value. magnus has handled `nil` cleanly since 2b, so the workaround was vestigial.

Migration shape:
- Rust: `ext/paradoxical/src/lib.rs` initialized both locals as `ruby.qfalse().as_value()` and overwrote only when the source had a `kind` keyword or explicit operator. Swapped both to `ruby.qnil().as_value()` so the kwargs! call passes `nil` directly when the source omits them.
- Ruby: removed the `def operator` / `def kind` getter overrides in `lib/paradoxical/elements/list.rb`. `attr_accessor :key, :operator, :kind` provides the plain readers.

External behavior unchanged — `list.operator` / `list.kind` still return `nil` for absent and the parsed string when present. Round-trip preservation verified by `spec/parser/{list,document}_spec.rb` and the EU5 parse smoke (3415 files, 0 failures).

Phase 2's deferred list is now empty.

### 3. Dependency bumps (landed)

One PR per dependency, in roughly increasing order of risk:

1. `rake` 10 → 13 ✓
2. `sqlite3` 1.3 → 2.0 ✓
3. `rubyzip` 1.x → 2.3 ✓ (rubyzip 3.0 imminent — gemspec is pinned `~> 2.3` to avoid surprise breakage)
4. `activesupport` 5 → 8.0 ✓

Ruby 3.2.0 → 4.0.3 and bundler 2.4.1 → 4.0 landed alongside once magnus 0.7 → 0.8 cleared the FFI side. `required_ruby_version >= 4.0` set in the gemspec; `.rubocop.yml` `TargetRubyVersion` follows. Rust pinned at 1.95.0 (lifted from 1.67.1 during phase 2b). Performance for the parser smoke is unchanged — it's GVL-bound on Rust-side parsing, not interpreter-bound — but Ruby-side code paths (search, builder DSL) gain Ruby 4's allocation improvements.

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

#### 4d. Continue fixing root causes (landed)

Triage's suggested sequence largely held: filter cleanup, B1–B5 grammar additions (non-ASCII identifiers, `---` placeholder, hsv360, alpha colors, negative-prefixed parameters), then C1–C9 (load_template, BC dates, hex/cylindrical, parameter blocks, code blocks, mid-file BOMs, etc.). Several follow-ons that surfaced during smoke iteration: case-insensitive `gui_kind`, `local_template`, top-level bare identifiers, top-level keyless lists, `keyed_kind_head` (`key = kind { body }`), `parameter_block` body widening, `unquoted_string` `@$` / `@@` / `'` sigils, C-style `//` comments, `f`-suffixed floats, trailing `;`.

Refactors rode along where they paid down complexity: `keyable_list` / `array_list` / `mixed_list` collapsed into one `list` rule with a named `list_head` alternation; the kind-position discriminator generalized from a content check (`kind == "LIST"`) into a parse-time `kind_after_key` flag; `bare_head` added with a numeric-rejection lookahead so `0.5 { … }` keeps its pair semantics; `cylindrical` peeled out of the `color` rule (it was always a camera property, not a color, and the unified `list` is its proper home).

Final allowlist totals at exit (down from 247 at phase-1c baseline / 222 at the 4c triage):

| game | start | exit | parsed clean |
|---|---:|---:|---:|
| EU4 | 118 | 0 | 8375 / 8375 |
| EU5 | 60 | 3 | 3033 / 3036 |
| Stellaris | 53 | 1 | 2989 / 2990 |
| Imperator | 16 | 1 | 1976 / 1977 |
| **total** | **247** | **5** | **16373 / 16378** |

The 5 remaining are all malformed-input files (extra/missing `}` in source) — Category D from the triage:

- EU5 `coalition.gui`, `crusade.gui`, `city_tooltips.gui` — extra `}` near EOF.
- Stellaris `scripted_loc_ruloc.txt` — missing `}` at EOF.
- Imperator `posteffect_volumes.txt` — extra `}` (47 opens, 48 closes).

PDX engine tolerates these; the right home for them is `Paradoxical::FileParser#corrections`, expanded with per-game-version default fix-ups that mutate the raw bytes before parsing — keeping the grammar strict rather than silently absorbing typos. That work is Phase-5-ish; not a phase-4 concern.

#### 4e. README rewrite (landed)

Boilerplate gem template replaced. README now covers what Paradoxical is, current state and pinned toolchain versions, a per-game support table (versions / coverage / notes), installation, a small worked example with `paradoxical!`, and pointers to deeper docs (`AGENTS.md`, `MODERNIZATION.md`). Kept short — ~140 lines — since this is a personal-project gem with one consumer, not a published library that needs exhaustive reference docs.

#### 4f. HOI4 onboarding + encoding simplification (landed)

Post-exit cleanup that brings HOI4 into the smoke and simplifies encoding handling along the way.

**HOI4 added to the smoke baseline** — 37 allowlisted failures at first run, 0 at exit. Drove out via filter cleanup, per-game `CORRECTIONS` for malformed-input files (16 missing `}`, 1 extra `}`, 1 stray-character typo in `events/WUW_Germany.txt`), grammar additions (curly quotes in `quoted_string`; `,` separators, mid-head comments, and the `-name` sigil in `unquoted_string`).

**Encoding handling simplified.** Per-game `ENCODING_FALLBACKS` constants and `Game#parse_file`'s retry loop replaced with a universal Windows-1252 fallback at the FileParser layer: `FileParser#read` reads UTF-8 by default and falls back to Windows-1252 when bytes aren't valid UTF-8 via a new `enforce_encoding!` helper. An explicit `encoding:` pin disables the fallback and raises if the bytes don't match. BOM detection in `parse_file` is gated on `encoding == Encoding::UTF_8` since the BOM is a UTF-8-specific marker. `Mod#read` runs zip-extracted bytes through the same validator so archived mods get the fallback for free.

**All five game smokes now empty-allowlist clean: 22,057 / 22,057 files parse** (eu4 8375, eu5 3242, stellaris 2992, imperator 2118, hoi4 5330).

**Corrections triage methodology.** Tail-fixup corrections (append `\n}\n`, or strip a trailing `}`) often parse but produce semantically wrong AST when the real defect is mid-file — an orphan `{` mid-content gets "balanced" by stripping a legitimate structural close, leaving subsequent content nested under the wrong scope. To distinguish a genuine tail defect from a mid-file orphan, build a brace-depth trace of the file:

1. Strip line comments (`#…`) and quoted-string contents (defects rarely live inside either, and counting their braces poisons the trace).
2. Walk the cleaned bytes character-by-character tracking depth (`{` = +1, `}` = −1).
3. Read two signals:
   - **EOF depth.** +1 = one unclosed open; −1 = one extra close.
   - **Minimum depth.** If depth ever dips below 0, a stray `}` closed something it shouldn't have; the line where it dipped is the defect site.

A genuine tail-append case traces as EOF depth = 1, min = 0, last non-blank lines still at depth ≥ 1 — the file ends mid-outer-block, engine implicitly closes at EOF, our `\n}\n` append is structurally correct. A genuine trailing-extra-`}` case traces as EOF depth = −1, min = −1 at the very last `}` line. Mid-file orphans either dip negative earlier in the file or end with EOF depth > 0 while the last non-blank line is at depth 0 (structure visually closed; an earlier open never matched).

**Triage findings.** All 17 HOI4 brace corrections (16 APPEND_BRACE + 1 STRIP_TRAILING_BRACE) trace as legitimate tail defects. Three EU5/Imperator corrections that were originally written as tail-fixups (`crusade.gui`, `coalition.gui`, `posteffect_volumes.txt`) turned out to be mid-file orphans and were re-anchored on unique surrounding substrings in PR #53. `eu5/city_tooltips.gui` (genuine trailing-`}`) and `stellaris/scripted_loc_ruloc.txt` (genuine missing-tail-`}`) stayed as before.

#### Exit condition: met (2026-05-03)

Phase 4 ends when remaining allowlist entries are either categorized as won't-fix or qualify as a new dedicated phase. The smoke baseline at exit becomes the new normal — anything that fails after isn't a phase-4 concern.

### 5. Game-namespaced DSLs

Restructuring, not just cleanup. Split across three sub-PRs.

#### 5a. Game modules + `paradoxical!` entry point (landed)

Each PDS title gets its own module under `Paradoxical::*` carrying the
game's constants (`NAME`, `SLUG`, `EXECUTABLE`, `STEAM_ID`,
`JOMINI_VERSION`), a `DSL` submodule (empty for now; populated in 5b),
and a `CORRECTIONS` hash (empty for now; populated in 5c).
`Paradoxical::Games` is a small registry — game modules register
themselves on require, and `Games.find(slug)` resolves slug strings.

A new top-level `paradoxical!` method is the single entry point for
mod scripts:

```ruby
require "paradoxical"
paradoxical! game: "eu5", playset: "Standard", mod: "My Mod"
```

It resolves the slug, builds the `Game` from the module's constants,
selects playset+mod, mixes the per-game DSL into Builder, registers
per-game default corrections on the active game, and pulls Helper into
Object so the rest of the script can call `parse_files` / `write` /
etc. without an explicit include. `root:` and `user_directory:` remain
available for advanced callers.

`Helper#game!` / `playset!` / `mod!` removed — `paradoxical!` replaces
them. No backwards-compat shim because PancakeTaco is the only
consumer (the maintainer is the only user).

8 games registered in chronological release order: CK2, EU4, HOI4,
Stellaris, Imperator: Rome, CK3, Victoria 3, EU5. CK2/CK3/V3/HOI4 are
placeholders — constants only — to round out the past ~15 years of
PDS titles.

#### 5b. DSL helpers per game (landed)

Game-specific DSL helpers moved off the shared `Paradoxical::Builder` into the matching `Paradoxical::Games::*::DSL` modules. `paradoxical!` wires the active game's DSL onto Builder via `prepend` (not `include`) so per-game methods *override* the base ones — load-bearing for the EU4 `set_variable` override, where the override needs to win over the game-agnostic definition for the same method name.

Concrete moves:
- **Stellaris** — `get_galaxy_setup_value`, `check_galaxy_setup_value`, `resource_stockpile_compare`, `add_resource`, `remove_resource`.
- **EU4** — the variable family (`set_variable` / `check_variable` / `change_variable` / `subtract_variable` / `multiply_variable` / `divide_variable` / `modulo_variable` / `round_variable_to_closest`) overrides the Builder base to emit `which = X` instead of `value = X` for non-numeric values. `export_to_variable` stayed on Builder — it always uses `value` so there's no per-game wrinkle.

Builder no longer carries any game's vocabulary; what remains is the game-agnostic base plus a brief comment at the variable-family override site pointing to where EU4's wrinkle lives.

#### 5c. Corrections registry + Game.new lockdown (landed)

**Per-game versioned corrections.** Each game module's `CORRECTIONS` hash is keyed by version: `{ "X.Y.Z" => { "path" => ->(data) { … } } }`. `Paradoxical::Games::Corrections.resolve` walks versions in ascending order, applies those `<=` the installed version, and supports per-path overrides — a `nil` at a later version unregisters a correction once Paradox patches the file.

**Version detection.** Each game module exposes `installed_version(game)`:
- EU4 / Stellaris / HOI4 / Imperator / CK3 / V3 share `Paradoxical::Games.read_launcher_version` (parses `rawVersion` from `launcher-settings.json`; helper searches `game.root` and `game.root.parent` for both `launcher-settings.json` and `launcher/launcher-settings.json` to handle install-layout variations).
- EU5 uses `read_build_checksum` against `binaries/checksum.txt` + a per-build `BUILD_VERSION_MAP`. Originally used `read_branch_version("caesar_branch.txt", …)` but that file proved unreliable: 1.1.10 reports as `release/1.1.0` (patch component dropped), and a later patch changed the format entirely. The build checksum is build-time-stamped, embedded inline in `eu5.exe`, and changes per Paradox release — the canonical per-build discriminator. Map keys are the *last 4 chars* of the disk checksum, which through 1.1.x are exactly the publicly-displayed checksum Paradox prints in the launcher (so the map can be populated for past releases from public patchnotes alone). 1.2.0 introduced an obfuscation transformation, so 1.2.0+ entries have to be sourced from an actual install. Unknown builds return nil and `Corrections.resolve` falls back to "apply all" (corrections are anchor-based and safely no-op on mismatch).
- CK2 is hardcoded at `3.3.5.1` — game has been EOL since the September 2021 patch.

**`Paradoxical::Game.new` lockdown.** Constructor signature is now `Game.new(game_module, root: nil, user_directory: nil)`. All the per-game inputs (NAME, STEAM_ID, executable, install layout, launcher format) flow from the module's constants. `JOMINI_VERSION` retired — replaced by orthogonal `HAS_GAME_SUBDIR` (controls `default_root`) and `LAUNCHER_FORMAT` (`:sqlite` / `:json` / `:legacy`, controls launcher dispatch). EU5 is the only `:json` user; CK2 gets `:legacy`, a stub that raises on mod-loading methods (parser-only usage still works); everything else is `:sqlite`. Per-version corrections register automatically inside the constructor.

**`paradoxical!` simplifies** down to slug → module lookup → `Game.new` → playset/mod selection → DSL prepend → Helper extend.

**Initial CORRECTIONS population** — the 5 malformed-input files left after phase 4d: 3 EU5 gui files (extra `}`), Stellaris `scripted_loc_ruloc.txt` (missing `}`), Imperator `posteffect_volumes.txt` (extra `}`).

**Smoke spec refactor**: `PARADOXICAL_PARSE_SMOKE` now takes a slug (e.g. `eu5`); install root resolves from the game module's defaults. `PARADOXICAL_PARSE_SMOKE_ROOT` overrides the install path for off-default Steam library locations. Encoding fallbacks initially moved to per-game `ENCODING_FALLBACKS` constants (superseded in phase 4f by a universal Windows-1252 fallback at the FileParser layer). Allowlist files renamed to slug-based names (`parse_smoke_allow_eu5.yml` etc.).

**All four game smokes are now empty-allowlist clean: 16,380 / 16,380 files parse.** Future malformed-input cases live in the matching game module's `CORRECTIONS` rather than getting allowlisted.

#### 5d. Game-namespaced code follow-up (landed)

Closing out phase 5. Three structural changes:

- **Editor moved under Stellaris.** `lib/paradoxical/editor.rb` was Stellaris-specific despite living at the top of `Paradoxical::` — it manipulates `intel_manager` / `clusters` / `galactic_object`, defaulted `@game = (game or Paradoxical::Game.new("Stellaris"))` (broken since 5c's `Game.new` lockdown took a module, not a string), and reads/writes `meta` + `gamestate` from `.sav` zips. Moved to `lib/paradoxical/games/stellaris/editor.rb`; renamed class to `Paradoxical::Games::Stellaris::Editor`. The pre-5c broken constructor default now resolves via `Paradoxical.game` (set by `paradoxical!`) with a clear ArgumentError if unset.
- **Per-game DSL files in subfolders.** Each game's DSL submodule now lives in its own file at `lib/paradoxical/games/<slug>/dsl.rb` rather than inline in `<slug>.rb`. Empty for CK2 / CK3 / EU5 / HOI4 / Imperator / V3 (placeholders for symmetry, populated as game-specific Builder helpers surface). Non-empty for EU4 (variable family override) and Stellaris (galaxy-setup + resource family).
- **DSL / Helper split.** `edit` was on the global `Paradoxical::Helper` (extended onto `main`). It's Stellaris-specific and shouldn't be visible from a non-Stellaris `paradoxical!`. Moved to a new `Paradoxical::Games::Stellaris::Helper` submodule at `lib/paradoxical/games/stellaris/helper.rb`. `paradoxical!` extends `game_module::Helper` onto `main` when defined (gated via `const_defined?(:Helper, false)`), alongside the existing `game_module::DSL` prepend onto Builder. The split mirrors callable-context: DSL methods (`add_resource`, `check_galaxy_setup_value`, etc.) need Builder context (`l()`, `p()`), so they go on Builder; Helper methods (`edit`) take a path and yield a block — they run at script top level, so they go on `main`. Conflating them in one module would expose Builder-context methods at the top level where they'd error on the missing `l()`/`p()` helpers.

The `@gamestate` intel-manager regex fix-up (`gsub(/^(\d+)\s*\{$/, '\1 = {')`) and the matching `intel > &list > &list` operator-clearing in `write` stay as-is — Stellaris save games deliberately ship that section in malformed PDX (the engine special-cases it on load), and the round-trip needs to preserve the engine's expected format. Worth recording: not all PDX malformedness is a bug; sometimes the engine itself emits non-conforming script. Same category as HOI4's `online_accountcreate.gui` Windows-1252 markup bytes — engine-specific quirks the parser has to humor.

Verified: 396 unit tests pass; EU5 + Stellaris parse smokes clean; `paradoxical! game: "stellaris"` exposes `edit` at top level, `paradoxical! game: "eu4"` does not.

Phases 1–5's structural restructuring is complete. 5e below is a known per-game DSL gap surfaced after the fact.

#### 5e. Per-game variable arithmetic DSLs (pending)

Surfaced during the in-game probe for 8d's precision validation: EU5 and Imperator use a new operation-keyed `change_variable` shape, while EU4 / Stellaris / HOI4 use the legacy separate-function family (`multiply_variable`, `divide_variable`, etc.) that the current base Builder loop emits.

Empirical sweep across installed games:

**Inline variable comparison in newer games.** EU5/Imperator deprecated `check_variable` in favor of inline comparison operators on variable references — `var:foo >= var:bar` is a valid trigger directly. This explains why `check_variable` empirically drops to 0 uses in EU5/Imperator (vs 825 in EU4 and 1431 in Stellaris) even though those games still need to test variable values. The DSL emits the inline form via the existing `p` helper: `p "var:foo", ">=", "var:bar"` — no new helper needed.

There are **three distinct body shapes** across the games, not two:

| Game | `change_variable` uses | Legacy `*_variable` uses | Shape |
|---|---:|---:|---|
| EU4 | 260 | 492 | `which` / `value` — `change_variable { which = X value = Y }` (functionally `add`), plus `multiply_variable` / `divide_variable` / … family. EU4 has a `which`-second-key wrinkle when the right-hand side references another variable (non-numeric Y) |
| Stellaris | 893 | 205 | `which` / `value` — same as EU4 but no second-key wrinkle. The high `change_variable` count is a keyword-name coincidence; the body is still the legacy `which`/`value` shape, not the new operation-keyed one |
| HOI4 | 0 | 341 | direct key=value — `set_variable = { VAR = VAL }`, `add_to_variable = { VAR = N }`, `multiply_variable = { VAR = N }`. No second-key wrapper at all; the variable name *is* the key. Arithmetic verb is `add_to_variable`, not `change_variable` |
| Imperator | 312 | 0 | `name` / operation-keyed — `set_variable { name = X value = Y }`, `change_variable { name = X add = Y }` |
| EU5 | 342 | 0 | `name` / operation-keyed — same as Imperator, with chainable + nestable operations inside `change_variable` |

**Three storage kinds.** Variables can attach to three different things:

- **Scope** — a persistent game object (country, location, religion, unit, …). The bare `set_variable` operates on the current scope; the variable lives with that object for the rest of the campaign (or until cleared). All games support this form, but the set of scopes that *accept* variables varies — EU4 limits to `country` and `province`; Stellaris expanded to nearly every scope type over its lifetime.
- **Context** — a transient execution unit (event chain, effect block, etc.). `set_local_variable` operates here; the variable disappears when the context ends. New in EU5 / Imperator.
- **Game** — game-wide, accessible from any scope. `set_global_variable` operates here. New in EU5 / Imperator.

| Game | Bare (scope) | Local (context) | Global (game-wide) |
|---|---|---:|---:|
| EU4 | yes — `country` / `province` scopes only | 0 | 0 |
| Stellaris | yes — broad scope support added over the game's lifetime | 0 | 0 |
| HOI4 | yes | 0 | 0 |
| Imperator | yes | 73 | 26 |
| EU5 | yes | 124 | 55 |

The per-game DSL helpers will need to surface the local + global variants separately on EU5 / Imperator since they're semantically distinct from the bare form (different lifetime + reach), not just a naming preference.

**`clamp_variable` aside.** EU5 (7 uses) and HOI4 (216 uses) ship a `clamp_variable` keyword that's redundant in EU5 (the same `min` / `max` operations live inside `change_variable`) but is the only path on HOI4 (which doesn't have the new operation-keyed shape). Body shapes differ too — HOI4 uses a `var =` key (`clamp_variable { var = X min = Y max = Z }`), EU5 uses `name =` to match the new-shape convention. Worth noting since it's a function the per-game DSL helpers should also cover, not just a quirk of the `change_variable` story.

The EU5 / Imperator shape is meaningfully more powerful. Operations (`add`, `subtract`, `multiply`, `divide`, `modulo`, `min`, `max`, `value`) can be chained in one `change_variable` and nested. Example from EU5:

```
change_variable = {
  name = imperial_authority
  add = {                                # nested expression
    value = scope:loser.total_population
    divide = scope:winner.total_population
    max = 2
    min = 0.1
    multiply = 5
  }
}
```

Read as: compute `loser.total_population / winner.total_population`, clamp to `[0.1, 2]`, multiply by 5, then add the result to `imperial_authority`. A single nested block — not expressible by the legacy per-operation function family.

**5e-1: Structural move + basic per-game shapes (landed).**

- Variable-arithmetic loop removed from base `Builder` — each game's DSL now owns its variable helpers, so adding a Builder DSL doesn't accidentally inherit wrong-shape behavior.
- **EU4 DSL**: keeps the existing `which`-second-key wrinkle for non-numeric values; absorbs `export_to_variable` from base Builder (EU4-only across the installed games, 370 uses).
- **Stellaris DSL**: legacy `which`/`value` family added, no wrinkle.
- **HOI4 DSL**: direct key=value family — `set_variable = { VAR = VAL }`, `add_to_variable = { VAR = N }`, `multiply_variable` / `divide_variable` / etc. The variable name is the inner property's key, not a wrapped `which =` / `name =`.
- **EU5 / Imperator DSL**: `set_variable { name = X value = Y }` plus simple non-chained `change_variable { name = X add = Y }` via operation kwargs. Scope-prefixed variants added (`set_local_variable` / `set_global_variable` / `change_local_variable` / `change_global_variable`).

Tests at `spec/games/dsl_spec.rb` exercise each game's emission shape via anonymous Builder subclasses with the DSL module prepended. 483/0 unit, 22,229/22,229 parse smokes clean.

**5e-2: Chainable + nested `change_variable` (landed).**

The EU5/Imperator example from the empirical research shows the full shape:

```
change_variable = {
  name = imperial_authority
  add = {                                # nested expression
    value = scope:loser.total_population
    divide = scope:winner.total_population
    max = 2
    min = 0.1
    multiply = 5
  }
}
```

Read as: compute `loser.total_population / winner.total_population`, clamp to `[0.1, 2]`, multiply by 5, then add the result to `imperial_authority`.

The 5e-1 DSL handled flat operation kwargs (`change_variable("x", multiply: 100, min: 0, max: 1)`); 5e-2 adds a block form so operations can carry nested bodies. Implementation is a backward-compatible addition — the existing `change_variable` / `change_local_variable` / `change_global_variable` helpers now also accept a block, and the block evaluates in Builder context so any `keyword do … end` inside it falls through `method_missing` → `pdx_obj` and emits the right `keyword = { body }` shape:

```ruby
change_variable "imperial_authority" do
  add do
    value "scope:loser.total_population"
    divide "scope:winner.total_population"
    max 2
    min 0.1
    multiply 5
  end
end
```

Flat kwargs + block can also mix; kwargs emit first, block contents after. Block form leaves the list multi-line for readability; flat-kwargs-only form stays `single_line!` as before.

The DSL needs almost no new code — three lines in each game's DSL (`change_variable` definition now passes a block through to `l(...)` and skips `single_line!` when a block is present). The heavy lifting (nested block evaluation, child accumulation) was already in `Builder#list`. Verified the doc-note suspicion in 5e-3 that "most keywords work via idiomatic DSL" — same logic applies to the operation bodies here.

**5e-3: `days:` kwarg + property-form shorthand (landed).**

5e-1 and 5e-2 covered the structural move + the common helpers + chainable change_variable. 5e-3 fills in the last two cases where an explicit helper still pays for itself; everything else (`has_variable`, `clamp_variable`, `round_variable`, etc.) works via Builder's `method_missing` → `pdx_obj` fall-through:

```ruby
has_variable "foo"                                  # has_variable = foo
clamp_variable do; name "foo"; min 0; max 100; end  # EU5 form
clamp_variable do; var "foo"; min 0; max 100; end   # HOI4 form
round_variable do; name "foo"; nearest 1; end
```

Two genuine helper additions:

- **`days:` kwarg on `set_*_variable`** (EU5/Imperator). Emits `{ name = X value = Y days = N }`. Real examples confirmed in EU5 source: `set_variable = { name = ccw_timer value = yes days = 365 }`. `set_global_variable` also accepts it (1 EU5 use); `set_local_variable` empirically doesn't appear with `days` (engine likely ignores it since local variables die with the context anyway) but the helper accepts it for shape symmetry.
- **Property-form shorthand**: `set_variable("foo")` (single positional arg) emits `set_variable = foo` instead of the block form. Equivalent to `set_variable = { name = foo value = yes }` per the wiki. Empirical use is heavy: EU5 has 768 / 9 / 27 property-form uses of bare / `_local_` / `_global_` (Imperator 700 / 1 / 11). The shorthand applies across all three scope variants.

Verified: 492/0 unit (4 new — single-arg shorthand for bare + scope variants, `days:` kwarg for bare + scope variants), 22,229/22,229 parse smokes clean, rubocop clean.

The variable-arithmetic DSL surface is now feature-complete for the per-game shapes we've observed. Future work would be game-specific (e.g., new keywords in future patches) rather than structural.

### 6. RBS types

- Type the public surface: `Paradoxical::Game`, `Paradoxical::Mod`, `Paradoxical::Elements::Document`, `Paradoxical::Elements::Node` and subclasses, `Paradoxical::Elements::Primitives::*`.
- Leave the builder/DSL as `untyped` — `method_missing` fundamentally resists static typing and forcing it gives users no real value.
- Use Steep with strict mode on the typed files only.

### 7. Documentation

- YARD `@example` blocks throughout the public API and the DSL. Where practical, run them as tests (yard-doctest or a small custom runner) so docs and tests can't drift.
- A real README (replace boilerplate) covering installation, supported games, a small worked example, and pointers to deeper docs.

### 8. Richer primitive types

Open-ended and explicitly gated on "concrete need surfaces." Stdlib-only by design: no third-party calendar/decimal/etc. gems, and no custom abstractions that downstream mod authors have to learn beyond what they already know. See memory.

#### 8a. Color subclass refactor (landed)

Foundation work for the broader color rework. `Primitives::Color` split from a single class with `type` / `colors` / `rgb?` predicates into a real subclass hierarchy: `Primitives::Color::RGB` / `HSV` / `HSV360` / `Hex`, each in its own file under `lib/paradoxical/elements/primitives/color/`. The parser instantiates the right subclass based on the matched keyword; `is_a?(Color)` stays true across all four.

**Grammar:** de-atomized the `color` rule. The old `@{ ... }` matched as a single byte string that Ruby regex'd back apart in `maybe_parse!`. The new rule captures each subtype + its components + per-token whitespace as distinct AST nodes, so the Rust side dispatches components to the right typed primitive (`Primitives::Integer` vs `Primitives::Float`) at parse time. HSV360 restricted to exactly 3 components per the parser-strictness principle (empirical sweep across all five installed games found zero hsv360 alpha).

**Ruby surface:**
- Per-channel accessors via a declarative `channels :r, :g, :b, :alpha` macro on the base — each concrete class reads as one line. Storage delegates to `component(idx)` / `set_component(idx, v)` which default to `@components[idx]`; Hex overrides them to slice 2-char channels out of its `0x...` literal so the same `channels` declaration works there too.
- Each subclass declares its `type` literal explicitly (`def type; "rgb"; end`); the base method is abstract.
- Conversion API shifted from in-place mutators (`hsv!`, `rgb!`) to typed constructors (`#to_rgb`, `#to_hsv`, `#to_hsv360`, `#to_hex`). Identity conversions return `dup`, not `self`, so callers can mutate the result safely.

NotImplementedError preserved at this phase for the cases 8b fixes (4-component conversions, hsv360 conversions, hex conversions, the float-RGB conversion math bug, `justify!` for 4-comp / hsv360 / hex).

#### 8b. Color validation + conversion math (landed)

Every remaining `NotImplementedError` in the Color subclasses replaced with real math, plus construction-time validation where empirical data supports it.

**Per-component interpretation rule** for conversion math (handles real-data mixed cases the originally-planned "all-or-nothing" rule couldn't):
- RGB: Integer → /255 (channel), Float → as-is (fraction, HDR-extended above 1 ok).
- HSV: Integer → /100 (percentage style — `hsv { 0 100 0.8 }`), Float → as-is.
- HSV360: h/360, s/100, v/100.
- Hex: 2-char pair → int / 255.

Direct conversions: RGB ↔ HSV (the classic math, fixed for float-RGB inputs), HSV ↔ HSV360, Hex ↔ RGB. Indirect conversions chain through these so the math lives in one place. **HDR preservation:** if any normalized channel > 1, HSV → RGB outputs Float RGB; otherwise Integer RGB. Alpha threads through where source and target both support it (RGB / HSV / Hex); dropped on HSV360.

**Validation (construction-time)** scoped to what real data supports:
- RGB: components all-Integer or all-Float — *except* Integer 0/1 are polymorphic. EU5 ships `rgb { 0.502 0 0.612 }` where the bare `0` is the fraction endpoint. Only real Integer (≥2) mixed with Float gets rejected.
- HSV360: all-Integer. Empirical sweep (826 unique values in EU5 alone) found zero floats.
- HSV: none. Real data ships mixed types and HDR-extended values (`hsv { 0 100 0.8 }`, `hsv { 0.5 0.1 4.5 }` Stellaris lighting colors) — permissive grammar matches engine permissiveness.
- Hex: `0x` followed by at least one hex digit. Even-digit requirement dropped — EU5 ships a 9-digit literal (`0xffeDAA06D`) the engine accepts; the slicer returns nil for incomplete pairs rather than corrupting the read.

`justify!` now works on every shape: RGB / HSV 3-or-4 components, HSV360 3-component integer width padding, Hex outer-whitespace canonicalization.

**Empirical findings worth recording** (for future numeric-primitive work in 8d and beyond):
- The parser-strictness principle ("don't be more lenient than the engine") must be empirically validated, not assumed. We initially planned all-or-nothing homogeneity for RGB *and* HSV; real data immediately refuted both. The shape we landed on is "validate what's clearly invalid; stay permissive where the engine itself is permissive."
- Per-component typing (each component reads its own scale) handles mixed-type real-data cases that all-or-nothing rules can't.
- HDR-extended values exist across HSV (Float `v` > 1) and HSV360 (Integer `v` > 100). Conversion math must let them flow through unclamped; output type can switch between Integer/Float per HDR presence to preserve the brightness multiplier.

Verified: 415 unit tests pass; all five parse smokes clean (22,229 / 22,229 files).

#### 8c. Custom per-game calendar implementations (landed)

Two concrete calendar classes under `Paradoxical::Calendars`; `Primitives::Date` carries a class-level default that `Game.new` sets per active game (so parse-smoke and `paradoxical!` both pick it up automatically — `paradoxical!` goes through `Game.new`).

- **Calendar365** — 365 days, 12 months of 28/30/31, *no leap years*. EU4 / EU5 / CK3 / HOI4 / Imperator / V3 / CK2. Imperator's BC-shifted years (`-50.1.1`) flow through plain integer-year math, so no Imperator-specific subclass needed.
- **Calendar360** — 12 × 30 = 360 days. Stellaris only.

Not "Gregorian" — Gregorian has leap years; the 365-day no-leap-year calendar is a Paradox invention with no real-world analog, so the name is descriptive.

**`Primitives::Date` rewrite.** Dropped the stdlib-Date impersonation in favor of a typed primitive that stores year / month / day eagerly and carries its calendar. `+`/`-` accept `Integer` (days) or `ActiveSupport::Duration` (calendar-aware year/month shifts with day-clamping when a month-shift lands on a shorter month). `Date - Date` returns the day-count delta. `Comparable` for `<`/`>`/`<=>`. The raw bytes round-trip via `to_pdx` unchanged.

**Permissive at parse time** — *not* "valid by construction." Empirical sweep across all five games turned up sentinel dates the engine accepts (`0000.00.00`, `1.0.1`, `Feb 29` in non-leap calendars). The grammar accepts them, the engine accepts them, so we round-trip them faithfully. Calendar semantics apply only on the arithmetic path; out-of-range inputs flow through `to_day_count` / `from_day_count` as integer math without crashing, but the result may be nonsensical (garbage-in / garbage-out).

**Explicit decision: don't impersonate stdlib `Date`.** Arithmetic on stdlib Date can land on Feb 29 (real-world leap day, in-game-invalid) and surface as wrong-day bugs much later. Custom calendars are regular enough (no leap years, fixed month lengths, no time / timezone / locale / format complexity) that arithmetic produces engine-valid dates by construction *when inputs are themselves engine-valid*.

HOI4 and EU5 have hour-level granularity in-game but the script language doesn't expose it (per the maintainer), so date primitives stay day-resolution. AS::Duration's `hours` / `minutes` / `seconds` parts are truncated to whole days.

Verified: 423 unit tests pass (8 new — year/month/day accessors, sentinel-date acceptance, day arithmetic, AS::Duration month-shift with day-clamp, Date - Date, Comparable, Stellaris Feb 30 support). Parse smokes clean across all five games (22,229 / 22,229 files).

#### 8d. Float → BigDecimal-backed precision (landed)

`Primitives::Float` was impersonating Ruby `::Float` (binary FP). DSL math on parsed decimals would drift due to binary-FP rounding — the classic `0.1 + 0.2 = 0.30000000000000004` failure on every value modders actually care about.

**Empirical precision finding (EU5):** older PDX games stored decimals as fixed-precision integers with 3 decimal places (`1.234` = internal `1234`). EU5 isn't that anymore — numerous game-data floats carry 4-6 digits of precision, with 6 a soft limit (~20k 6-digit values across the install, only 49 with 7+ digits and at least one of those is in a comment). Best guess: 64-bit integers with 6-digit fixed precision for game logic, true float/double for some shader/rendering paths.

**Decision: BigDecimal over Integer × scale.** Variable precision per file/field rules out fixed-scale Integer. BigDecimal is stdlib; the `Impersonator` concern handles infix and comparison delegation through `to_real`, so switching the impersonated class to `::BigDecimal` and the conversion method to `:to_d` propagates BigDecimal semantics to comparisons and arithmetic automatically.

Migration surface (small — PancakeTaco is the only consumer):
- `Primitives::Float#to_real` returns `BigDecimal` instead of `Float`. Arithmetic results from `+`/`-`/`*`/`/`/`%`/`**` are `BigDecimal` instead of `Float`.
- `prop.value.to_f` still works (BigDecimal responds to `to_f`).
- `prop.value.is_a?(::Float)` becomes false; `is_a?(::BigDecimal)` becomes true. `PropertyMatcher#matches?`'s `is_a?(Float)` coercion check was updated to also recognize `BigDecimal`.

Raw bytes still round-trip via `to_pdx` unchanged — round-trip is bytes-in / bytes-out, independent of how arithmetic interprets the value.

Verified: 469 unit tests (5 new — `to_real` is BigDecimal, `0.1 + 0.2 == 0.3` exact, `is_a?` type contract, raw-bytes round-trip, `to_f` still works). Parse smokes clean across all five games (22,229 / 22,229).

**In-game empirical confirmation (EU5, post-merge).** Validated via console `run`:

```
set_local_variable = { name = test_var value = 0.2 }
while = { count = 10 change_local_variable = { name = test_var add = 0.1 } }
debug_log = "test_var: [SCOPE.GetLocalVariable('test_var').GetValue]"
```

Result: `1.2` exactly — not `1.20000…` drift. So the engine's variable arithmetic isn't `Float`/`double`; it's fixed-precision or BigDecimal-equivalent. Our Ruby-side BigDecimal model is engine-correct for arithmetic semantics, not just "close enough."

Same probe revealed a two-tier precision cap:
- **6 digits** for general source-file constants (modifiers, events, etc.). Beyond → load-time errors.
- **5 digits** for `set_local_variable` / `change_local_variable`. Distinct error messages for `set` vs `change` suggest separately validated, not a shared parser path. A 6-digit constant in `modifiers.txt` loads fine but the same value via `change_local_variable add` errors.

**Binary-save confirmation (2026-05-19).** `BinaryParser` (PR #81) revealed that the binary save format ships a dedicated fixed-point token range — 0x0d48..0x0d4e (positive, 1..7 byte widths) and 0x0d4f..0x0d55 (negative) — encoded as `raw_integer / 100_000`, i.e. *exactly* 5 decimal digits of precision. This is the storage shape EU5 uses ubiquitously for serialized state, not just for variable arithmetic, and corroborates the in-game probe. Source-file values with more digits after the decimal (the ~20k 6-digit and ~49 7+-digit values flagged in the empirical sweep) presumably flow through a separate true-float/double path the engine picks per field — context the script-side parser doesn't have, so we can't disambiguate at parse time. BigDecimal stays the right Ruby-side abstraction for both cases; the new evidence is one more reason to default DSL emissions to ≤5 digits.

Practical guidance: DSL emissions should stay ≤5 digits in variable arithmetic, ≤6 elsewhere. Not currently enforced in code (would need a precision-cap option on the Float DSL output); documented in `Primitives::Float`'s class doc-comment for future reference.

Note: the `Impersonator#is_a?` override doesn't alias to `kind_of?`, so RSpec's `be_a` matcher (which uses `kind_of?`) sees the standard class-hierarchy answer (Primitives::Float doesn't inherit from BigDecimal). Production code uses `is_a?` consistently, so this divergence isn't load-bearing. Aliasing `kind_of?` to `is_a?` in the Impersonator concern is a follow-up cleanup not specific to 8d.

#### 8e. Distinct primitive types for string-like patterns

`Primitives::String` is the catch-all for any sequence that doesn't match a structured primitive. Several PDX concepts the engine treats as distinct types are still lumped under it; each lift gets its own sub-PR since each surfaces its own allowlist-churn risk.

Sub-PR sequence in order of complexity:

- **8e-1: `Primitives::Percentage` (landed).** Lift the percentage shape out of `String`. Grammar widened to capture fractional percentages (`12.5%` — HOI4 ships 7k+ of these and they previously fell through to `unquoted_string`). Class stores raw bytes for round-trip plus `value` (BigDecimal — matches 8d's Float backing) and `multiplier` accessors (the scalar to multiply against; renamed from "fraction" since HDR-style >100% values are common and "fraction" implies [0, 1]). Immutable — same shape as `Primitives::Date`; raw bytes carry presentation info (sign, decimal precision, multi-`%` count) that doesn't map cleanly through a `value=` setter. No range validation: all five games ship negative percentages and >100% values; HOI4 alone has 13k+ `>100%` uses. Multi-`%` (`+10.00%%`, HOI4's 956 uses) is a localization-template escape — preserved as raw bytes; `value` strips the trailing `%`s. Comparable on numeric value. 499/0 tests, 22,229/22,229 smokes clean.

- **8e-2: `Primitives::VariableRef` (landed).** Lift `@variable_name` references out of `String`. New grammar rule `var_ref = @{ !("@@" | "@$" | "@[" | "@\\") ~ "@" ~ (LETTER | NUMBER) ~ (LETTER | NUMBER | "_")* ~ &break_character }` precedes `string` in the `primitive` alternation. The negative lookahead protects four `@`-using shapes that share the sigil for unrelated runtime operators and stay as `String`: `@@varname` (EU5 template indirect), `@$NAME$_text` (Stellaris parameter splice), `@[expr]`/`@\[expr]` (math-at-parse, owned by 8e-3). Other `@`-using patterns (HOI4 `party_popularity@democratic` dynamic accessor, Stellaris `event_target:name@suffix`, EU4 `flag_name_@ROOT`) have a non-`@` token prefix so they never reach this rule and stay as `String` naturally. Empirically — no game ships `@varname` mid-identifier embeddings, so whole-token-only matches the actual surface area.
  - Ruby class: immutable `raw`/`name` value-state plus a mutable `owner` ivar (the containing `Property` or `Value`), set by `Property#key=` / `Property#value=` / `Value#value=` setters when a VariableRef is assigned in. Comparable / `==` / `eql?` / `hash` are name-based.
  - `#resolve` walks up from `owner.parent`, scanning each enclosing list/document for a `Property` whose key is a VariableRef of the same name; returns the property's value (which may itself be a VariableRef — chain by re-calling). Raises with a descriptive message if detached or unresolved. This is the foundation 8e-3's Computation `#evaluate` builds on.
  - Builder helper `var_ref("name")` / `var_ref("@name")` / `var_ref(:name)` — normalizes the leading `@`.
  - 524/0 tests (15 new), 22,229/22,229 smokes across all five games clean.

- **8e-3: `Primitives::Computation` (pending).** `@[expr]`, `@\[expr]`. Math-at-parse-time. Internal expression grammar that may reference VariableRefs — `#evaluate` chains through 8e-2's resolution. Done next so the VariableRef foundation is exercised end-to-end before we layer on the simpler-but-orthogonal localization/parameter work.

- **8e-4: `Primitives::LocalizationRef` (pending).** `[ROOT.GetName]`, `[KEY|format]`. Has internal grammar — scope chain + getter + optional format spec. Tier-1 (validate balanced brackets) is cheap; tier-2 (parse scope/getter/format slots) enables typed querying. Likely worth tier-2 since the scope chain itself is rich enough that knowing its parts is useful.

- **8e-5: `Primitives::Parameter` (pending — possibly punt).** `$NAME$` substitutions. Pre-compilation macros — the engine string-substitutes before parsing, so `foo_$BAR$_baz` is a valid identifier shape where `$BAR$` expands inline. Empirical: whole-form `$BAR$` and mid-identifier embeddings have comparable volume (10k-40k each per game), so whole-form-only coverage loses ~30-50% of uses. **Working plan**: hybrid (whole-form gets typed; mid-identifier stays as `String` with a `.parameters` accessor for introspection) — or punt entirely and leave parameters as strings since the typing value is limited and the grammar already differentiates the sigil shapes. Decide after VariableRef/Computation land and we have a calibrated sense of the typing pattern's payoff.

**Trade-off to budget for.** A stricter parser will surface previously-passing files as smoke failures. That's positive signal (real invalid syntax we used to mask) but each fix surfaces its own allowlist churn — and if any `compile.rb`-emitted output trips on stricter validation, the DSL needs a small accompanying fix to use the right typed helper. Each sub-PR runs all five smokes before merge.

### 9. Per-game primitive validation

The grammar accepts the union of what all five engines permit, by design (one parser, many games). But individual engines reject shapes other engines accept, and there's no way today to surface "the grammar permits it, but engine X rejects it" so mod authors hear about real bugs in their content.

Known seed cases (more expected as we investigate):

- **VariableRef name shape** — EU5 (Jomini) rejects `@_foo` and `@1foo` with "Invalid variable name. Variable names must start with a letter and only contain letters, numbers, or underscores." HOI4 (Clausewitz) accepts and ships 141 `@<year>` defs (`@1918 = 0` etc.). Two different validation rules across engine generations for the same grammar shape.
- **Quoted vs unquoted strings** — game-specific strictness varies; need to catalog empirically.
- **Date sentinels** — `0000.00.00` and similar are accepted in some games but not others.
- **Color components** — `Color::RGB`, `Color::HSV360`, `Color::Hex` already use `validate!` (shape established in phase 8b), but it raises rather than warns.

Warnings, not errors. The engine itself warns and skips the offending line at runtime — a hard parse error in Paradoxical would make an invalid mod unparseable until the user writes a correction, which is a worse user experience than the engine's "log and continue." Fatal parse errors stay reserved for grammar-level failures (`ParseError`).

Design surface to settle:

- **Warning channel.** Probably a `Document#warnings` accumulator the parser populates, plus a CLI surface to print them after a parse. Needs to flow through `Game#parse_files` so batch-parses surface every warning, not just the last one.
- **Per-primitive validation hook.** Extend the `validate!` precedent already in `Color::*` to other primitives; convert raise → warn-channel for the new cases.
- **Per-game config.** Class-level state set by `Game.new`, same shape as `Date.default_calendar` and `Float.default_precision`. E.g., `VariableRef.name_pattern` set to a Jomini-strict or Clausewitz-permissive regex.
- **Empirical sweep.** Once the infrastructure exists, walk each primitive and catalog which games reject which shapes. The seed cases above are what we know about; the actual list is likely larger.
- **Relationship with corrections.** Corrections (phase 5c) fix up *parse-blocking* invalid syntax; validation warnings flag *engine-rejected-but-grammar-acceptable* syntax. They're complementary — a mod could have both. May need to consider whether some validation warnings should suggest a correction.

Gated on 8e completing — once all the typed primitives exist we know the full set that might want per-game rules. Phase 8b's `validate!` work is the closest precedent and a useful reference.

### 10. Compound keys (object-as-key maps)

EU5 (and likely older PDX) save files use a "map keyed by a sub-list" pattern the current parsers don't model: a `{ … }` block on the LHS of `=`. Real example from an EU5 save:

```
needed={
    {
        demand=pop_demand
    }={ 37 43 47 51 71 86 91 99 … }
}
```

Read as: *"for each demand-spec object, the list of pop IDs that need it"*. One probe save (`plaintext.eu5`, ~300 MB, 1337.4.1) contains 24,541 such pairs.

Both parsers fail at the same shape:

- **Script grammar** restricts `property` and `keyed_head` to `primitive ~ ws ~ operator` — a `{ … }` block isn't a primitive, so `}={` is ungrammatical.
- **Binary parser** `read_next` handles only value / close / token-key; encountering `{open: true}` (`0x0003`) where a key is expected raises `expected token, got: {open: true}`.

Structurally independent of phases 8e and 9 — different concern (`Property` shape, not primitive richness). Can run in parallel with whichever 8e sub-PR is in flight; no ordering dependency between them.

#### 10a. `Property` key-shape audit

`Paradoxical::Elements::Property` is *already* polymorphic on `key` — `to_pdx` calls `key.to_pdx`, and a `List` key would render as `{ … }=` correctly today. So 10a is an audit, not a redesign: sweep every consumer that does `prop.key.is_a?(String)`, `prop.key.to_s`, or feeds `key` into a string-keyed Hash and decide per site whether to (a) skip non-string keys, (b) handle them, or (c) widen the type.

Known sites to check: `Document#[]` / `value_for` / `keys`, `Property#==` and `#hash` (already structural — likely fine), the builder DSL's `pdx_obj` emission path, and anywhere the search subsystem joins on key.

The `VariableRef` back-fill in `key=` (sets `key.owner = self`) is precedent for type-aware key handling and likely the right hook to mirror when a `List` key arrives (back-fill `list.parent = self` so resolution works from inside a compound key).

#### 10b. Script grammar: compound-key shape

Extend `script.pest` so a `{ … }` block can appear as the LHS of `=`. Likely shape: a new `compound_head` alternative inside `list_head`, ordered so the `}` + `=` lookahead disambiguates it from the existing `keyed_head` / `bare_head`. Rust side dispatches the captured sub-list into the Property's `key` field instead of a String.

Risk to budget for: the 22,229-file smoke baseline is currently empty-allowlist across all five games. A new alternative tried too early in the alternation could regress files that already parse. Add it as the last fallthrough; `}` + `=` is a boundary no existing shape produces.

Open question: does the script form *only* appear in save files, or does any mod-data file ship compound keys? Empirical sweep across the installed games' game-data trees will answer this. If save-files-only, the grammar change isn't load-bearing for the parse-smoke baselines (saves aren't smoked today), which lowers the risk.

#### 10c. Binary parser: compound-key handling (landed)

`read_next` now branches on `{open: true}` at the position a key token would normally occupy: it consumes the sub-list via `read_list(key: nil)`, expects `=`, then dispatches the tail through a new `read_property_with_key` helper (extracted from the existing token-key path so both code paths share value-reading). Two output shapes per the rest-of-parser convention:

- compound key + primitive value → `Property.new(compound_key, "=", primitive)`
- compound key + list value → `List.new(compound_key, [children])` (matches the existing "RHS is `{…}` → keyed List" pattern)

4 new synthesized fixtures in `spec/parser/binary_parser_spec.rb` exercise the primitive-value form, the list-value form, the realistic outer-keyed-list-of-compound-pairs shape, and the "compound block not followed by `=`" error path. 584 / 0 across the full suite.

**Empirical verification: partial.** Parsing a real EU5 binary save (~40 MB gamestate, no token table supplied) makes it deep into the gamestate but fails at a different shape — `unexpected control token after \`225\`: {token: 11478}`. That's a separate EU5 quirk, tracked below as **10e — token-as-value**: the engine encodes some right-hand-side identifiers as raw 2-byte tokens (presumably compression for repeated literals like `yes`/`no` and enum names) instead of as type-discriminated quoted/unquoted strings. The current `read_scalar` `else { token: type }` branch only intends to surface key tokens; in value position the code expects a type-discriminated scalar and there isn't one.

#### 10d. Document accessors

`Document#[]` / `value_for` / `keys` currently assume string keys. Three options when compound-keyed entries are present:

- **Skip silently** — simplest; existing string-keyed callers see no change, compound keys are reachable only via direct iteration.
- **Separate `compound_entries` enumeration** — explicit access path for callers that want compound-keyed pairs without paying the cost of structural equality on every lookup.
- **Structural-equality lookup** — `doc[{demand: "pop_demand"}]` etc. Most general, largest scope; requires `List#hash` / `#eql?` to behave correctly under arbitrary nesting, which is currently true by construction but worth re-verifying.

Defer the call until a concrete consumer materializes. The first one will almost certainly want enumeration ("walk every compound-keyed entry in this list"), not structural lookup.

**Shared design for 10e and 10f.** Both of the binary-parser extensions below resolve byte-shape tokens to identifier-shaped strings — value-position tokens via the per-game `tokens:` table (10e), and lookup-index values via a per-save `string_lookup:` table (10f). Rather than inventing per-shape primitive wrappers (`Primitives::TokenRef`, `Primitives::LookupRef` mirroring `VariableRef`), `Primitives::String` grows two optional kwargs:

- `token_index:` — the `tokens:`-table integer the string was resolved from
- `lookup_index:` — the `string_lookup:`-table integer the string was resolved from

Both default nil; equality / `hash` ignore them since they're round-trip metadata, not value state. Plaintext-parsed strings never set either. The existing key-resolution path in `read_next` migrates to emit `Primitives::String.new(name, quoted: false, token_index: …)` in place of the plain `::String` returned by `tokens[…] || …` today, so all three identifier-producing sites in the binary parser read identically — consistent "string-with-kwargs" strategy for binary tokens across the board.

Future binary writer ternary: `token_index` set → emit 2-byte token; `lookup_index` set → emit `LOOKUP_NN` + index bytes; neither set → emit standard `QUOTED`/`UNQUOTED` + length + bytes. Until the writer exists the metadata is dead state; one kwarg + accessor's worth of cost to avoid a `Primitives::String` shape change later.

Graceful degradation when the side-channel table isn't supplied: fall back to the raw integer surfacing the current code does. Matches how missing `tokens:` entries degrade today, and keeps inspection callers usable.

#### 10e. Binary parser: token-as-value (landed)

`Primitives::String` gained an optional `token_index:` kwarg (default nil, equality/hash ignore it, preserved across `dup`). Three sites in the binary parser now share a `resolve_token_string` helper that produces the same shape:

- `read_next`'s key-resolution path: `resolve_token_string(n[:token])` instead of `tokens[n[:token]] || n[:token]`. Keys now arrive at `Property.new(...)` as `Primitives::String` with `token_index` set.
- `read_property_with_key`'s value-position branch: when `maybe_open` is `{token: N}`, the same helper produces a `Primitives::String` for the property value.
- The shared `resolve_token_string` helper is the single source of truth for "binary token → identifier-shaped string."

Unresolved tokens (no entry in the supplied `tokens:` table, or no table at all) still produce a `Primitives::String` — with `"0x#{token_int.to_s(16).rjust(4, "0")}"` as the text, e.g. `"0x2cd6"`. The `token_index` field is set in both resolved and unresolved cases. Rationale: a `Primitives::Integer` fallback would be visually indistinguishable from a genuine integer value in the parsed Document; a hex-formatted string with the leading `0x` is unambiguously a binary-token artifact, making missed lookups easy to spot at a glance and grep for. The `0x` prefix matches the format the parser's existing error messages already use (the rgb branch's `"expected open token got: 0x..."`).

Tests: 7 new specs in `spec/parser/binary_parser_spec.rb` covering resolved-key shape, unresolved-key hex shape, token-as-value resolution, value-position hex fallback, and `Primitives::String#token_index` value semantics (default nil, equality ignores it, preserved across dup). 591/0 full suite.

**Empirical verification against a real ~40 MB EU5 binary save** (no token table supplied so all identifier-shapes appear as `Primitives::Integer` fallbacks): the parser now clears the token-as-value shape and gets *much* further in (~404 KB into the gamestate) before hitting yet another binary-format shape — a tuple-key pattern where multiple bare integers act as a compound key inside a list (`{ 1 0 = 0 }`). Tracked as 10g below. The empirical question 10e was supposed to answer — "do bare tokens appear in list-child position?" — didn't surface; the tuple-key case is structurally different and is what trips on real data first.

#### 10g. Binary parser: peek-equals key/value disambiguation (landed)

Surfaced when verifying 10e against a real EU5 save. Originally hypothesized as a "tuple key" (two bare i32s forming a compound key); empirical check against the plaintext save refuted that:

```
duration={ 1 0=0 }
duration={ 66 0=0 1=0 2=0 3=0 … 64=0 65=0 }
```

The actual shape is a list whose children mix *bare scalar values* with *integer-keyed properties*. The leading integer is a count (66 entries → 0..65 keys); the trailing entries are an indexed map. The blocker isn't a compound-key shape — it's that the binary parser was committing too early to "this thing is a bare value" without checking whether `=` follows.

Implementing the fix surfaced *two more* shapes that depend on the same disambiguation:

- A `{ … }` block that turned out **not** to be a compound key — the next bytes were `{` (a new keyless sibling), not `=`. PDX saves carry keyless sub-lists like `key = { 1 { 2 3 } 4 }` at any nesting level.
- A token (`{token: N}`) that turned out **not** to be a key — followed by `}` (close), making it a bare token-as-value. This is the empirical question 10e's plan asked but didn't surface until ~7.4 MB deep.

All three reduce to the same lookup: peek the next 2 bytes for the `=` (`0x0001`) marker. If present, the just-read thing is a key — consume the `=` and dispatch through `read_property_with_key`. If absent, it's a stand-alone value (bare Value for primitives + resolved tokens; the List directly for sub-lists, since keyless lists are first-class in the AST).

Implementation:

- New `peek_equals?` helper: `bytes[0] == 0x01 and bytes[1] == 0x00` without consuming; safe at EOF.
- Three branches of `read_next` each gain the same peek-and-consume pattern (after a primitive scalar, after a sub-list, after a resolved token). The three "is this a key" branch points stay duplicated rather than extracted — each has its own correct-result-when-not-a-key (Value-wrap for primitives/tokens, list-direct for sub-lists), so a shared helper would buy little.
- No AST-shape changes: the existing `Property.new(any_kind_of_key, "=", value)` path the 10a audit already verified handles all three key shapes.

The leading-length / indexed-map *semantics* (recognize "first child is bare int, remaining children are ascending integer-keyed entries, count matches" → typed Vector) is downstream of parsing and a candidate for a later phase. The parser's job is faithfully representing the wire shape; collapsing into a typed wrapper would lose information when those rules don't hold.

Empirical verification: real EU5 ~40 MB save (172 MB gamestate) now parses fully end-to-end — 77 top-level entries.

#### 10f. Binary parser: lookup-index resolution (the values-correctness issue)

Lookup tokens (`LOOKUP_08` / `LOOKUP_16` / `LOOKUP_24` / `LOOKUP_08A` / `LOOKUP_16A`, all in the `0x0d3e..0x0d44` range) carry a 1/2/3-byte index into a `string_lookup` table that ships as a second file alongside `gamestate` in the save's zip. Currently `read_scalar` emits these as `Primitives::Integer`, breaking binary↔plaintext symmetry — the same logical value renders as an integer in binary parses but as a string in plaintext parses.

Fix shape, per the shared design above:

- New `string_lookup:` kwarg on `BinaryParser.parse` (and matching `default_string_lookup=` class-level setter). The save-extraction wrapper reads the `string_lookup` file from the zip alongside `gamestate` and passes both in.
- `read_scalar`'s `LOOKUP_NN` branches read the N-byte index and look it up. When found, emit `Primitives::String.new(text, quoted: false, lookup_index: idx)`. When not (or no table supplied), fall back to the existing `Primitives::Integer` so inspection callers without the side channel stay usable.
- Wire format of the `string_lookup` file itself needs reverse-engineering — probably a sequence of length-prefixed UTF-8 strings indexed by position. A small dedicated helper in the binary module covers parsing it; first implementation step is figuring it out empirically against the user's save.

Not a parsing blocker — without 10f, lookup-indexed values surface as `Integer` instead of `String`, which is wrong but parseable. Lower priority than 10e. Useful when correct values matter (DSL editing, search queries comparing against expected string literals, the token-mapping work the maintainer is currently focused on).

#### 10h. Binary-encoding metadata for round-trip

Forward-looking work for binary→AST→binary lossless round-trip. No writer exists yet; this phase adds the kwargs so primitives carry their source binary encoding, and the future writer dispatches on it to emit the original wire shape. Same `token_index:`-style metadata pattern from 10e — optional kwarg, equality/hash ignore it, the writer matches on the constant to recover wire shape.

Most primitives need exactly one new kwarg, `binary_encoding:`, taking a `TokenKind::*` constant that fully specifies the wire format (sign, byte width, payload shape). Per type:

- **`Primitives::Integer`** — records `U32` / `U64` / `I32` / `I64`, or any `LOOKUP_*` (08/16/24/08A/16A) when the source was a lookup token that fell back to Integer because no `string_lookup:` was supplied (the 10f wrapper covers the resolved case via `lookup_index:`; this kwarg covers the fallback case for symmetry on round-trip).
- **`Primitives::Float`** — records `F32` / `F64` or any `FIXED_*` (positive widths 1..7 / negative widths 1..7 — 14 variants total, the constant fully specifies width + sign-via-token-range). **Requires wrapping IEEE floats in `Primitives::Float`** — currently the parser emits raw `::Float` for `F32`/`F64` per a deliberate design choice (the binary form has no source-string for `to_pdx`). 10h shifts that: `Primitives::Float`'s BigDecimal storage represents the IEEE bits exactly, so the wrap is lossless, and the metadata is what carries the F32-vs-F64 distinction the raw `::Float` couldn't.
- **`Primitives::String`** — no new metadata. `quoted` already distinguishes `QUOTED` / `UNQUOTED`; `token_index` (10e) covers token-encoded shapes; `lookup_index` (10f) covers lookup-index resolution. Fully covered.
- **`Primitives::Date`** — int32 hours-since-epoch is empirically the only wire shape, so no per-instance kwarg needed. But: the *forward* parsing path needs a token-name allowlist (`date_tokens:` kwarg or class-level list) — today only the literal `key == "date"` triggers the int→Date conversion, but EU5 saves carry multiple date-typed fields (`last_battle_date`, etc.) that currently flow through as raw integers. Empirically catalog the date-typed token names during implementation.
- **Booleans** — single token, two values; the writer emits `TokenKind::BOOL` + 1/0 regardless. No metadata; raw Ruby `true`/`false` stays as-is, consistent with the existing "don't wrap booleans" decision.

Plaintext-derived primitives have `binary_encoding: nil`; the writer picks a default ("smallest token that fits" for ints/floats) so plaintext→binary doesn't need exact-shape knowledge. The engine appears tolerant of any legal encoding for a given value — the wire format itself has multiple legal encodings for the same logical value (e.g., `U32` and `I32` both represent positive 32-bit ints), which strongly implies the engine reads what it gets rather than expecting a specific shape per field.

Not blocking anything; pure round-trip prep. Lands when a binary writer becomes the next priority — either a `to_pdx_binary` API for the existing Document or a save-editing workflow on the binary side.

#### Suggested sequence

10a → (10b in parallel with 10c) → 10d. 10a is the prerequisite for both parser paths; 10b and 10c are independent — either order works.

**Save-file parsing path:** 10a → 10c → 10e → 10g → 10f → 10h. 10a/10c/10e/10g are landed; the EU5 gamestate parses end-to-end. 10f and 10h are independent follow-ups — 10f gives string-value correctness for `LOOKUP_*` tokens (currently parseable but wrong); 10h is round-trip prep that lands when a binary writer becomes the next priority. The grammar and accessor pieces (10b, 10d) can come later when a script-side or DSL-side consumer surfaces.

## Decision log

Captured here so we don't re-litigate them.

- **Tests before migration.** Without a regression net, FFI/dep migrations silently break subtle behavior (whitespace preservation, BOM, `single_line!`, encoding round-trips, `method_missing` dispatch).
- **Phase 1 split, interleaved with phase 2.** The original plan had phase 1 finish before phase 2. After landing the scaffolding (1a) we hit a wall: any further phase-1 work needs the Rust extension loadable in CI, which means reproducing the rutie/Ruby-3 hacks — i.e. fighting exactly what phase 2 deletes. New ordering is 1a → 1b (PancakeTaco round-trip, local-only, run before+after magnus) → phase 2 → 1c (unit fixtures + parse smoke, now CI-capable). Risk acceptance: the magnus port is more likely to break wholesale than to drift subtly on untouched paths, so a round-trip canary against the example mod is sufficient pre-migration coverage. If something breaks beyond what the harness catches, `git revert` to a working commit is the fallback.
- **magnus over rutie or rolling our own.** rutie is abandoned; rolling our own reinvents what magnus already solved.
- **2c absorbed into 2b.** Original plan split the magnus port across two PRs (lib.rs in 2b, search.rs in 2c). Cargo can't carry both `rutie` and `magnus` simultaneously without ABI conflicts (they're competing bindings to the same Ruby C API), and `Init_paradoxical` sets up both `Paradoxical::Parser` and `Paradoxical::Search::Parser` in one init call — so a half-ported state isn't really expressible. Cleaner to flip both files in one PR.
- **Phases renumbered after phase 4 went empty.** The original plan had phase 4 as "Rust idiom uplift" and 5a/5b as bug-fixes / game-namespaced DSLs. The magnus port (phase 2b) subsumed the Rust idiom work, leaving 4 reserved-but-empty next to 5a/5b. After 1a-d and 2a-d landed, 5a was renamed to 4 and 5b to 5 so the remaining work proceeds in clean numerical order. References to "5a"/"5b" in pre-renumber commits/PRs/AGENTS.md are historical.
- **Phase 8 added; Float deferral moved out of phase 4.** Phase 4 was originally going to absorb the "Float → fixed-precision" cleanup as a deferred 4f item, but the calendar-support discussion surfaced a parallel concern (game-aware `Date#to_pdx`) with the same shape — a primitive type wanting richer representation. Both moved to a new phase 8 explicitly gated on "concrete need surfaces," and explicitly stdlib-only (no external gems, no custom calendar/decimal abstractions). The reasoning: external gems can be abandoned (lesson from rutie), and downstream mod authors shouldn't have to learn a `Paradoxical::Calendar` abstraction when stdlib `Date` is what they already know.
- **Phase 8 expanded to cover the "distinct primitive types for string-like patterns" family.** Phase 4d's grammar work surfaced that the parser silently accepts a lot of malformed syntax because the engine treats several syntactically-distinct PDX concepts (percentages, parameter substitutions, localization refs, computation expressions, variable refs) as separate types — paradoxical lumps them all under `Primitives::String`. Phase 8 absorbs that family of "deserves its own typed primitive" items. Each gets validated by a dedicated pest rule (the parser becomes properly strict for the patterns the engine itself recognizes) and a typed DSL helper. Phase 4d-B5 specifically should tackle the `-$NAME$` parameter case via the typed `Primitives::Parameter` shape rather than just widening grammar.
- **Color rework split into 8a / 8b.** The original phase-8 plan filed the color work as a single "hsv360 conversions ride along with Color rework" bullet. During implementation it grew into a foundation/math split worth doing as two PRs: 8a (subclass hierarchy + conversion API rename + grammar de-atomization, with current NotImplementedError preserved for the math fixes) shipped first as a regression baseline; 8b followed with the validation and the math. Each ran on green parse smokes (22k+ files) before merge so any real-data regression would have surfaced at the seam between them.
- **Per-component color interpretation rule.** Empirical data ruled out the originally-planned "all-int-or-all-float" homogeneity validation: HSV ships mixed Integer + Float in real Stellaris lighting files, and HDR-extended values blow past 0..1 ranges. Settled on: each component reads its own type (Integer → /scale, Float → as-is); validation stays permissive where data demands it (HSV none; RGB with Integer 0/1 polymorphism); HDR values flow through unclamped. Output type (Integer vs Float RGB) decided dynamically from the presence of HDR-extended values so the brightness multiplier survives conversion. Same shape may apply to future numeric primitives that show similar variance.
- **Custom calendar over stdlib Date impersonation (8c).** Discussed adding `Date#to_pdx` to `core_extensions.rb` so users could pass Ruby Dates through. Rejected: arithmetic on stdlib Date can land on Feb 29 (real-world leap day, in-game-invalid) and surface as wrong-day bugs much later. Building `Calendar365` / `Calendar360` outright is small — no leap years, regular month lengths, no time / timezone / locale / format complexity.
- **Permissive parse, calendar = arithmetic engine, not validator (8c).** Original framing was "guarantee in-game-valid dates by construction" — i.e. validate at parse time. Empirical sweep refuted: real game data ships sentinel dates (`0000.00.00`, `1.0.1`) and Feb 29 dates that the engine itself accepts. Same pattern as the color homogeneity rule — empirically validate the rule before committing to it. Settled on: parse permissively, attach the calendar as arithmetic metadata, garbage-in / garbage-out for the arithmetic on engine-invalid inputs. Round-trip preservation is the load-bearing property; "valid by construction" was aspirational.
- **Imperator BC support via integer-year math, no subclass (8c).** Originally planned as `Calendar365` + `ImperatorCalendar < Calendar365` with an `allows_bc?` flag. Once we dropped construction-time validation, the BC distinction stopped paying for itself — `Calendar365#to_day_count` works on any integer year via Ruby's `divmod`-with-negative-floor semantics. Single class handles every non-Stellaris game including Imperator.
- **BigDecimal over Integer × scale for floats (8d).** Originally planned as either-or. EU5 game-data floats carry 4-6 digits of precision (with 6 a soft limit), so fixed-scale Integer doesn't fit — precision varies per file. BigDecimal is stdlib, arithmetic plugs into the Impersonator concern's existing comparison/infix delegation through `to_real`, and the migration surface is one-line (`PropertyMatcher#matches?`'s `is_a?(::Float)` check). PancakeTaco is the only consumer so the broader Ruby-side audit is tiny.
- **Synthetic fixtures + env-var-gated integration.** Avoids any question of shipping Paradox-owned data.
- **One PR per dep bump.** Activesupport especially is high-risk; isolating the changes makes regressions trivially bisectable.
- **No type coverage on the DSL.** The metaprogramming-heavy `method_missing` surface costs more in friction than it returns in safety.
- **Game-namespaced DSL via mixin.** Mirrors the existing jomini-version dispatch in `Game`, avoids inheritance gymnastics.
- **Phase 10 added: compound keys.** Surfaced when both the script and binary parsers failed mid-EU5-save at the `}={` shape — Paradox saves encode "map keyed by sub-list" structures (e.g. demand-spec → pop IDs) the existing grammar and binary `read_next` flow can't express. New phase rather than a slot under phase 8 because this is a `Property` *shape* extension, not a new primitive — different concern, different file surface. Structurally independent of 8e and 9 so can run in parallel; the only ordering is internal (10a audit → 10b/10c parser paths → 10d accessors).
- **Unified `Primitives::String` w/ source-token kwargs for 10e and 10f.** EU5 binary saves resolve identifier-shaped values through three distinct tokenizations: key tokens via per-game `tokens:`, value tokens via the same (10e), lookup-indices via per-save `string_lookup:` (10f). Considered typed wrappers (`Primitives::TokenRef`, `Primitives::LookupRef`) mirroring `VariableRef`'s pattern from 8e-2. Rejected because the *Ruby-side semantic* in all three cases is the same — an identifier-shaped string — and inventing wrappers would make binary↔plaintext asymmetric (plaintext produces `Primitives::String`, binary would produce typed wrappers). Settled on `Primitives::String` carrying optional `token_index:` / `lookup_index:` round-trip metadata that equality/hash ignore. Future binary writer dispatches on which kwarg is set. The shape difference vs. 8e-2's `VariableRef`: the script grammar itself distinguishes `@varname` from a plain string, so a typed primitive is engine-symmetric; the binary tokenizations are pure compression of identical string semantics, so a single primitive type with metadata is the symmetric fit.
- **Smoke parallelism: nogvl + Thread pool, not Ractors.** Investigated a Ractor-pool architecture for `parse_file` (each parse dispatched to a worker Ractor; `parse_file` returns a `Future`; `parse_files` becomes `files.map { parse_file(f) }.map(&:value)`). Working implementation preserved on the `experiment/ractor-pool` branch. Net result: doesn't beat the simpler nogvl + Thread pool approach already on main, and runs slower than serial parse for small per-file workloads. Measured at 250-290 files/s (Ractor pool) vs 318 files/s (serial) vs 470 files/s (nogvl + threads) on imperator. The per-job dispatch overhead (Ractor#send + port.receive + future lifecycle) dominates the parallelism win when each parse is ~3 ms. Even the simplest sliced-Ractor design (no pool, no future infrastructure) tops out at ~2x scaling — same Amdahl wall as nogvl. To revisit if Ruby's Ractor implementation matures or if a future workload (much larger files, or many concurrent Game instances) shifts the per-parse cost enough to amortize the message overhead. The `rb_ext_ractor_safe(true)` flag is set in the magnus init so users CAN call `Paradoxical::Parser.parse` from non-main Ractors in their own code; the framework just doesn't itself.

# Phase 4c Triage: Remaining Allowlist Entries

A breakdown of the **222 files** still allowlisted across the four PDX games after phases 4b-i and 4b-ii landed. Each cluster is grouped by root cause so phase 4d can pick fixes by impact-per-effort rather than file-by-file.

Methodology: a throwaway script (`/tmp/triage.rb`) walked each game with the smoke's filtering rules and captured `{path, line, col, expected, source}` per failure. Failures were then clustered by pest's "expected" message and top-level directory. Representative files were sampled to confirm the pattern.

## Counts at triage start

| game | files | clusters |
|---|---:|---:|
| europa_universalis_iv | 118 | 6 distinct |
| europa_universalis_v | 54 | 8 distinct |
| stellaris | 35 | 7 distinct |
| imperatorrome | 15 | 6 distinct |
| **total** | **222** |  |

Numbers below are estimates from cluster analysis; some files belong to more than one cluster (the fix sequence matters).

---

## Category A — Mis-categorized non-script files (filter cleanup)

These slipped past the basename / path-substring filters. Right answer is to extend those filters, not allowlist. Cheap and obvious.

**Files to add to basename exclusions:**

| file | game | content |
|---|---|---|
| `LICENSE.txt` | Stellaris | Apache License text (capital L; current filter has `OFL.txt` and `license-fi.txt` only) |
| `HOW_TO_MAKE_NEW_SHIPS.txt` | Stellaris | Documentation prose |
| `99_README_GRAMMAR.txt` | Stellaris | Localization doc |
| `TODO.txt` | Imperator | Plain prose note |
| `trigger_profile.txt` | EU4 | Debug profiler dump (`11808{}95` style) |

**Files to add to path-substring exclusions:**

| substring | game(s) | reason |
|---|---|---|
| `/tests/` | EU4 (4 files) | AI test harness scripts (`echo Standard scenario...`) — debug REPL syntax, not Clausewitz script |

**Suggested cluster delta:** ~10 files moved from allowlists to filters. Reduces noise without grammar work.

---

## Category B — High-value grammar fixes (one fix unblocks many)

Sorted by estimated impact.

### B1. Non-ASCII identifiers in `unquoted_string` (~68 EU4 files)

**Pattern.** EU4 country files contain ship/leader/general names with non-Latin Latin characters (Latin-1 supplement and Latin Extended-A): `Élou`, `Çandarli`, `Šubic'`, `Ärger`, etc.

Example (`common/countries/Air.txt:111`):
```
Élou Ésou Ekahi Eys Aqjun Tahenkat Amayas Ahulil Tafuk Tallit Etran Elkessan
```

**Why it fails.** Grammar:
```
unquoted_string = { ( ( ( "@" | "_"+ | "$" ) ~ ASCII_ALPHANUMERIC ) | ASCII_ALPHANUMERIC ) ~ ( !( break_character ) ~ ANY )* }
```

The first character must be `ASCII_ALPHANUMERIC`. `É` (U+00C9) isn't ASCII, so the rule fails. The parser falls through and reports "expected gui_kind, gui_type, scripted_kind, primitive, or operator."

**Fix.** Replace `ASCII_ALPHANUMERIC` with a broader Unicode letter class — pest supports `XID_START` / `XID_CONTINUE` (Unicode standard identifier characters) or `LETTER` / `LETTER_NUMBER` / `MARK` / `NUMBER` etc. Conservative choice: `( ASCII_ALPHANUMERIC | (LETTER ~ ANY) )` for the first-char alternative; keep the existing `(!break_character ~ ANY)*` for the tail since it already accepts any non-break-character.

**Estimated reach.** ~60 country files (`common/countries/*`) + ~8 more (`common/customizable_localization/*`). EU4 baseline drops from 118 → ~50.

**Risk.** Low. Strictly widens what `unquoted_string` accepts; no previously-valid input is rejected. Round-trip preserved (unquoted strings store the raw bytes).

### B2. `---` placeholder values (~37 EU4 files)

**Pattern.** History files use literal `---` as a "no value" placeholder.

Example (`history/diplomacy/hre.txt:11`):
```
1806.7.12 = { emperor = --- }
```

**Why it fails.** Grammar requires a `primitive` after the operator. `---` doesn't match any primitive (not numeric, not string-shaped per `unquoted_string`'s required-leading-alphanumeric). Parser reports "expected: numeric" (because pest reaches the `numeric` alternative inside `integer` last).

**Fix options.**

1. Add a `placeholder` primitive that matches `"-"+`. Smallest change. Stored as a Primitives::String with the raw `---`. Round-trip preserves.
2. Loosen `unquoted_string` to accept a leading `-` followed by `-`. Risk: ambiguity with negative numbers.

Option 1 is cleaner.

**Estimated reach.** ~33 history files + ~4 common files (`change_tribal_land = ---`, `set_revolution_target = ---`). EU4 → ~13.

**Risk.** Low if scoped to literal `---` (or `-`+ followed by break_character) without bleeding into number parsing.

### B3. `hsv360` color format (22 EU5 files)

**Pattern.** EU5 introduced `hsv360 { H S V }` where H is degrees (0–360) and S/V are integers (0–100), in addition to the existing `hsv { ... }` (0.0–1.0 floats) and `rgb { ... }`.

Example (`in_game/common/climates/00_default.txt:110`):
```
debug_color = hsv360 { 49 35 71 }
```

**Fix.** Extend the `color` rule:
```
color = @{ ( "hsv360" | "hsv" | "rgb" ) ~ ws ~ "{" ~ ( ws ~ ( integer | float ) ){3} ~ ws ~ "}" }
```

(Order matters — `hsv360` must precede `hsv` because pest is left-to-right longest-match within an alternation.)

`Primitives::Color` stores the raw text including the type prefix, so its `type` accessor will return `"hsv360"` for these. Downstream code that branches on `rgb?` / `hsv?` will treat `hsv360` neither — that's actually the right behavior (HSV360 != HSV) but worth a follow-up if anyone wants `hsv360?`.

**Estimated reach.** 22 EU5 files. EU5 baseline 54 → 32.

**Risk.** Low. Strictly additive.

### B4. 4-component RGB (alpha channel) (9 Stellaris files)

**Pattern.** Stellaris uses `rgb { r g b a }` for some color values.

Example (`common/map_modes/00_map_modes.txt:44`):
```
value = rgb { 235 0 18 0 }
```

**Fix.** Loosen the `color` rule's component-count from `{3}` to `{3,4}`:
```
color = @{ ( "hsv360" | "hsv" | "rgb" ) ~ ws ~ "{" ~ ( ws ~ ( integer | float ) ){3,4} ~ ws ~ "}" }
```

**Estimated reach.** 9 Stellaris files. Stellaris baseline 35 → 26.

**Risk.** Low. The `Primitives::Color#colors` accessor returns an Array with whatever number of components was parsed; downstream `to_pdx` reproduces verbatim.

### B5. Negative-prefixed `-$PARAMETER$` substitution placeholders (~6 Stellaris files)

**Pattern.** `$NAME$` parameter substitution is supported across **all** PDX games — it's the engine's parse-time placeholder syntax — and the bare positive form already works post-B1 (the `$` prefix branch in `unquoted_string` matches the leading, the closing `$` rides in via the tail). Stellaris is the only game that uses the *negative-prefixed* `-$NAME$` form, used in `inline_scripts/` to subtract parameter values, and that's the actual remaining bug.

Example (`common/inline_scripts/jobs/industrial_districts_factory_add.txt:56`):
```
job_artisan_add = -$AMOUNT$
```

**Why it fails.** The leading `-` doesn't match `unquoted_string`'s leading-character alternatives (none of `(LETTER|NUMBER)`, `("@" | "_"+ | "$") ~ ...`, or bare `"_"+`). It also doesn't match integer or float (no numeric after the sign). Falls through to "expected: primitive."

**Fix.** A dedicated `parameter` primitive that handles the optional sign:

```
parameter = @{ ("-" | "+")? ~ "$" ~ (LETTER | NUMBER)+ ~ "$" }
```

Ordered before `string` in the `primitive` alternation so the prefixed form gets matched here rather than partially consumed elsewhere.

**Estimated reach.** ~6 Stellaris files (the `-$NAME$` cases). Bare positive `$NAME$` cases without a leading sign should already be unblocked by B1.

**Risk.** Moderate. The new rule's ordering matters — must come before `string`/`unquoted_string` so the negative-prefixed form gets matched as a parameter.

---

## Category C — Game-specific grammar additions (moderate)

Each addresses one game's quirks, narrower scope.

### C1. EU5 `load_template` directive (7 files)

Example (`main_menu/gfx/map/city_data/ashanti.txt:316`): `load_template player_buildings {`. EU5 uses `load_template <name> { ... }` as a top-level directive that mirrors `gui_kind` / `scripted_kind`. Add `load_template` as a new keyword in the `keyable_list` alternation.

### C2. EU5/Imperator `cylindrical{}` and `hex{}` color formats (~5 files)

`position = cylindrical { 210 30 10 }` and `color = hex{ 0xffffffff }` — additional color/coordinate constructor formats. Could be folded into the same rule as `hsv360` (B3) or get their own primitive. Hex notation specifically would need a `0x[0-9a-fA-F]+` integer literal.

### C3a. Stellaris `[[NAME] body ]` parameter-conditional blocks (8+ files)

Stellaris's `inline_scripts/` and shared `scripted_effects/` / `script_values/` / `scripted_triggers/` use a parameter-conditional template syntax:

```
revolt_situation_low_stability_factor = {
    base = @stabilitylevel2
    [[ALTERED_STABILITY]
        subtract = $ALTERED_STABILITY$
    ]
    mult = 0.2
}

pop_group_transfer_ethic = {
    [[POP_GROUP]
        $POP_GROUP$ = { save_event_target_as = source_pop_group }
    ]
    [[!POP_GROUP]
        weighted_random_owned_pop_group = { ... }
    ]
}
```

Body between `[[NAME]` and the matching `]` is emitted only if the parameter `NAME` is set when the script is invoked. The negation form `[[!NAME] body ]` emits when `NAME` is *not* set.

**Why it fails.** The opening `[[` and closing `]` aren't recognized by any rule. The opening looks like a `localization_string` (`[ ... ]`) start but immediately fails on the inner `[`. Falls through; eventually fails when reaching the unmatched `]` deep in the file.

**Fix shape.** A new structural rule, allowed wherever expressions are allowed (lists, keyless_lists):

```
parameter_block = { "[[" ~ "!"? ~ unquoted_string ~ "]" ~ expression* ~ ws ~ "]" }
```

Then a new `Paradoxical::Elements::ParameterBlock` Ruby class storing the parameter name, the negation flag, and the inner children. Round-trip preserves the textual form.

**Estimated reach.** 8 confirmed Stellaris files via the smoke + spot-check; pattern is common enough in scripted_effects (8000+ line files use it heavily) that fixing it could also unblock other allowlisted files whose first observed error wasn't `]` but whose later content uses the construct. Worth running smoke after to see secondary unblocks.

**Risk.** Low. New rule, additive, can't shadow existing matches because nothing else starts with `[[`. The body holds expressions which the parser already knows how to handle.

### C3b. EU5 `code [[ ... ]]` opaque code blocks (~3 files)

Example (`main_menu/gfx/map/city_data/templates.txt:4`): `code [[`. EU5 city_data templates embed what looks like an opaque code block (Lua or GDScript-shaped). Content between `[[` and `]]` is freeform — not parsed as Clausewitz script. Different shape from C3a (true double-bracket pairs, opaque body).

Could be handled by a `code_block = { "code" ~ ws ~ "[[" ~ (!"]]" ~ ANY)* ~ "]]" }` rule, stored as a primitive that holds the raw inner text. Lower priority than C3a (fewer files).

### C4. Negative dates (~2 EU4 files)

Example (`common/great_projects/01_monuments.txt:308`): `date = -2500.01.01`. Imperator: Rome-era BC dates that EU4 also uses for great projects. Currently the `date` rule requires `ASCII_DIGIT{1,4}` for the year — no leading sign. Add an optional `"-"?` prefix.

### C5. Top-level identifiers without `=` (~2 EU4 files)

Example (`common/graphicalculturetype.txt:2`): `easterngfx` standalone. Some EU4 config files are bare-identifier-per-line lists. Would need a new top-level rule to accept `primitive ~ NEWLINE` as a kind of statement, distinct from `property` and `list`.

### C6. Trailing `;` (~4 files across games)

Example: `textureFile3 = "gfx//mapitems//trade_route_arrow_terrain.dds";`. PDX `.gfx` files sometimes have C-style semicolons after assignments. Adding optional `";"` to break_character is hacky but small. Risk of unintended interactions with future grammar work.

### C7. Imperator `LIST { ... }` keyword (1 file)

Example (`map_data/climate.txt:3`): `mild_winter = LIST {`. The all-caps `LIST` keyword between operator and `{`. Could be a `gui_kind`-style alternation entry.

### C8. `_` (single underscore) as identifier (1 Stellaris file)

`_ = { 255 0 255 }` in `interface/fonts.gfx`. Single underscore as a key. Currently `unquoted_string` requires `_+` followed by alphanumeric. Loosening to allow bare `_` as a complete identifier is small.

### C9. BOM-mid-file (2 Imperator files)

Imperator's `common/script_values/00_mission_syracuse.txt` and `common/customizable_localization/00_syr_mission.txt` start with a UTF-8 BOM mid-file (or after the first BOM has been stripped, there's another). Likely a tooling artifact. Could be handled by stripping all leading BOMs in `FileParser`, not just the first.

---

## Category D — Tricky / probably won't fix

Files where the right answer isn't a grammar tweak.

| file(s) | issue | recommendation |
|---|---|---|
| `interface/messagetypes.txt` (EU4) | 8000+ line interface config; specific pattern not yet identified — error at L8433 reading `{` standalone. Could be malformed or a deeply-buried grammar gap. | Defer until 4d completes the easier fixes; revisit once the file is more isolated. |
| `interface/credits_l_simp_chinese.txt` (Stellaris) | Localization-as-text file (`--------` separator at L2). Simplified Chinese credits with structure-as-text. | Likely should be excluded; investigate whether `_l_simp_chinese.txt` follows a localization convention to filter on. |
| `interface/contentview.gui` (EU4) | Bare `{` at L28 — preceded by something the parser handled but ate too much. Likely an interaction bug. | Defer; revisit after B1 (B1 may incidentally fix). |
| EU5 `gui` files with EOI-mid-content errors | `}` at line 430 of a GUI file means parser swallowed too much earlier. Likely interaction with `gui_kind` / templating. | Defer; root cause likely in earlier grammar match. |

---

## Suggested phase 4d sequence

In order of impact-per-effort:

1. **Category A cleanup (~10 files)** — extend basename / path-substring exclusions. One small PR.
2. **B1 — non-ASCII unquoted strings (~68 files)** — biggest single win. EU4 drops by more than half.
3. **B2 — `---` placeholder (~37 files)** — second-biggest win. New `placeholder` primitive.
4. **B3 — `hsv360` color (22 files)** — easy. One alternation entry.
5. **B4 — 4-component rgb (9 files)** — trivial. Component count `{3}` → `{3,4}`.
6. **B5 — parameter substitution (~6 files)** — slight care with rule ordering.
7. **C1, C4 — `load_template` (7) and negative dates (2)** — small additive grammar entries.
8. **C2, C7, C8 — `cylindrical/hex`, `LIST`, bare `_`** — narrow but easy.
9. **C9 — multi-BOM stripping** — `FileParser` change, not grammar. Easy.
10. **C3 — `[[ ... ]]` blocks** — moderate; new construct.
11. **C6 — trailing `;`** — hacky; only do if the affected files matter.
12. **C5 — top-level bare identifiers** — moderate; new top-level statement.
13. **Category D** — defer until everything else is shrunk and the remaining files are easier to investigate in isolation.

Estimated reach if 1–6 land: **222 → ~80 across all four games** (EU4 contributes most of the drop). 7–9 would push it under 50. 10+ is diminishing returns territory.

## Re-running the triage

The throwaway script lives at `/tmp/triage.rb` while phase 4c is fresh; if it gets useful for 4d sub-PR verification, it could move to `bin/` or be folded into the smoke spec as an opt-in mode. For now the smoke's existing `PARADOXICAL_PARSE_SMOKE_DUMP=<path>` env var covers most of the shrinkage-verification need.

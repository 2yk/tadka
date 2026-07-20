# Project Tadka — "Spice Route"

A premium roguelike deckbuilder for iOS/Android: you cook dishes from a pantry of ingredient cards,
poker-style patterns become regional dishes, utensils multiply the score into absurd numbers.
Solo project, no backend, no ads/IAP.

**Current state: M0 graybox — the fun-check.** The whole game is one self-contained web file
([`web/tadka.html`](web/tadka.html)) whose only job is to answer GO / NO-GO on the core loop.
Ugly is correct; fun is mandatory. M1 is a rewrite in Flutter + Flame — the web build is
deliberately throwaway *except* for its logic layers, which are structured to port 1:1 to Dart.

## Docs, in authority order

| File | What it is |
|---|---|
| [`spice-route-concept-doc.md`](spice-route-concept-doc.md) | The vision — theme, full v1.0 scope, art brief, milestones, business case. Aspirational; most of it is not built. |
| [`tadka-m0-build-spec.md`](tadka-m0-build-spec.md) | The contract for what M0 must contain. **Scoring order-of-operations in §4 is normative** — the engine implements it exactly. |
| [`web/README.md`](web/README.md) | What actually shipped, how to test on a phone, balance findings, and the port table. Closest to the truth. |
| [`web/asset-pack/DESIGN-SYSTEM.md`](web/asset-pack/DESIGN-SYSTEM.md) | "Midnight Bazaar" art direction — tokens, type, components, motion spec. |

Where the concept doc and the shipped build disagree, the build wins — it has been tuned against
the simulator. Note the concept doc still describes an 8-city run; M0 ships 3 cities.

## Layout

```
web/tadka.html          THE GAME. 1648 lines, zero dependencies, zero build step.
web/game-core.mjs       GENERATED mirror of the pure layers — do not hand-edit (see below).
web/data/*.json         Schema documentation + future Flutter assets. NOT loaded at runtime.
web/asset-pack/         Generated SVG art + generate_assets.py + the design system.
tools/sim.mjs           Headless balance simulator (greedy bot, win-rate per stake).
tools/extract-core.mjs  Regenerates game-core.mjs from tadka.html.
```

`tadka.html` is sectioned so each block maps to a future Dart package. Nothing touches the DOM until `§UI`:

| Section | Lines | Ports to |
|---|---|---|
| `ART` blob + `§ART` | 255–307 | `apps/mobile` — inline SVG skin |
| `§RNG` | 309–327 | `game_core` — seeded PRNG (`makeRng`) |
| `§CONTENT` | 328–463 | `content` — already valid JSON shapes |
| `§ENGINE` | 464–606 | `game_core` — `bestPattern`, `scoreDish`, `dishError` |
| `§PROGRESSION` | 607–739 | `game_core` + meta — stakes, decks, achievements, unlocks |
| `§RUN` | 740–908 | `game_core` — run state machine, economy, bazaar |
| `§UI` | 909–1648 | `apps/mobile` — throwaway shell |

## The one invariant that will bite you

`web/game-core.mjs` is a **byte-for-byte extract of `tadka.html` lines 309–908** (§RNG through §RUN),
wrapped in a Node shim and an export block. It exists so `tools/sim.mjs` scores *exactly* like the
game, with no parallel implementation that can drift.

**`tadka.html` is the source of truth. Never hand-edit `game-core.mjs`.** After changing anything in
§RNG..§RUN:

```bash
node tools/extract-core.mjs           # regenerate
node tools/extract-core.mjs --check   # verify sync; exits 1 on drift
```

The same discipline applies to `web/data/*.json` and the inline `STAKES` / `DECKS` / `ACHIEVEMENTS`
tables — those are hand-maintained duplicates, and **editing the JSON changes nothing in the game**.
Change the inline copy in `tadka.html` too, or the JSON is a lie.

## Hard constraints on `tadka.html`

These are why the file looks the way it does. Breaking one breaks phone testing.

- **Single self-contained file.** No build step, no bundler, no `package.json`, no npm deps.
- **No network at runtime.** No `fetch`, no `import`, no XHR. It must work from `file://` and under
  the strict CSP of a hosted Artifact. Google Fonts is a soft `@import` with a serif/system fallback;
  everything else — all art — is inline SVG in the `ART` blob.
- **Classic script, not a module.** No `type="module"`. Every top-level binding is global, which is
  how you poke the engine from the browser console: `scoreDish(...)`, `bestPattern([...])`, `RUN`.
- **Portrait, thumb-zone layout.** The empty space above the action bar is intentional.

## Commands

```bash
# Play it
open web/tadka.html                       # file:// works
cd web && python3 -m http.server 8000     # then http://<mac-lan-ip>:8000/tadka.html on a phone
                                          # LAN IP: ipconfig getifaddr en0

# Balance
node tools/sim.mjs                        # win-rate ladder, all 8 stakes, 500 runs each (~30s)
node tools/sim.mjs --stake 3
node tools/sim.mjs --stake 8 -n 2000 --deck royal

# Engine sync
node tools/extract-core.mjs --check
```

Verified 2026-07-20 on Node v24.12.0 / Python 3.11.4 — both present on this machine, despite
`web/README.md` and `tools/sim.mjs` headers saying Node was unavailable when they were written.
Current ladder at 200 runs: Paprika 26%, Jalapeño 3%, everything above ~0–1%. That matches the
in-browser figures in the README and meets the spec's acceptance bar (monotone, stake 8 ≤ 2%),
but the upper stakes are steep for the bot because the coin→Kitchen-level loop is economy-sensitive.
They are config and want real-play data before a tuning pass.

## Tuning is data, not code

Change a number, reload. No logic touched. All of these live in `§CONTENT` / `§PROGRESSION` of
`tadka.html` (and mirror into `game-core.mjs` via the extractor):

`CITIES` (score targets) · `UTENSILS` · `PALATES` · `CRITICS` · `LEVEL_BONUS` (Festival/recipe
scaling) · `RARITY_WEIGHTS` · `STAKES`.

Two load-bearing balance facts, both hard-won — don't undo them without re-simming:

- **Festival recipe-leveling is the scaling engine.** Without it a maxed build caps around 15k and
  Naples (18k–50k) is impossible for everyone. Leveled base × utensil multipliers is what makes the
  late targets reachable.
- **Kochi's Minimalist boss is 1200, not the spec'd 2000.** Max-3-cards caps you at Three-of-a-Kind,
  which made an all-flavor build mathematically capped at ~1572 — unwinnable.

Naples' finale critic is fixed to The Traditionalist on purpose; rolling Minimalist on a 50k target
was unwinnable at any level.

## Effect DSL

Utensils are pure data so content scales without engine changes. The M0 build extends the spec's
starter key set — **keep these in the Dart validator's allow-list**:

- conditions: spec's `all_cards_family`, `contains_family`, `min_cards`, `pattern_is`, `card_family`,
  `is_first_dish`, `is_last_dish` — plus `num_cards`, `all_cards_same_family`, `pattern_at_least`
- effects: spec's `flavor_add`, `heat_add`, `heat_mult`, `retrigger_highest`, `coin_add`,
  `flavor_per_card` — plus `heat_per_card`, `copy_right` (Grandmother's Ladle)

The validator must reject unknown keys. That discipline is what keeps 100+ future utensils safe.

## Things to preserve

- **The Coach (`§UI`, ~1014–1320) drives the live engine.** It calls `scoreDish` / `bestPattern` /
  `dishError` / `rollOffers` rather than reimplementing scoring, so every number it shows is exactly
  what the game will score. If you touch it, keep that property — a parallel solver that drifts is
  worse than no Coach.
- **Seeded determinism, with entropy only at the boundary.** One seeded RNG (`makeRng`) owns every
  shuffle and shop roll, so a run is a pure function of (seed, stake, deck, player choices). Same
  seed → identical run. This underwrites bug reports, seed sharing, the future Daily Route, and the
  determinism golden test.

  `Math.random()` is legitimate in exactly two places, and **`game-core.mjs` must stay at zero**:
  `randomSeed()` (`§UI`), which mints the seed *before* the run starts, and particle VFX
  (~1525–1532), which never touches game state. Anywhere else it breaks reproducibility silently.

  Note that a blank seed field is **not** an unseeded run — it generates a `SPICE-XXXXX` code and
  seeds normally, so every run stays replayable from the summary screen. The seed alphabet omits
  `I`/`O`/`0`/`1` because players read seeds off a phone and retype them; keep it that way.
- **Unlocks are never lost on death.** `loadProfile` merges over `defaultProfile()` so added fields
  survive old saves; "Show step tips again" resets tips but must not touch the profile.

`localStorage` keys: `tadka_profile_v1` (meta-save, write-through) · `tadka_coach` · `tadka_seen` ·
`tadka_tipsoff`. All accesses are `try/catch`-wrapped for CSP/Artifact safety.

## Known gaps

- **No automated tests, no CI.** The README's "22 hand-computed golden cases pass" describes ad-hoc
  browser-console sessions that were never committed. `tools/sim.mjs` is the only executable check
  in the repo, and it verifies balance, not correctness. Those golden cases become real tests in the
  Dart `game_core`.
- **`tadka-progression-spec.md` is referenced twice by `web/README.md` but is not in the repo.**
  The progression layer was built from it, so it exists somewhere — it just was never committed.
- **`web/asset-pack/generate_assets.py` writes to a hardcoded `/mnt/user-data/outputs/tadka-assets`**
  (a sandbox path). Edit `OUT` before running it here. Its output is also not wired to the game:
  the `ART` blob in `tadka.html` is hand-pasted, so regenerating art is generate → copy → inline,
  all manual.

## Working conventions

- Commit non-breaking changes automatically, with a clear message. **Never add a co-author line.**
- Anything needing a human decision or a device check: stop, and end with the commit message plus
  explicit "how to test this" steps.
- M0 deploys nowhere. Device builds and the local server only.

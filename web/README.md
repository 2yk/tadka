# Spice Route — M0 Graybox (web prototype)

The playable **fun-check** build for Project Tadka, per [`tadka-m0-build-spec.md`](../tadka-m0-build-spec.md).
Skinned with the **"Midnight Bazaar"** art direction ([`asset-pack/DESIGN-SYSTEM.md`](asset-pack/DESIGN-SYSTEM.md)):
parchment ticket cards with inline ingredient SVGs, circular utensil badges with rarity rings, per-city
backdrops, critic medallions, Fraunces/Inter type, and the motion spec (count-up pop, per-card particle
bursts, big-multiplier screen shake). Colors, layout, and motion follow the design tokens; icons are the
placeholder set a human artist upgrades later.

It's a single self-contained file — [`tadka.html`](tadka.html) — no build step, no dependencies. All art is
inline SVG (embedded from `asset-pack/`); Fraunces + Inter load from Google Fonts where allowed and fall
back to a serif / system stack under strict CSP (e.g. the hosted Artifact). Runs on any modern phone browser.

## How to test on your device

**Easiest — the hosted Artifact (private to your Claude account):**
Open this on your phone's browser:

> https://claude.ai/code/artifact/0d22d79d-8948-4aaa-8d4c-9f7b9fb8ad4a

**Or serve it locally from this Mac** (phone on the same Wi-Fi):
```bash
cd web
python3 -m http.server 8000
# find your Mac's LAN IP:
ipconfig getifaddr en0
# then on your phone open  http://<that-ip>:8000/tadka.html
```

**Or just open the file** — double-click `web/tadka.html` (works on `file://` too).

Add it to your Home Screen (Share → Add to Home Screen) for a full-screen, app-like feel.

## What's in this M0 (matches the spec)

- **3-city mini-run:** Kochi → Tokyo → Naples, 3 services each (Lunch / Dinner / Critic).
- **Full 52-card pantry:** 5 flavor families × ranks 1–10, plus 2 prized cards (Saffron, Ghee).
- **All 9 recipes** with regional dish names per city (Chaat/Onigiri/Bruschetta, Royal Biryani/Kaiseki/Nonna's Feast…).
- **20 utensils** (effect DSL), max 5 equipped, fire left→right.
- **6 spice blends** (consumables): Chili Oil, Sea Salt, Fermentation, Sun-Dry, Whetstone, Mise en Place.
- **Festivals 🎉 (recipe leveling) — the scaling engine.** Festival offers in the Bazaar permanently raise your **Kitchen level**; every recipe's base flavor & heat grow for the rest of the run. Bosses grant free Kitchen levels. This compounding (leveled base × utensil multipliers) is what makes the big late-city targets actually reachable — without it the run caps at ~15k and Naples is impossible.
- **3 city palates** and **2 critics** (The Minimalist at Kochi's boss; The Traditionalist at Tokyo's boss and the Naples finale).
- **Bazaar** between services: 3 offers (utensils / blends / festivals), reroll (2🪙), sell utensils at half.
- **Economy:** 4 base + 1 per unused cook + interest (1 per 5 coins, cap 5).
- **Seeded RNG:** same seed → identical run (great for bug reports & the future Daily Route). Type a seed on the start screen, or "Replay this seed" from the summary.
- **Run summary:** per-service scores, cause of death, seed, Play Again / Replay.
- **Onboarding for testers:** a one-time coach tip appears the first time you reach each step (welcome → cook → recipe/score → boss critic → bazaar → using a blend → summary), each with "Got it" / "Skip all tips". A **?** button on every screen opens a full **How to Play** sheet any time; it also has "Show step tips again" to reset. Seen-state is stored per-browser (`localStorage`), so each tester sees each tip once.

## 🧠 Coach (cheat / learn mode)

Toggle with the **🧠 button** (top-right, next to `?`); the choice persists per-browser (`localStorage`). It's a
solver overlay for players still learning the combos — and it never lies, because it drives the **live engine**:

- **On the cook screen** it brute-forces every legal dish from your hand and lists the **best per recipe, highest
  score first** — each row shows the exact `scoreDish` **breakdown** (base × level, per-card flavor, each utensil
  step, final flavor × heat) plus a one-line strategic *why*. **Tap a row to load those exact cards**, then COOK.
  It obeys the active critic, so it only ever suggests legal dishes.
- **In the Bazaar** it ranks every offer by **real marginal value**: it re-scores a panel of benchmark dishes (Flush,
  Full House, wide spread, Three-of-a-Kind, Pair — across first/last-dish variants) *with and without* each buy, and
  reports the delta. Permanents (utensils & Festivals) are valued across the estimated dishes left in the run, so
  they're compared fairly against one-time blends; the **◎ best buy** is marked with a concrete before→after example
  and the reason. Coin utensils are labelled as economy (not "situational"), and combo pieces (Grandmother's Ladle)
  are flagged as such.

Because it reuses `scoreDish`/`bestPattern`/`dishError`/`rollOffers`, every number the Coach shows is exactly what
the game will score — there's no parallel math to drift. Ports to M1 as a `game_core` solver used by a debug overlay.

## Tuning is data, not code

City score targets live in the `CITIES` array (search `§CONTENT`). Utensil numbers live in `UTENSILS`.
Palates in `PALATES`, critics in `CRITICS`, recipe-level scaling in `LEVEL_BONUS`. Change a number,
reload — no logic touched. This is where your first-run tuning pass happens.

## Balance (sim-verified in the browser)

The engine doubles as a headless balance simulator — run it from the browser console against the live
`scoreDish`/`rollOffers`. Findings that shaped this build:

- **Kochi Minimalist boss** retuned 2000 → 1200 (max-3-cards caps you at Three-of-a-Kind, so an
  all-flavor build was mathematically capped at ~1572 — unwinnable). Now: any heat source ≈ wins,
  the naive build is a fair ~27%.
- **The original targets assumed exponential scaling the engine lacked** — a maxed build capped ~15k,
  so Naples (18k–50k) was impossible for everyone. Fixed by adding **recipe leveling (Festivals)**:
  a full-run sim (300 runs, greedy bot, no blends) now completes **~23% at the original targets**, with
  a clean curve (Tokyo Lunch ~100% → Naples finale ~46% of those who reach it). Skilled humans beat that.
- **Naples' "random" critic** could roll Minimalist on a 50k target (unwinnable at any level) — the
  finale is now fixed to The Traditionalist.
- Economy base income 3 → 4 so a build *and* Festivals are both affordable; boss reward = +3 Kitchen levels.

## Progression layer (stakes · unlocks · endless)

Per [`tadka-progression-spec.md`](../tadka-progression-spec.md). Turns "I won once" into a long tail.
All data-driven — the schemas live in [`data/`](data/) (`stakes.json`, `achievements.json`, `decks.json`)
and are mirrored inline for the self-contained artifact.

- **Stakes — the Heat Ladder** (8 cumulative tiers, Paprika → Carolina Reaper). Winning a deck at stake N
  unlocks N+1 for that deck (5 decks × 8 = 40 goals; shown as a chili grid in the Recipe Book). Modifiers
  fold into the run config only — `service_reward_zero`, `target_scale`, `swaps_delta`, `cooks_delta`,
  `shop_inflation_per_city`, `minor_critic_on_dinner`, `utensil_slots`.
- **Unlocks + meta-save** (`localStorage`, schema §4, write-through). ~12 utensils start available, the rest
  are achievement- or stake-gated; the shop only rolls what you've unlocked. Death never takes unlocks away.
- **Achievements** (event bus: `dish_played`, `service_cleared`, `run_won`, `coins_held`, `utensil_bought`,
  `reroll_count`, …). Each payoff utensil is gated behind performing its own trigger once (First Flush →
  Golden Sieve). `first_dish` fires on run 1 so early runs always unlock something.
- **Secret recipes** — Five of a Kind, Family Feast (Full House, one family), Perfect Palate — reachable only
  via blends; show as **? ? ?** in the Recipe Book until played once.
- **Endless Mode** — after victory, **Continue the Route →**: `CityBase(k)=CityBase(k−1)·(2+0.25(k−1))`,
  service targets `×{0.6,1.0,1.6}`. Distance = endless services cleared → local top-10. Scores go compact
  (`1.2M`, `34.5B`) then engineering past `1e15`.
- **Recipe Book** — the whole collection made visible (recipes, utensils, decks, stake grid), locked items
  as silhouettes.

## The balance sim (`--stake`)

The engine is auto-extracted to [`game-core.mjs`](game-core.mjs) (byte-identical to the inline copy) so the
CLI scores exactly like the game:

```bash
node tools/sim.mjs                     # win-rate ladder, all 8 stakes, 500 runs each
node tools/sim.mjs --stake 3           # a single stake
node tools/sim.mjs --stake 8 -n 2000 --deck royal
```

(Node wasn't installed on the authoring box, so the ladder was verified via the equivalent in-browser sim:
greedy no-blend bot, 200 runs/stake — Paprika ~26% → stake 8 0%, monotone-decreasing with stake 8 ≤ 2%,
meeting spec §1's acceptance. Per tuning directive #1 the stake modifiers are steep for the bot because the
coin→Kitchen-leveling loop is economy-sensitive; they're config and want real-play data before a tuning pass.)

## How this ports to the Flutter/Flame build (M1)

The file is sectioned so each block maps 1:1 to a spec'd package. Nothing touches the DOM until `§UI`.

| Section in `tadka.html` | Spec package | Notes |
|---|---|---|
| `§RNG` | `packages/game_core` | seeded PRNG (mulberry32 + string hash). Swap for `Random(seed)` in Dart. |
| `§CONTENT` | `packages/content` | plain data objects — already valid JSON shapes. Lift straight into JSON assets. |
| `§ENGINE` | `packages/game_core` | `bestPattern` + `scoreDish` implement the exact order-of-operations from spec §4. |
| `§RUN` | `packages/game_core` | run state machine, economy, bazaar rolls. Pure, headless-testable. |
| `§UI` | `apps/mobile` | the throwaway shell. Rebuilt in Flame; the layers above are the keepers. |

**Verification already done in this build** (run in the browser console against the live engine):
22 hand-computed golden cases pass — pattern detection, palate math, utensil **slot order**
(griddle→tandoor = 688 vs tandoor→griddle = 561), retriggers, prized bonus, both critics, and
seeded determinism. These become the `game_core` golden tests in Dart.

### DSL note (carry to Dart)
The spec's starter condition/effect keys were extended slightly so a few utensils could be expressed
purely as data. Keep these in the Dart validator's allow-list:
- conditions: `num_cards` (exact count), `all_cards_same_family`, `pattern_at_least`
- effects: `heat_per_card`, plus `copy_right` (Grandmother's Ladle)

## Known simplifications (fine for a fun-check)

- No `tools/sim` here — the golden-test harness proves the engine instead. The headless
  random-policy simulator is an M1 item (and easier to write once this logic is in Dart).
- Blends apply to your currently-selected cards (tap cards, then tap the blend).
- The layout keeps the action bar in the thumb zone; the empty space above it is intentional.

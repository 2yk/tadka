# Spice Route — M0 Graybox (web prototype)

The playable **fun-check** build for Project Tadka, per [`tadka-m0-build-spec.md`](../tadka-m0-build-spec.md).
Ugly on purpose: colored rectangles, text, and emoji only. One load-bearing piece of juice
(the score count-up ticker) is kept because it's core to game feel.

It's a single self-contained file — [`tadka.html`](tadka.html) — no build step, no dependencies,
no external network calls. Runs on any modern phone browser.

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
- **3 city palates** and **2 critics** (The Minimalist, The Traditionalist; Naples rolls one of the two).
- **Bazaar** between services: 3 offers, reroll (2🪙), sell utensils at half.
- **Economy:** 3 base + 1 per unused cook + interest (1 per 5 coins, cap 5).
- **Seeded RNG:** same seed → identical run (great for bug reports & the future Daily Route). Type a seed on the start screen, or "Replay this seed" from the summary.
- **Run summary:** per-service scores, cause of death, seed, Play Again / Replay.
- **Onboarding for testers:** a one-time coach tip appears the first time you reach each step (welcome → cook → recipe/score → boss critic → bazaar → using a blend → summary), each with "Got it" / "Skip all tips". A **?** button on every screen opens a full **How to Play** sheet any time; it also has "Show step tips again" to reset. Seen-state is stored per-browser (`localStorage`), so each tester sees each tip once.

## Tuning is data, not code

City score targets live in the `CITIES` array (search `§CONTENT`). Utensil numbers live in `UTENSILS`.
Palates in `PALATES`, critics in `CRITICS`. Change a number, reload — no logic touched. This is where
your first-run tuning pass happens.

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

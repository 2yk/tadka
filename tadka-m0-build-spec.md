# PROJECT TADKA — M0 Graybox Build Spec

*Hand this file + `spice-route-concept-doc.md` to Claude Code. M0's only job: let Yeshu play the core loop and decide GO / NO-GO. Ugly is correct. Fun is mandatory.*

---

## 1. Goal & Exit Criteria

Build a playable, text-only prototype of the core loop in 1–2 weeks of sessions.

**GO gate (Yeshu's decision):** after playing, does he voluntarily start run #5 in one sitting? If yes → hire artist, proceed to M1. If no → we diagnose (loop problem vs. tuning problem) or kill the project having spent only time.

**Hard rules for M0:**
- NO art (colored rectangles + text + emoji only)
- NO sound, NO animations beyond basic score count-up
- NO meta-progression, unlocks, daily challenge, or cloud anything
- YES to: complete scoring engine, shop, utensils, a 3-city mini-run, deterministic RNG, tests

---

## 2. M0 Scope

**IN:**
- 3-city mini-run (Kochi → Tokyo → Naples), 3 services each (Lunch / Dinner / Critic) = ~10–15 min per run
- Full pantry: 52 ingredient cards (5 flavor families × ranks 1–10, +2 prized cards)
- All 9 recipe patterns with regional dish names per city
- 20 utensils (list in §6), max 5 equipped
- 6 spice blends (consumables)
- 2 critics (The Minimalist, The Traditionalist)
- City palates (3 defined in §7)
- Bazaar between services: 3 random offers (utensils/blends), reroll for coins, sell utensils at half price
- Economy: coins per service = 3 base + 1 per unused dish + interest (1 per 5 held, cap 5)
- Run summary screen (score history, cause of death)
- Seed input field on the start screen (same seed = same run, for testing and bug reports)

**OUT (deferred):** everything else in the concept doc.

## 3. Tech Setup

- **Stack:** Flutter (latest stable) + Flame. Single repo `tadka`.
- **Packages:**
  - `packages/game_core` — pure Dart, ZERO Flutter imports. All rules, scoring, RNG, run state. This package must be fully unit-testable headless.
  - `packages/content` — JSON assets (ingredients, utensils, blends, critics, palates, dish-name tables) + loader/validator.
  - `apps/mobile` — Flutter/Flame UI shell.
  - `tools/sim` — headless CLI: plays N random-policy runs, prints score distribution, avg death city, utensil pick stats. v0 can be crude.
- **Determinism:** one seeded RNG (`Random(seed)`) owned by game_core; every shuffle/shop-roll draws from it. No `Random()` anywhere else. This gives us reproducible bugs and golden tests.
- **State:** plain immutable-ish Dart classes + a simple reducer pattern (action in → new state out). No heavy state-management framework in M0.

## 4. Scoring Engine — Exact Order of Operations

This is the heart. Implement precisely; write golden tests for each step.

1. Player selects 1–5 cards → detect best matching recipe pattern (evaluate from strongest to weakest: Straight Flush → Four of a Kind → Full House → Flush → Straight → Three of a Kind → Two Pair → Pair → High Card). Straights are runs of intensity ranks; Flushes are single flavor family. Only the cards forming the pattern are "scoring cards"; extras played still trigger "any card" effects but add no intensity.
2. Start with recipe base: `flavor = base_flavor`, `heat = base_heat` (table in concept doc §3.2).
3. Apply city palate modifiers to each scoring card (e.g., Kochi: Sour cards give +50% of their intensity as bonus flavor).
4. For each scoring card **left to right in played order**: add its intensity to `flavor`, then fire per-card utensil triggers **in utensil slot order (left to right)**.
5. After cards: fire per-dish utensil triggers in slot order (flat +flavor first, then +heat, then ×heat multipliers — additive before multiplicative within a slot's effect).
6. Final dish score = `flavor × heat` (floor to int). Add to service total.
7. Critic rules apply as pre-checks (e.g., Minimalist rejects 4+ card dishes) or modifiers (Traditionalist: Sweet cards contribute 0 intensity and don't trigger palate bonuses).

Retrigger effects re-run step 4 for the affected card only.

## 5. Content Schemas (JSON)

```json
// ingredient
{ "id": "spicy_07", "family": "spicy", "rank": 7, "display": "Bird's Eye Chili" }

// utensil — effect DSL keeps content data-driven
{
  "id": "tandoor",
  "name": "Tandoor",
  "rarity": "uncommon",
  "cost": 6,
  "trigger": "on_dish",
  "condition": { "all_cards_family": "spicy" },
  "effect": { "heat_mult": 1.5 },
  "flavor_text": "Everything tastes better slightly burnt."
}

// palate
{ "city": "kochi", "boost_family": "sour", "boost": { "intensity_pct": 50 } }

// critic
{ "id": "minimalist", "rule": { "max_cards_per_dish": 3 }, "target_mult": 1.6 }
```

Supported condition keys (M0): `all_cards_family`, `contains_family`, `min_cards`, `pattern_is`, `card_family` (per-card), `is_first_dish`, `is_last_dish`.
Supported effect keys (M0): `flavor_add`, `heat_add`, `heat_mult`, `retrigger_highest`, `coin_add`, `flavor_per_card`.
The content validator must reject unknown keys — that discipline keeps 100+ future utensils safe.

## 6. The 20 M0 Utensils

Commons (cost 4): Iron Tawa (+30 flavor if 3+ cards) · Mint Garnish (+4 heat if contains Sour) · Salt Cellar (+3 heat if contains Salty) · Honey Jar (+25 flavor if contains Sweet) · Stock Pot (+2 heat if contains Umami) · Street Cart (+1 coin per dish played) · Big Spoon (+20 flavor if pattern is Pair) · Rice Cooker (+30 flavor if pattern is Three of a Kind)

Uncommons (cost 6): Tandoor (×1.5 heat if all Spicy) · Pressure Cooker (retrigger highest card) · Wok (×1.5 heat if all cards same family) · Chai Stall (+2 coins when you play a Pair) · Bamboo Steamer (+5 heat if exactly 3 cards) · Butcher's Block (+40 flavor if pattern is Full House or better) · Ice Box (first dish each service ×2 heat... implement as heat_mult with is_first_dish) · Griddle (+1 heat per card played)

Rares (cost 9): Clay Handi (last dish of each service ×3 heat) · Grandmother's Ladle (copies effect of utensil to its right) · Golden Sieve (Flushes get +50 flavor and +3 heat) · Emperor's Wok (×2 heat if dish has 5 cards)

Shop rarity weights M0: 60% common / 30% uncommon / 10% rare.

## 7. M0 Cities & Targets

| City | Palate | Lunch | Dinner | Critic |
|---|---|---|---|---|
| Kochi | Sour +50% intensity | 300 | 800 | 2,000 (Minimalist) |
| Tokyo | Umami cards +2 heat each | 3,500 | 6,000 | 11,000 (Traditionalist) |
| Naples | Flush dishes +40 flavor | 18,000 | 30,000 | 50,000 (random of the 2) |

Targets are first-guess numbers — expect to retune after sim + play. Tuning targets is a config change, never a code change.

## 8. UI (Ugly on Purpose)

Portrait. Single screen per state:
1. **Service screen:** target + current score top; 5 utensil slots as labeled boxes; hand of 8 cards as colored rectangles (family color, rank number, family emoji); tap to select up to 5; buttons COOK (4 charges) and SWAP (3 charges); score count-up ticker on cook (the one piece of juice M0 keeps — it's load-bearing for fun).
2. **Bazaar screen:** coins, 3 offers with name/cost/description, REROLL (2 coins), NEXT SERVICE.
3. **Run summary:** per-service scores, death cause, seed, PLAY AGAIN.

Family colors: Spicy #E23B22, Sweet #E8A020, Sour #7CB342, Salty #4A90D9, Umami #8E5AA8.

## 9. Testing & Acceptance

- **Unit tests (game_core):** pattern detection (incl. edge cases: 5-card straight vs flush priority, A-low equivalents none — ranks 1–10 only), full scoring golden tests (≥15 hand-computed cases), palate math, each of the 20 utensils, critic rules, economy math, seeded determinism (same seed twice → identical run states).
- **Sim smoke test:** `dart run tools/sim -n 2000 --policy random` completes without crashes; prints distribution. A random-policy bot should clear Kochi sometimes and almost never clear Naples — if random wins full runs, targets are too easy.
- **Content validation test:** every JSON file passes schema check in CI.
- **How Yeshu tests on device:**
  - Android: `flutter build apk --debug` → install APK on phone (or `flutter run` with USB debugging)
  - iOS: `flutter run` to a simulator, or to his iPhone via Xcode free provisioning (no TestFlight needed for M0)
- **Definition of Done:** full 3-city run playable start→finish on a physical phone; a lost run auto-offers PLAY AGAIN with a new seed; no crash in 2,000 sim runs; all tests green.

## 10. Suggested Session Breakdown for Claude Code

1. Repo scaffold, packages, CI (analyze + test), RNG + models
2. Pattern detection + scoring engine + golden tests
3. Content schema, validator, load the 20 utensils/6 blends/palates/critics
4. Run state machine (services, dishes/swaps, economy, bazaar logic) + sim CLI
5. Flutter/Flame UI: service screen + count-up ticker
6. Bazaar + summary screens, device build, playtest fixes
7. Tuning pass from Yeshu's first runs + sim output

*Per Yeshu's workflow rules: every commit gets a clear message (no co-author line), and each session ends with "how to test this" notes. Nothing deploys to production in M0 — device builds only.*

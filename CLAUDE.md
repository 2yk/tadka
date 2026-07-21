# Project Tadka — "Spice Route"

A premium roguelike deckbuilder for iOS/Android: you cook dishes from a pantry of ingredient
cards, poker-style patterns become regional dishes, utensils multiply the score into absurd
numbers. Solo project, no backend, no ads/IAP.

**Current state: M1 Flutter app, content-complete, heading to external testers.**
The M0 fun-check passed — a full run was played and finished. Art and sound are deliberately
deferred until the systems have been tested; everything on screen is placeholder emoji and
generated SVG.

## Layout

```
packages/game_core/     THE GAME. Pure Dart — rules, scoring, RNG, run state, progression,
                        blends, the Coach solver. Zero Flutter imports (enforced by a test).
packages/content/       JSON loader/validator. Scaffolded; catalogs still live in game_core.
apps/mobile/            Flutter app. Presentation only — it owns no rules.
tools/sim/              Headless balance simulator (Dart).
web/                    FROZEN. The M0 web prototype, kept as the differential reference.
tools/*.mjs             Node tooling for that reference: extract-core, gen-vectors, sim.
```

`apps/mobile` delegates every decision — legality, scoring, economy, offers — to `game_core`.
The live dish preview calls the real `scoreDish`, so what it shows is what COOK will pay. Keep
that property; a parallel implementation that drifts is worse than none.

## The trap that has bitten four times

**Seeded-list lengths are part of the seed contract.** `rng.pick(list)` indexes by length, so
appending to any list the run RNG draws from re-rolls every recorded seed and breaks the
differential traces. This has happened with `kUtensils`, `kBlends`, `kFestivals`, and — the
nastiest one — the *filtered* list `kCityPool.where(criticCanCloseARun)`, which is perturbed by
editing a **critic**, a file that looks nothing like the list it breaks.

The established fix is a fixture-scoping seam:

```dart
List<Utensil> activeUtensilCatalog = kUtensils;   // and activeBlendCatalog, activeFestivalCatalog
List<Deck> activeDeckCatalog = kDecks;            // assigning it rebuilds kDeckById
```

Live play uses everything; `runs_test.dart` pins each to the ported set in `setUpAll`. The route
is a `newRun` parameter for the same reason. **Scope the fixture, don't freeze the game.**

`activeDeckCatalog` is the fifth instance and reached the traces by a different road again: it
is not a list the RNG indexes, but `newRun` copies `deckCfg.startBlends` into `run.blends`,
which every recorded step snapshots. `kPortedDecks` holds the JS build's definitions and
`kDecks` the live ones; they may differ in `startBlends` and `identity` and nothing else, which
`content_visibility_test.dart` asserts field by field.

## The internal-testing switch

`kShowAllContent` in `progression.dart` — **defaults true**, and is read in exactly two places
(`isUnlocked`, `maxStake`). On, every utensil is in the shop pool from run one, every deck and
stake is selectable, and the Recipe Book and Help name the secret recipes. Set it to `false` for
a discovery-gated public build; that is the only edit needed.

It is a *read* override, never a write one. `unlockThing`, `setStakeProgress`, `recordRecipe`
and the achievement bus all still record the real progression underneath, so flipping the flag
back turns a tester's save into an ordinary gated profile. `content_visibility_test.dart` pins
both positions and the reversal; `runs_test.dart` forces it off in `setUpAll`, because the JS
reference has no notion of it and its recorded shop rolls are rolls against the starter pool.

Never regenerate `vectors.json` to make a failing test pass. Those vectors are recorded from the
frozen JS engine; regenerating them against Dart would only prove Dart agrees with Dart.

## How this codebase is tested

Unusually adversarially, on purpose — the engine is tuned and a silent scoring change would ruin
a balanced game invisibly.

- **Differential vectors** (`test/vectors.json`, ~6,200 cases) — scoring, patterns, RNG, pantry
  builds, blends, all recorded from `web/game-core.mjs` and asserted exactly, doubles included.
- **Whole-run traces** — 48 scripted runs replayed step for step against the JS engine.
- **Mutation testing** — every major suite has been checked by deliberately breaking the code and
  confirming the tests fail. If you add a suite, do this; a test that can't fail is decoration.
- **DSL allow-lists** — utensil and blend effect keys are validated; an unknown key fails loudly
  rather than silently doing nothing.

`web/game-core.mjs` must stay a byte-for-byte extract of `tadka.html`:
`node tools/extract-core.mjs --check`. CI runs it first, because drift there invalidates
everything measured against it.

## Content is data; the DSL is the boundary

Utensils and blends are pure data so content scales without engine changes.

- **utensil conditions:** `all_cards_family`, `contains_family`, `all_cards_same_family`,
  `min_cards`, `num_cards`, `pattern_is`, `pattern_at_least`, `is_first_dish`, `is_last_dish`
- **utensil effects:** `flavor_add`, `heat_add`, `heat_mult`, `flavor_mult`, `flavor_per_card`,
  `heat_per_card`, `coin_add`, `retrigger_highest`, `copy_right`
- **blend effects:** `set_family`, `copy_family`, `rank_set`, `rank_add`, `rank_invert`,
  `copy_rank`, `set_prized`, `prefix`, `duplicate`, `merge`, `discard_draw`, `draw_matching`,
  `draw`, and the `scope: 'hand'` modifier
- **critics:** `maxCards`, `minCards`, `debuff`, `requireFamily` only

If content needs a new key, add it deliberately with tests — don't route around it with a rule
forbidding the content. A content rule that exists to dodge an engine bug ages badly.

**Any critic that can end a run must not cap score** (`criticCanCloseARun`): a card cap holds you
at Three of a Kind, a required family can make a Flush impossible. Both are ceilings no Kitchen
level clears.

## Commands

```bash
dart analyze                                   # whole workspace
cd packages/game_core && dart test             # ~500 tests
cd apps/mobile && flutter test                 # ~47 widget tests
cd tools/sim && dart run bin/sim.dart -n 300   # balance ladder

node tools/extract-core.mjs --check            # web reference integrity

cd apps/mobile && flutter build apk --release
~/Library/Android/sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk
flutter build ios --release && xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app
```

## Reading the simulator

The bot is a greedy approximation with no taste — it never rerolls and declines nothing on its
own. Two things follow:

1. **Only the shape of the ladder is meaningful**, not the absolute win rate. The bar is
   monotone-decreasing with stake 8 at or near 0.
2. **Bot selectivity is a percentile of the pool** (`--pct`, default 55), not an absolute
   threshold. An absolute floor gets less selective as the catalog grows, which produced a false
   "balance collapse" twice. `--floor N` forces an absolute for A/B work.

When a ladder moves after a content drop, isolate before tuning: revert one half, re-measure. On
three occasions the apparent regression was the instrument, not the game.

Load-bearing balance facts, hard-won — don't undo without re-simming:

- **Festival recipe-leveling is the scaling engine.** Without it a maxed build caps and the late
  targets are unreachable. Note it levels the whole Kitchen, not the recipe named on the card —
  a divergence from concept doc §3.4 that is deliberate and balance-tested.
- **Targets follow `210·(s+2)²`** across the 24-service route, derived from `kLevelBonus` being
  linear in Kitchen level. A geometric curve reproducing M0's Naples numbers sims 0% everywhere.

## Docs

| File | What it is |
|---|---|
| [`spice-route-concept-doc.md`](spice-route-concept-doc.md) | The vision and v1.0 scope. Content targets are now met; the art brief and business case are still ahead. |
| [`tadka-m0-build-spec.md`](tadka-m0-build-spec.md) | The M0 contract. Scoring order-of-operations in §4 is still normative. |
| [`web/README.md`](web/README.md) | Describes the frozen M0 web build. Historical. |
| [`web/asset-pack/DESIGN-SYSTEM.md`](web/asset-pack/DESIGN-SYSTEM.md) | "Midnight Bazaar" tokens, type, components, motion spec — still the visual contract. |

`tadka-progression-spec.md` is referenced by `web/README.md` but is not in the repo.

## Known gaps

- **No sound.** Deliberately excluded for now.
- **Art is placeholder** — emoji and generated SVG. Fraunces/Inter aren't bundled, so display
  type falls back to a platform serif.
- **Nothing is gated right now** — `kShowAllContent` is on for internal testing. Underneath it
  the ladder still gates 24 of 95 utensils, which is short of the concept doc's ~60% locked at
  launch; that number is a launch-tuning decision to take when the flag goes off.
- **Android is debug-signed**; iOS uses free provisioning (7-day expiry, re-install to fix).
- **Not expressible without engine work:** The Rival Chef (dish cap — also changes the economy,
  since unused cooks pay coins), The Health Inspector (slot-0 suppression, with a trap around
  Grandmother's Ladle hopping right), the Golden Thali legendary (pattern-rewrite key), and a
  wild-card blend (needs a `Card` field and `bestPattern` changes).
- `packages/content` is still a scaffold; the catalogs live in `game_core`.

## Working conventions

- Commit non-breaking changes automatically, with a clear message. **Never add a co-author line.**
- Anything needing a human decision or a device check: stop, and end with the commit message plus
  explicit "how to test this" steps.
- Verify on a real device when the change has a visual surface. Several bugs this project shipped
  past unit tests and were only caught by looking at a phone.

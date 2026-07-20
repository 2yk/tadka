#!/usr/bin/env node
// Generates differential-test vectors from the JS reference engine (web/game-core.mjs).
//
// The Dart port in packages/game_core must reproduce every one of these exactly. The web
// build is tuned and playtested, so it — not the spec — is the behavioural source of truth
// for M1. A silent scoring divergence would quietly ruin a balanced game, and hand-written
// cases only cover what we thought to check; these cover what the engine actually does.
//
//   node tools/gen-vectors.mjs            # → packages/game_core/test/vectors.json
//   node tools/gen-vectors.mjs -n 4000    # more score cases
//
// Cases are drawn with the engine's own seeded RNG, so output is deterministic: regenerating
// on an unchanged engine produces a byte-identical file, and a diff means real behaviour moved.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import * as G from '../web/game-core.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'packages', 'game_core', 'test', 'vectors.json');

const args = process.argv.slice(2);
const opt = (f, d) => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : d; };
const N = +opt('-n', '3000');

const rng = G.makeRng('VECTOR-GEN-V1');
const pantry = G.buildPantry(null);
const card = (c) => ({ id: c.id, family: c.family, rank: c.rank, display: c.display, prized: !!c.prized });

// ---- RNG vectors: the 32-bit arithmetic in xmur3/mulberry32 is the classic porting trap.
// Dart ints are 64-bit, so any missing mask shows up here immediately.
const rngCases = ['SPICE-K7M2P', 'kochi', '', '0', 'a', 'The quick brown fox', '9999999999', '🌶️seed']
  .map((seed) => {
    const r = G.makeRng(seed);
    const next = Array.from({ length: 8 }, () => r.next());
    const ints = Array.from({ length: 8 }, () => r.int(52));
    const shuffled = r.shuffle(pantry.slice(0, 12)).map((c) => c.id);
    const weighted = Array.from({ length: 8 }, () => r.weighted(G.RARITY_WEIGHTS));
    return { seed, next, ints, shuffled, weighted };
  });

// ---- pattern + scoring vectors
const PALATE_KEYS = [null, 'kochi', 'tokyo', 'naples'];
const CRITIC_KEYS = [null, 'minimalist', 'traditionalist'];

// Synthetic utensils that exercise DSL combinations the 20 shipping utensils never hit.
// Verified by mutation testing: with the real catalog alone, swapping heat_mult ahead of
// heat_add inside a slot changes nothing observable, because no shipping utensil carries
// both keys — so build spec §4's "additive before multiplicative" rule was untestable, and
// `flavor_per_card` was entirely unexercised. These probes pin the DSL semantics now, so
// utensil #21 can't quietly depend on an ordering the port got wrong.
// They are test fixtures only and deliberately never enter the game catalog.
const PROBES = [
  { id: '_probe_add_then_mult', name: 'Probe AddMult', rarity: 'common', cost: 0, trigger: 'on_dish', condition: null, effect: { heat_add: 3, heat_mult: 2 }, text: 'probe' },
  { id: '_probe_flavor_per_card', name: 'Probe FlavorPer', rarity: 'common', cost: 0, trigger: 'on_dish', condition: null, effect: { flavor_per_card: 7 }, text: 'probe' },
  { id: '_probe_both_per_card', name: 'Probe BothPer', rarity: 'common', cost: 0, trigger: 'on_dish', condition: null, effect: { flavor_per_card: 4, heat_per_card: 2 }, text: 'probe' },
  { id: '_probe_kitchen_sink', name: 'Probe Everything', rarity: 'rare', cost: 0, trigger: 'on_dish', condition: null, effect: { flavor_add: 11, heat_add: 2, flavor_per_card: 3, heat_per_card: 1, coin_add: 2, heat_mult: 1.5 }, text: 'probe' },
  { id: '_probe_frac_mult', name: 'Probe FracMult', rarity: 'common', cost: 0, trigger: 'on_dish', condition: null, effect: { heat_mult: 0.5 }, text: 'probe' },
  { id: '_probe_cond_pattern', name: 'Probe CondPattern', rarity: 'common', cost: 0, trigger: 'on_dish', condition: { pattern_at_least: 'three_kind', min_cards: 2 }, effect: { flavor_add: 9, heat_mult: 1.25 }, text: 'probe' },
];
const UTIL_POOL = [...G.UTENSILS, ...PROBES];
const UTIL_BY_ID = Object.fromEntries(UTIL_POOL.map((u) => [u.id, u]));
const UTIL_IDS = UTIL_POOL.map((u) => u.id);

// Hand shapes: uniform-random cards mostly miss the interesting patterns, so bias the draw
// toward rank/family collisions. Without this, straights and full houses are ~never sampled.
function drawCards(n, shape) {
  const out = [];
  if (shape === 'same_family') {
    const fam = rng.pick(['spicy', 'sweet', 'sour', 'salty', 'umami']);
    const pool = pantry.filter((c) => c.family === fam);
    while (out.length < n) out.push(rng.pick(pool));
  } else if (shape === 'run') {
    const start = 1 + rng.int(6);
    const fam = rng.pick(['spicy', 'sweet', 'sour', 'salty', 'umami']);
    for (let i = 0; i < n; i++) {
      const r = start + i;
      const same = rng.int(2) === 0;
      out.push(pantry.find((c) => c.rank === Math.min(10, r) && c.family === (same ? fam : rng.pick(['spicy', 'sweet', 'sour', 'salty', 'umami']))) || rng.pick(pantry));
    }
  } else if (shape === 'rank_dupes') {
    const rank = 1 + rng.int(10);
    const pool = pantry.filter((c) => c.rank === rank);
    const k = 2 + rng.int(Math.min(4, n));
    for (let i = 0; i < k; i++) out.push(rng.pick(pool));
    while (out.length < n) out.push(rng.pick(pantry));
  } else {
    while (out.length < n) out.push(rng.pick(pantry));
  }
  return out.slice(0, n);
}

// Hands hand-built to hit every rung of the pattern ladder. Random draws never produce the
// secret recipes (full_family / perfect_palate need duplicate cards, which only blends create)
// and badly undersample full_house / straight_flush — so the top of the ladder, where a port
// bug would hide, would otherwise go untested.
const at = (fam, rank) => pantry.find((c) => c.family === fam && c.rank === rank);
const FAMS = ['spicy', 'sweet', 'sour', 'salty', 'umami'];
function constructedHands() {
  const hands = [];
  for (let r = 2; r <= 9; r++) {
    const f = FAMS[r % 5];
    const g = FAMS[(r + 1) % 5];
    // duplicates model blend-manipulated hands (Sun-Dry duplicates a card)
    hands.push([at(f, r), at(f, r), at(f, r), at(f, r), at(f, r)]);              // perfect_palate
    hands.push(FAMS.map((fam) => at(fam, r)));                                    // five_kind
    hands.push([at(f, r), at(f, r), at(f, r), at(f, r + 1), at(f, r + 1)]);       // full_family
    hands.push([at(f, r), at(g, r), at(FAMS[(r + 2) % 5], r), at(f, r + 1), at(g, r + 1)]); // full_house
    hands.push([0, 1, 2, 3, 4].map((k) => at(f, r === 9 ? k + 1 : Math.min(10, r + k)))); // straight_flush
    hands.push([0, 1, 2, 3, 4].map((k) => at(FAMS[k], r === 9 ? k + 1 : Math.min(10, r + k)))); // straight
    hands.push([at(f, r), at(g, r), at(FAMS[(r + 2) % 5], r), at(f, r + 1)]);     // four_kind (3+1 ranks)
    hands.push(FAMS.slice(0, 4).map((fam) => at(fam, r)));                        // four_kind
    hands.push([at(f, 1), at(f, 3), at(f, 5), at(f, 7), at(f, 10)]);              // flush
    hands.push([at(f, r), at(g, r), at(f, r + 1), at(g, r + 1)]);                 // two_pair
    hands.push([at(f, r), at(g, r), at(FAMS[(r + 2) % 5], r)]);                   // three_kind
    hands.push([at(f, r), at(g, r)]);                                             // pair
    hands.push([at(f, r)]);                                                       // high_card
  }
  return hands.filter((h) => h.every(Boolean));
}
const CONSTRUCTED = constructedHands();

const SHAPES = ['uniform', 'same_family', 'run', 'rank_dupes'];
const scoreCases = [];
const patternCases = [];

for (let i = 0; i < N; i++) {
  // front-load the constructed hands, then fill out with random shapes
  const n = 1 + rng.int(5);
  const cards = i < CONSTRUCTED.length
    ? CONSTRUCTED[i]
    : drawCards(n, SHAPES[i % SHAPES.length]);

  const bp = G.bestPattern(cards);
  patternCases.push({
    cards: cards.map(card),
    pattern: bp.pattern,
    scoring: bp.scoring.map((c) => c.id),
  });

  const nUtil = rng.int(6); // 0..5 — exercises empty racks and full racks
  const utensils = Array.from({ length: nUtil }, () => rng.pick(UTIL_IDS));
  const palateKey = rng.pick(PALATE_KEYS);
  const criticKey = rng.pick(CRITIC_KEYS);
  const ctx = {
    palate: palateKey ? G.PALATES[palateKey] : null,
    utensils: utensils.map((id) => UTIL_BY_ID[id]),
    critic: criticKey ? G.CRITICS[criticKey] : null,
    kitchenLevel: 1 + rng.int(12),
    isFirstDish: rng.int(2) === 0,
    isLastDish: rng.int(2) === 0,
  };
  const r = G.scoreDish(cards, ctx);
  scoreCases.push({
    cards: cards.map(card),
    ctx: {
      palate: palateKey,
      utensils,
      critic: criticKey,
      kitchenLevel: ctx.kitchenLevel,
      isFirstDish: ctx.isFirstDish,
      isLastDish: ctx.isLastDish,
    },
    pattern: r.pattern,
    scoring: r.scoring.map((c) => c.id),
    flavor: r.flavor,
    heat: r.heat,
    coins: r.coins,
    score: r.score,
  });
}

// ---- dishError vectors (gates the COOK button, so a divergence is player-visible)
const errCases = [];
for (let i = 0; i < 240; i++) {
  const n = rng.int(8); // include 0 and >5 to hit both bounds
  const cards = n === 0 ? [] : drawCards(n, SHAPES[i % SHAPES.length]);
  const criticKey = rng.pick(CRITIC_KEYS);
  errCases.push({
    cards: cards.map(card),
    critic: criticKey,
    error: G.dishError(cards, criticKey ? G.CRITICS[criticKey] : null),
  });
}

// ---- pantry build vectors (deck modifiers reshape the 52-card deck)
const pantryCases = G.DECKS.filter((d) => !d.reserved).map((d) => ({
  deckId: d.id,
  cards: G.buildPantry(d).map(card),
}));

const payload = {
  _comment: 'Generated by tools/gen-vectors.mjs from web/game-core.mjs. Do not hand-edit.',
  // Full utensil definitions (shipping catalog + synthetic DSL probes) so the Dart test is
  // self-describing: it builds these from the fixture rather than looking them up in the
  // Dart catalog, which means catalog drift shows up as a scoring diff instead of a crash.
  utensilDefs: Object.fromEntries(UTIL_POOL.map((u) => [u.id, u])),
  rng: rngCases,
  patterns: patternCases,
  scores: scoreCases,
  dishErrors: errCases,
  pantries: pantryCases,
};

writeFileSync(OUT, `${JSON.stringify(payload)}\n`);
const dist = {};
for (const c of patternCases) dist[c.pattern] = (dist[c.pattern] || 0) + 1;
console.log(`wrote ${OUT}`);
console.log(`  rng ${rngCases.length} · patterns ${patternCases.length} · scores ${scoreCases.length} · dishErrors ${errCases.length} · pantries ${pantryCases.length}`);
console.log('  pattern coverage:', Object.entries(dist).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}=${v}`).join(' '));

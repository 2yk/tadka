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
import { readFileSync, writeFileSync } from 'node:fs';
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

// ===========================================================================
// §PROGRESSION + §RUN traces
// ===========================================================================
// Scoring vectors prove one dish scores the same. They say nothing about the state machine
// around it: draw order, the economy, when a critic appears, which achievements fire, or how
// an unlock changes the next bazaar. Those are exactly the places a port silently drifts, and
// they compound — a one-coin difference in service 1 changes what you can buy for the rest of
// the run. So we record whole runs, step by step, and the Dart test replays them.
//
// The policy below is deliberately dumb and completely fixed: cook the first N legal hand
// indices, buy the first affordable offer, never reroll. A clever bot would make the trace
// depend on the bot rather than on the engine. The point is not to play well — most of these
// runs die in Kochi or Tokyo — it is that every branch taken is forced by the engine's own
// state, so any divergence is the engine's.
//
// game-core.mjs exports only what tadka.html's §UI needs, which leaves doCook, doSwap,
// recordLoss, onRunWon, emit and the whole profile layer unreachable from an import. Rather
// than widen the export block — that would mean editing web/, which is generated and off
// limits — the module body is read as text and evaluated with a wider return. The bytes are
// the file's own, so there is still exactly one JS implementation and nothing to drift.
const CORE_SRC = readFileSync(join(ROOT, 'web', 'game-core.mjs'), 'utf8');
const CORE_BODY = CORE_SRC.slice(0, CORE_SRC.lastIndexOf('\nexport {'));
const CORE_NAMES = [
  'makeRng', 'buildPantry', 'bestPattern', 'cardContribution', 'scoreDish', 'dishError',
  'stakeConfig', 'defaultProfile', 'isUnlocked', 'unlockThing', 'unlockedUtensilPool',
  'unlockedDecks', 'maxStake', 'setStakeProgress', 'recordRecipe', 'bumpStat', 'setBest',
  'rewardLabel', 'grantReward', 'condMetAch', 'emit', 'newRun', 'cityOf', 'activeCritic',
  'startService', 'mergeCritics', 'startEndlessCity', 'onRunWon', 'drawUp', 'ctxFor',
  'doCook', 'doSwap', 'bankService', 'recordLoss', 'recordEndless', 'advance',
  'isFinalService', 'rollOffers', 'UTENSILS', 'UTIL_BY_ID', 'BLENDS', 'BLEND_BY_ID',
  'FESTIVALS', 'CRITICS', 'MINOR_CRITICS', 'CITIES', 'STAKES', 'DECKS', 'DECK_BY_ID',
  'START_UTENSILS', 'STAKE_GATED_UTENSILS', 'VENDOR_IDS', 'ACHIEVEMENTS', 'SERVICE_NAMES',
];

function loadCore() {
  const body = `'use strict';\n${CORE_BODY}\nreturn {\n  ${CORE_NAMES.join(', ')},\n`
    + '  __setProfile(p){ PROFILE = p; },\n'
    + '  __profile(){ return PROFILE; },\n'
    + '  __drainUnlocks(){ const m = unlockQueue.slice(); unlockQueue.length = 0; return m; }\n};';
  // eslint-disable-next-line no-new-func
  return new Function(body)();
}
const core = loadCore();

const criticSnap = (c) => (c ? {
  id: c.id,
  name: c.name,
  max_cards: c.max_cards ?? null,
  min_cards: c.min_cards ?? null,
  debuff: c.debuff ?? null,
  require_family: c.require_family ?? null,
  minor: !!c.minor,
  legend: !!c.legend,
} : null);

// The profile is module-global in JS and feeds rollOffers through unlockedUtensilPool, so it
// is part of the observable state of a run, not a side channel. Snapshotting it after every
// action is what makes the achievement bus testable at all.
function profileSnap() {
  const P = core.__profile();
  return {
    utensils: P.unlocks.utensils.slice(),
    blends: P.unlocks.blends.slice(),
    decks: P.unlocks.decks.slice(),
    cardbacks: P.unlocks.cardbacks.slice(),
    achievements: P.achievements_done.slice(),
    recipes: P.recipes_discovered.slice(),
    stats: { ...P.stats },
    stake_progress: { ...P.stake_progress },
    endless_top10: P.endless_top10.map((e) => ({ ...e })),
  };
}

function coreSnap(run) {
  // cityOf() would index past CITIES once the route is cleared; the JS UI never calls it there.
  const city = (run.endless || run.cityIndex <= 2) ? core.cityOf(run) : null;
  return {
    cityIndex: run.cityIndex,
    serviceIndex: run.serviceIndex,
    cityName: city ? city.name : null,
    cityTargets: city ? city.targets.slice() : null,
    target: run.target,
    score: run.score,
    coins: run.coins,
    kitchenLevel: run.kitchenLevel,
    cooksLeft: run.cooksLeft,
    swapsLeft: run.swapsLeft,
    dishesPlayed: run.dishesPlayed,
    totalScore: run.totalScore,
    hand: run.hand.map((c) => c.id),
    deckLen: run.deck.length,
    critic: criticSnap(run.critic),
    status: run.status,
    utensils: run.utensils.map((u) => u.id),
    blends: run.blends.map((b) => b.id),
    endless: run.endless,
    endlessCity: run.endlessCity,
    distance: run.distance,
    svcMaxCards: run.svcMaxCards,
    svcSwapsUsed: run.svcSwapsUsed,
    historyLen: run.history.length,
  };
}

const snap = (run, tag, extra) => ({
  tag,
  ...coreSnap(run),
  unlocks: core.__drainUnlocks(),
  profile: profileSnap(),
  ...(extra || {}),
});

// JSON.stringify drops undefined-valued keys, and festival offers carry no `desc` while
// utensil/blend offers carry no `pattern`. Normalising here keeps the fixture's shape square
// and matches the Dart `Offer`, whose `desc` defaults to ''.
const offerSnap = (o) => ({
  kind: o.kind, id: o.id, name: o.name, cost: o.cost, rarity: o.rarity,
  desc: o.desc ?? '', pattern: o.pattern ?? null,
});

const histSnap = (run) => run.history.map((h) => ({ ...h }));

/// Every size-1..cap subset of hand indices, in a canonical depth-first order:
/// [0], [0,1], [0,1,2], ..., [0,1,2,3,5], ... The order is the tiebreak for `chooseBest`,
/// so it is part of the policy contract the Dart replay has to reproduce exactly.
function candidateIdxs(handLen, cap) {
  const out = [];
  const acc = [];
  const rec = (start) => {
    if (acc.length > 0) out.push(acc.slice());
    if (acc.length === cap) return;
    for (let i = start; i < handLen; i++) {
      acc.push(i);
      rec(i + 1);
      acc.pop();
    }
  };
  rec(0);
  return out;
}

/// Fixed cook policy B: the highest-scoring legal dish in hand, ties going to the earliest
/// candidate. Still deterministic — it asks the engine, it does not model it — but unlike
/// policy A it actually clears services, which is the only way the trace ever reaches Tokyo,
/// Naples, a Food Critic, or `onRunWon` in situ. Uses at most 218 scoreDish calls per cook.
function chooseBest(run) {
  const cap = Math.min(5, run.critic && run.critic.max_cards ? run.critic.max_cards : 5);
  const ctx = core.ctxFor(run);
  let best = null;
  let bestScore = -1;
  for (const idxs of candidateIdxs(run.hand.length, cap)) {
    const cards = idxs.map((i) => run.hand[i]);
    if (core.dishError(cards, run.critic)) continue;
    const s = core.scoreDish(cards, ctx).score;
    if (s > bestScore) { bestScore = s; best = idxs; }
  }
  return best;
}

/// Fixed cook policy A: the first N hand indices, narrowed to whatever the critic allows.
/// Returns null when no legal dish can be formed, which ends the trace at a `stuck` step.
function chooseCook(run) {
  const cap = run.critic && run.critic.max_cards ? run.critic.max_cards : 5;
  const n = Math.min(5, cap, run.hand.length);
  if (n < 1) return null;
  let idxs = [];
  for (let i = 0; i < n; i++) idxs.push(i);
  const req = run.critic && run.critic.require_family;
  if (req && !idxs.some((i) => run.hand[i].family === req)) {
    const j = run.hand.findIndex((c) => c.family === req);
    if (j < 0) return null;
    idxs[idxs.length - 1] = j;
  }
  idxs = [...new Set(idxs)].sort((a, b) => a - b);
  const min = run.critic && run.critic.min_cards ? run.critic.min_cards : 0;
  if (idxs.length < min) return null;
  return idxs;
}

/// Fixed shopping order. Festivals first because Kitchen level is the run's scaling engine
/// (CLAUDE.md) — a bot that buys whatever is in slot 0 never gets past Kochi, and then the
/// whole late-route state machine goes untraced. Utensils next, blends last (the engine does
/// not apply blends; they only ever occupy inventory here).
const BUY_PRIORITY = { festival: 0, utensil: 1, blend: 2 };

const canBuy = (run, o) => run.coins >= o.cost
  && !(o.kind === 'utensil' && run.utensils.length >= run.utensilSlots)
  && !(o.kind === 'blend' && run.blends.length >= 3);

/// Buys by [BUY_PRIORITY], then by slot index, repeating while anything is still affordable.
/// Mirrors §UI's buyOffer minus its two cosmetic emits — `utensil_bought`, which nothing
/// listens for, and the festival's `kitchen_level`, which bankService re-emits every service
/// anyway. The Dart replay skips exactly the same two.
function policyBuy(run, offers) {
  const bought = [];
  const remaining = offers.slice();
  for (;;) {
    let pick = -1;
    for (let i = 0; i < remaining.length; i++) {
      if (!canBuy(run, remaining[i])) continue;
      if (pick < 0 || BUY_PRIORITY[remaining[i].kind] < BUY_PRIORITY[remaining[pick].kind]) pick = i;
    }
    if (pick < 0) break;
    const o = remaining[pick];
    run.coins -= o.cost;
    if (o.kind === 'utensil') run.utensils.push({ ...core.UTIL_BY_ID[o.id] });
    else if (o.kind === 'festival') run.kitchenLevel++;
    else run.blends.push({ ...core.BLEND_BY_ID[o.id] });
    bought.push({ kind: o.kind, id: o.id, cost: o.cost });
    remaining.splice(pick, 1);
  }
  return bought;
}

function playRun(combo) {
  core.__setProfile(core.defaultProfile());
  core.__drainUnlocks();
  const steps = [];
  const run = core.newRun({ seed: combo.seed, stake: combo.stake, deckId: combo.deckId });
  steps.push(snap(run, 'start', {
    cooksBase: run.cooksBase, swapsBase: run.swapsBase, utensilSlots: run.utensilSlots,
    finalBaseTarget: run.finalBaseTarget, naplesCritic: run.naplesCritic,
  }));

  // Finale probe: even the greedy policy only reaches Naples' Food Critic, never beats it, so
  // the win arm — isFinalService, onRunWon, status 'won' — would never be traced in situ.
  // Dropping the run onto the last service with a Kitchen level it could plausibly have
  // reached exercises it, plus Naples' target scaling and the `reached_city: 2` achievement.
  if (combo.boost) {
    run.cityIndex = 2;
    run.serviceIndex = 2;
    run.kitchenLevel = combo.boost;
    core.startService(run);
    steps.push(snap(run, 'boost'));
  }

  let swapped = false;
  let guard = 0;
  while (run.status === 'playing' && guard < 600) {
    guard++;
    if (combo.swapFirst && !swapped && run.swapsLeft > 0 && run.dishesPlayed === 0) {
      swapped = true;
      const sw = core.doSwap(run, [0, 1]);
      steps.push(snap(run, 'swap', { swapError: sw.error ?? null, swapOk: !!sw.ok }));
      continue;
    }
    const idxs = combo.policy === 'best' ? chooseBest(run) : chooseCook(run);
    if (!idxs) { steps.push(snap(run, 'stuck')); break; }
    const res = core.doCook(run, idxs);
    steps.push(snap(run, 'cook', {
      idxs,
      cookError: res.error ?? null,
      pattern: res.result ? res.result.pattern : null,
      dishScore: res.result ? res.result.score : null,
      dishFlavor: res.result ? res.result.flavor : null,
      dishHeat: res.result ? res.result.heat : null,
      dishCoins: res.result ? res.result.coins : null,
      outcome: res.outcome ?? null,
    }));
    if (res.error) { steps.push(snap(run, 'stuck')); break; }

    if (res.outcome === 'won') {
      const bank = core.bankService(run);
      steps.push(snap(run, 'bank', { bank: { ...bank } }));
      if (core.isFinalService(run)) {
        core.onRunWon(run);
        run.status = 'won';
        steps.push(snap(run, 'runWon'));
        break;
      }
      const offers = core.rollOffers(run);
      steps.push(snap(run, 'offers', { offers: offers.map(offerSnap) }));
      steps.push(snap(run, 'buy', { bought: policyBuy(run, offers) }));
      core.advance(run);
      steps.push(snap(run, 'advance'));
      swapped = false;
      continue;
    }
    if (res.outcome === 'lost') {
      core.recordLoss(run);
      steps.push(snap(run, 'loss'));
      break;
    }
  }
  return { ...combo, steps, history: histSnap(run) };
}

const RUN_SEEDS = [
  'SPICE-K7M2P', 'SPICE-QW3XY', 'SPICE-ZZTOP', 'SPICE-4LEAF', 'SPICE-MANGO',
  'SPICE-TADKA', 'SPICE-NAPLE', 'SPICE-TOKYO', 'SPICE-KOCHI', 'SPICE-HAWKR',
];
const RUN_DECKS = ['home', 'coastal', 'royal', 'hawker'];
const runCases = [];
for (let i = 0; i < RUN_SEEDS.length; i++) {
  for (let j = 0; j < RUN_DECKS.length; j++) {
    const n = i * RUN_DECKS.length + j;
    runCases.push(playRun({
      seed: RUN_SEEDS[i],
      stake: 1 + (n % 8),                       // every stake, on every deck
      deckId: RUN_DECKS[j],
      policy: n % 2 === 0 ? 'best' : 'first',   // depth from B, early-loss paths from A
      swapFirst: n % 4 < 2,                     // swap and no-swap (Steady Hands) branches
    }));
  }
}
for (let i = 0; i < 8; i++) {
  runCases.push(playRun({
    seed: `SPICE-FIN0${i + 1}`,
    stake: 1 + i,
    deckId: RUN_DECKS[i % RUN_DECKS.length],
    policy: 'best',
    swapFirst: i % 2 === 0,
    boost: 16 + i * 4,
  }));
}

// ---- Long Route probes
// A dumb bot never wins the base route, so the endless machinery would go untested if we
// waited to reach it honestly. startEndlessCity is legal on a fresh run, so drive it directly:
// six cities in sequence compound endlessBase the same way real progression does, and k=3 and
// k=6 hit the mergeCritics branch. serviceIndex is then forced to the finale to exercise
// activeCritic's endless arm, which is the only place the city's rolled critic is read.
const ENDLESS_COMBOS = [
  { seed: 'SPICE-LONG1', stake: 1, deckId: 'home' },
  { seed: 'SPICE-LONG2', stake: 3, deckId: 'coastal' },
  { seed: 'SPICE-LONG3', stake: 5, deckId: 'royal' },
  { seed: 'SPICE-LONG4', stake: 8, deckId: 'hawker' },
  { seed: 'SPICE-LONG5', stake: 6, deckId: 'home' },
  { seed: 'SPICE-LONG6', stake: 7, deckId: 'coastal' },
];
const endlessCases = ENDLESS_COMBOS.map((combo) => {
  core.__setProfile(core.defaultProfile());
  core.__drainUnlocks();
  const run = core.newRun({ seed: combo.seed, stake: combo.stake, deckId: combo.deckId });
  core.__drainUnlocks();
  const cities = [];
  for (let k = 1; k <= 6; k++) {
    core.startEndlessCity(run, k);
    const c = run.endlessCityObj;
    const rec = {
      k,
      endlessBase: run.endlessBase,
      cityId: c.id,
      cityName: c.name,
      targets: c.targets.slice(),
      criticObj: criticSnap(c.criticObj),
      lunch: coreSnap(run),
    };
    run.serviceIndex = 2;
    core.startService(run);
    rec.finale = coreSnap(run);
    cities.push(rec);
  }
  return { ...combo, cities, profile: profileSnap() };
});

// ---- onRunWon probes: stake progression, the stake-gated Ladle, and the run_won ladder.
// Vendors are pushed onto the rack by hand because the scripted runs never buy two.
const ON_WON = [
  { seed: 'SPICE-WON01', stake: 1, deckId: 'home', vendors: [] },
  { seed: 'SPICE-WON02', stake: 2, deckId: 'home', vendors: [] },
  { seed: 'SPICE-WON03', stake: 3, deckId: 'coastal', vendors: ['street_cart'] },
  { seed: 'SPICE-WON04', stake: 4, deckId: 'royal', vendors: ['street_cart', 'chai_stall'] },
  { seed: 'SPICE-WON05', stake: 8, deckId: 'hawker', vendors: ['street_cart', 'chai_stall'] },
];
const wonCases = ON_WON.map((combo) => {
  core.__setProfile(core.defaultProfile());
  core.__drainUnlocks();
  const run = core.newRun({ seed: combo.seed, stake: combo.stake, deckId: combo.deckId });
  core.__drainUnlocks();
  for (const id of combo.vendors) run.utensils.push({ ...core.UTIL_BY_ID[id] });
  core.onRunWon(run);
  return { ...combo, unlocks: core.__drainUnlocks(), profile: profileSnap() };
});

// ---- endless leaderboard: the sort keys, the 10-row cap, and stability on exact ties.
// Rows 1 and 6 tie on both distance and score with different seeds — JS Array#sort is stable
// and Dart's List#sort is not, so this pins the tiebreak the port has to reproduce.
const LEADER_ROWS = [
  { seed: 'LB-A', d: 3, s: 500 }, { seed: 'LB-B', d: 1, s: 900 },
  { seed: 'LB-C', d: 3, s: 700 }, { seed: 'LB-D', d: 5, s: 100 },
  { seed: 'LB-E', d: 2, s: 200 }, { seed: 'LB-F', d: 3, s: 500 },
  { seed: 'LB-G', d: 7, s: 10 }, { seed: 'LB-H', d: 4, s: 4 },
  { seed: 'LB-I', d: 6, s: 6 }, { seed: 'LB-J', d: 2, s: 201 },
  { seed: 'LB-K', d: 9, s: 9 }, { seed: 'LB-L', d: 8, s: 8 },
  { seed: 'LB-M', d: 1, s: 1 },
];
core.__setProfile(core.defaultProfile());
core.__drainUnlocks();
const leaderboardCases = LEADER_ROWS.map((row) => {
  const run = core.newRun({ seed: row.seed, stake: 2, deckId: 'home' });
  run.distance = row.d;
  run.totalScore = row.s;
  core.recordEndless(run);
  core.__drainUnlocks();
  return { ...row, top10: profileSnap().endless_top10 };
});

// ---- bankService probe matrix.
// Found by mutation testing: dropping the interest cap from 5 to 4 changed nothing any trace
// could see, because a policy that spends its coins every bazaar never reaches the 25 needed
// to hit the cap. The economy is too load-bearing to leave to whatever the bot happens to do,
// so drive it directly across the purse sizes, service slots and both route modes.
const BANK_COINS = [0, 4, 5, 9, 19, 20, 24, 25, 26, 49, 100];
const bankCases = [];
for (const stake of [1, 2]) {            // stake 2 is where Lunch stops paying
  for (const endless of [false, true]) { // the endless arm banks distance instead
    for (const serviceIndex of [0, 1, 2]) {
      for (const cooksLeft of [0, 2, 4]) {
        for (const coins of BANK_COINS) {
          core.__setProfile(core.defaultProfile());
          core.__drainUnlocks();
          const run = core.newRun({ seed: `BANK-${stake}-${coins}`, stake, deckId: 'home' });
          if (endless) core.startEndlessCity(run, 1);
          core.__drainUnlocks();
          run.serviceIndex = serviceIndex;
          run.coins = coins;
          run.cooksLeft = cooksLeft;
          run.svcMaxCards = cooksLeft;      // drives minimal_effort
          run.svcSwapsUsed = serviceIndex;  // drives steady_hands
          const bank = core.bankService(run);
          bankCases.push({
            stake, endless, serviceIndex, cooksLeft, coins,
            bank: { ...bank },
            coinsAfter: run.coins,
            distance: run.distance,
            history: histSnap(run),
            unlocks: core.__drainUnlocks(),
            profile: profileSnap(),
          });
        }
      }
    }
  }
}

// ---- stakeConfig: cheap, and it underpins every run above.
const stakeCases = [1, 2, 3, 4, 5, 6, 7, 8].map((id) => {
  const c = core.stakeConfig(id);
  return {
    id,
    cooksDelta: c.cooksDelta,
    swapsDelta: c.swapsDelta,
    utensilSlots: c.utensilSlots,
    lunchRewardZero: c.lunchRewardZero,
    targetScale: c.targetScale ? { fromCity: c.targetScale.fromCity, pct: c.targetScale.pct } : null,
    shopInflationPerCity: c.shopInflationPerCity,
    minorCriticOnDinner: c.minorCriticOnDinner,
  };
});

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
  // A fresh save, serialized. Pins the exact `tadka_profile_v1` shape so the Dart Profile
  // stays byte-compatible with a save written by the web build.
  defaultProfile: JSON.stringify(core.defaultProfile()),
  stakes: stakeCases,
  runs: runCases,
  endless: endlessCases,
  runsWon: wonCases,
  leaderboard: leaderboardCases,
  banks: bankCases,
};

writeFileSync(OUT, `${JSON.stringify(payload)}\n`);
const dist = {};
for (const c of patternCases) dist[c.pattern] = (dist[c.pattern] || 0) + 1;
const stepTotal = runCases.reduce((s, r) => s + r.steps.length, 0);
const tagDist = {};
for (const r of runCases) for (const s of r.steps) tagDist[s.tag] = (tagDist[s.tag] || 0) + 1;
const deepest = runCases.reduce((m, r) => {
  const last = r.steps[r.steps.length - 1];
  return Math.max(m, last.cityIndex * 3 + last.serviceIndex);
}, 0);
console.log(`wrote ${OUT}`);
console.log(`  rng ${rngCases.length} · patterns ${patternCases.length} · scores ${scoreCases.length} · dishErrors ${errCases.length} · pantries ${pantryCases.length}`);
console.log('  pattern coverage:', Object.entries(dist).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}=${v}`).join(' '));
console.log(`  runs ${runCases.length} · steps ${stepTotal} · endless ${endlessCases.length}x6 · runsWon ${wonCases.length} · leaderboard ${leaderboardCases.length} · banks ${bankCases.length}`);
console.log('  step tags:', Object.entries(tagDist).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}=${v}`).join(' '));
console.log(`  deepest service reached: ${deepest} (0 = Kochi Lunch, 8 = Naples Critic)`);

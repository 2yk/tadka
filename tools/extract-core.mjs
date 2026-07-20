#!/usr/bin/env node
// Regenerates web/game-core.mjs from web/tadka.html.
//
// tadka.html is the single source of truth. game-core.mjs is a byte-for-byte mirror of the
// pure layers (§RNG .. §RUN) with a Node shim on top and an export block at the bottom, so
// tools/sim.mjs scores exactly like the game. Referenced by game-core.mjs's header comment.
//
//   node tools/extract-core.mjs          # rewrite web/game-core.mjs
//   node tools/extract-core.mjs --check  # verify sync, exit 1 if drifted (no write)
//
// Boundaries are found by section banner, not line number, so edits elsewhere in tadka.html
// (§ART above, §UI below) don't break extraction.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'web', 'tadka.html');
const DST = join(ROOT, 'web', 'game-core.mjs');

const HEADER = `// AUTO-EXTRACTED from web/tadka.html — the pure game-core (§RNG..§RUN).
// Mirrors the inline copy in tadka.html byte-for-byte; regenerate with tools/extract-core.
// The Flutter build replaces both this and the inline copy with the Dart game_core package.
const localStorage={getItem:()=>null,setItem:()=>{}}; // Node shim — headless sim keeps the profile in memory
`;

const EXPORTS = `
export { makeRng, buildPantry, scoreDish, bestPattern, dishError, cardContribution, newRun,
  startService, ctxFor, bankService, advance, isFinalService, rollOffers, cityOf, activeCritic,
  startEndlessCity, PALATES, CRITICS, MINOR_CRITICS, CITIES, UTENSILS, UTIL_BY_ID, FESTIVALS, BLENDS,
  RARITY_WEIGHTS, STAKES, STAKE_BY_ID, stakeConfig, DECKS, DECK_BY_ID, PROFILE, GENERIC, PORDER };
`;

const lines = readFileSync(SRC, 'utf8').split('\n');
const bannerAt = (marker) => {
  const i = lines.findIndex((l) => l.includes(marker));
  if (i < 0) throw new Error(`extract-core: banner not found in tadka.html: ${marker}`);
  return i - 1; // step up onto the opening /* ==== rule
};

// §RNG banner through the line before the §UI banner
const core = lines.slice(bannerAt('§RNG  (game_core)'), bannerAt('§UI  (apps/mobile)'));
const out = `${HEADER}\n${core.join('\n')}\n${EXPORTS}`;

if (process.argv.includes('--check')) {
  const ok = readFileSync(DST, 'utf8') === out;
  console.log(ok
    ? 'game-core.mjs is in sync with tadka.html'
    : 'DRIFT: game-core.mjs differs from tadka.html — run: node tools/extract-core.mjs');
  process.exit(ok ? 0 : 1);
}

writeFileSync(DST, out);
console.log(`wrote web/game-core.mjs (${core.length} core lines extracted from tadka.html)`);

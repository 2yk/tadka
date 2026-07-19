#!/usr/bin/env node
// Tadka headless balance sim — plays N runs with a scripted greedy bot and reports win rate.
// Usage:
//   node tools/sim.mjs                 # stake ladder (all 8), 500 runs each, Home deck
//   node tools/sim.mjs --stake 3       # single stake, 500 runs
//   node tools/sim.mjs --stake 8 -n 2000 --deck royal
//
// Imports the exact engine from web/game-core.mjs (auto-extracted from tadka.html), so sim
// scores match the game 1:1. Verified equivalently in-browser; ships here for CI / when Node
// is available (this workstation had no Node at authoring time).
import * as G from '../web/game-core.mjs';

// headless profile: unlock the full utensil pool so the bot represents an experienced build
G.PROFILE.unlocks.utensils = G.UTENSILS.map(u => u.id);

const args = process.argv.slice(2);
const opt = (flag, def) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : def; };
const stakeArg = opt('--stake', null);
const N = +opt('-n', '500');
const deckId = opt('--deck', 'home');

// crude value heuristic for the shop bot (heat is scarce → weighted high)
const VAL = {clay_handi:100,emperors_wok:75,ice_box:80,tandoor:70,wok:70,bamboo_steamer:85,griddle:78,
  salt_cellar:60,mint_garnish:62,stock_pot:55,golden_sieve:90,butchers_block:65,iron_tawa:70,rice_cooker:58,
  honey_jar:52,big_spoon:45,pressure_cooker:74,grandmother_ladle:66,street_cart:20,chai_stall:22};
const uval = id => VAL[id] || 40;

function kcombos(n, k) {
  const res = []; if (k > n) return res;
  const idx = Array.from({length:k}, (_,i)=>i);
  while (true){ res.push(idx.slice()); let i=k-1; while(i>=0&&idx[i]===i+n-k)i--; if(i<0)break; idx[i]++; for(let j=i+1;j<k;j++)idx[j]=idx[j-1]+1; }
  return res;
}
const CB = {}; for (let s=1;s<=5;s++) CB[s] = kcombos(8, s);
const ctxOf = run => ({palate:G.PALATES[G.cityOf(run).id], utensils:run.utensils, critic:run.critic,
  kitchenLevel:run.kitchenLevel, isFirstDish:run.dishesPlayed===0, isLastDish:run.cooksLeft===1});

function bestDish(run, mc) {
  const h = run.hand, ctx = ctxOf(run); let b = {score:-1, idxs:[0]};
  for (let s=1;s<=mc;s++) for (const c of (CB[s]||kcombos(h.length,s))) {
    if (c[c.length-1] >= h.length) continue;
    const cards = c.map(i=>h[i]); if (G.dishError(cards, run.critic)) continue;
    const r = G.scoreDish(cards, ctx); if (r.score > b.score) b = {score:r.score, idxs:c};
  }
  return b;
}
function digIdx(run, mc) {
  const fa={}, rk={}; run.hand.forEach(c=>{fa[c.family]=(fa[c.family]||0)+1; rk[c.rank]=(rk[c.rank]||0)+1;});
  const tf = Object.keys(fa).sort((a,b)=>fa[b]-fa[a])[0]; const keep = new Set();
  if (mc>=5 && fa[tf]>=3) run.hand.forEach((c,i)=>{ if(c.family===tf) keep.add(i); });
  else run.hand.forEach((c,i)=>{ if(rk[c.rank]>=2) keep.add(i); });
  return run.hand.map((c,i)=>({i,r:c.rank})).filter(x=>!keep.has(x.i)).sort((a,b)=>a.r-b.r).slice(0,5).map(x=>x.i);
}
function playService(run) {
  const mc = (run.critic && run.critic.max_cards) ? run.critic.max_cards : 5;
  while (run.cooksLeft > 0 && run.score < run.target) {
    const best = bestDish(run, mc), pace = Math.ceil((run.target - run.score) / run.cooksLeft);
    if (run.swapsLeft > 0 && run.cooksLeft > 1 && best.score < pace) {
      const d = digIdx(run, mc);
      if (d.length) { run.hand = run.hand.filter((_,i)=>!d.includes(i)); while(run.hand.length<8&&run.deck.length) run.hand.push(run.deck.shift()); run.swapsLeft--; continue; }
    }
    const cards = best.idxs.map(i=>run.hand[i]); const r = G.scoreDish(cards, ctxOf(run));
    run.score += r.score; run.coins += r.coins; run.dishesPlayed++; run.cooksLeft--;
    run.hand = run.hand.filter((_,i)=>!best.idxs.includes(i)); while (run.hand.length<8&&run.deck.length) run.hand.push(run.deck.shift());
  }
  return run.score >= run.target;
}
function shop(run) {
  const offers = G.rollOffers(run);
  const uo = offers.filter(o=>o.kind==='utensil').sort((a,b)=>uval(b.id)-uval(a.id));
  for (const o of uo) { if (run.utensils.length >= Math.min(run.utensilSlots,3)) break; if (run.coins>=o.cost){ run.utensils.push({...G.UTIL_BY_ID[o.id]}); run.coins-=o.cost; } }
  let bought = 0;
  for (const o of offers) { if (o.kind==='festival' && run.coins>=o.cost && bought<2) { run.kitchenLevel++; run.coins-=o.cost; bought++; } }
  for (const o of uo) { if (run.coins<o.cost) continue; if (run.utensils.length<run.utensilSlots){ run.utensils.push({...G.UTIL_BY_ID[o.id]}); run.coins-=o.cost; } else break; }
}
function simRun(seed, stake) {
  const run = G.newRun({seed, stake, deckId});
  for (let guard=0; guard<40; guard++) {
    if (!playService(run)) return false;
    const wasBoss = run.serviceIndex===2; G.bankService(run); if (wasBoss) run.kitchenLevel += 3;
    if (G.isFinalService(run)) return true;
    shop(run); G.advance(run); if (run.status==='won') return true;
  }
  return false;
}
function winRate(stake) { let w=0; for (let s=0;s<N;s++) if (simRun('L'+s, stake)) w++; return Math.round(w/N*100); }

if (stakeArg) {
  const st = +stakeArg;
  console.log(`Stake ${st} (${G.STAKE_BY_ID[st].name}) · deck ${deckId} · ${N} runs → ${winRate(st)}% win`);
} else {
  console.log(`Stake ladder · deck ${deckId} · ${N} runs each:`);
  for (let s=1;s<=8;s++) console.log(`  ${s}  ${G.STAKE_BY_ID[s].chili_icon}  ${G.STAKE_BY_ID[s].name.padEnd(16)} ${winRate(s)}%`);
}

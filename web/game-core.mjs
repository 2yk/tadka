// AUTO-EXTRACTED from web/tadka.html — the pure game-core (§RNG..§RUN).
// Mirrors the inline copy in tadka.html byte-for-byte; regenerate with tools/extract-core.
// The Flutter build replaces both this and the inline copy with the Dart game_core package.
const localStorage={getItem:()=>null,setItem:()=>{}}; // Node shim — headless sim keeps the profile in memory

/* =====================================================================
   §RNG  (game_core)  — deterministic seeded PRNG. Same seed => same run.
   ===================================================================== */
function xmur3(str){let h=1779033703^str.length;for(let i=0;i<str.length;i++){h=Math.imul(h^str.charCodeAt(i),3432918353);h=h<<13|h>>>19;}return function(){h=Math.imul(h^h>>>16,2246822507);h=Math.imul(h^h>>>13,3266489909);h^=h>>>16;return h>>>0;};}
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
function makeRng(seedStr){
  const seed=xmur3(String(seedStr))(); const f=mulberry32(seed);
  return {
    next:f,
    int:(n)=>Math.floor(f()*n),
    pick:(arr)=>arr[Math.floor(f()*arr.length)],
    shuffle:(arr)=>{const a=arr.slice();for(let i=a.length-1;i>0;i--){const j=Math.floor(f()*(i+1));[a[i],a[j]]=[a[j],a[i]];}return a;},
    weighted:(pairs)=>{ // [[key,w],...]
      const tot=pairs.reduce((s,p)=>s+p[1],0); let r=f()*tot;
      for(const[k,w]of pairs){ if((r-=w)<0) return k; } return pairs[pairs.length-1][0];
    }
  };
}

/* =====================================================================
   §CONTENT  (content package)  — pure data. Trivially JSON for Dart.
   ===================================================================== */
const FAMILIES=['spicy','sweet','sour','salty','umami'];
const FAM_EMOJI={spicy:'🌶️',sweet:'🍯',sour:'🍋',salty:'🧂',umami:'🍄'};
const NAMES={
  spicy:['Paprika','Black Pepper','Green Chili','Mustard Seed','Cayenne','Red Chili',"Bird's Eye Chili",'Scotch Bonnet','Ghost Pepper','Carolina Reaper'],
  sweet:['Jaggery','Honey','Date','Fig','Palm Sugar','Maple','Condensed Milk','Caramel','Dark Chocolate','Rose Syrup'],
  sour:['Lime','Lemon','Tamarind','Green Mango','Yogurt','Vinegar','Kokum','Sumac','Amchur','Fermented Lime'],
  salty:['Sea Salt','Rock Salt','Soy Sauce','Fish Sauce','Miso','Olives','Capers','Anchovy','Preserved Lemon','Bottarga'],
  umami:['Mushroom','Tomato','Seaweed','Parmesan','Dashi','Soy Bean','Cured Ham','Dried Shiitake','Aged Cheese','Bonito Flake']
};
// full 52-card pantry: 5 families x ranks 1-10 (+2 prized)
function buildPantry(deckCfg){
  let cards=[];
  for(const fam of FAMILIES) for(let r=1;r<=10;r++)
    cards.push({id:fam+'_'+r, family:fam, rank:r, display:NAMES[fam][r-1], prized:false});
  cards.push({id:'prized_saffron', family:'umami', rank:10, display:'Saffron', prized:true});
  cards.push({id:'prized_ghee',    family:'sweet', rank:10, display:'Ghee',    prized:true});
  const b=deckCfg&&deckCfg.build;   // pantry-deck modifiers
  if(b&&b.family_delta){
    for(const fam in b.family_delta){ const d=b.family_delta[fam];
      if(d>0){ const rk=[3,5,7,9]; for(let i=0;i<d;i++){ const r=rk[i%4]; cards.push({id:fam+'_x'+i,family:fam,rank:r,display:NAMES[fam][r-1],prized:false}); } }
      else if(d<0){ let rm=-d; cards=cards.filter(c=>{ if(rm>0&&c.family===fam&&!c.prized&&c.rank<=4){rm--; return false;} return true; }); }
    }
  }
  if(b&&b.trim){ let t=b.trim; cards=cards.filter(c=>{ if(t>0&&!c.prized&&c.rank<=2){t--; return false;} return true; }); }
  return cards;
}
const PRIZED_BONUS=25;

// recipe base table  (concept doc §3.2 / spec §4)
const PORDER=['high_card','pair','two_pair','three_kind','straight','flush','full_house','four_kind','straight_flush','five_kind','full_family','perfect_palate'];
// Secret recipes (five_kind / full_family / perfect_palate) only appear via blend
// manipulation; they show as ??? in the Recipe Book until discovered once.
const SECRET_PATTERNS=['five_kind','full_family','perfect_palate'];
const RECIPE={
  high_card:{flavor:5,heat:1}, pair:{flavor:10,heat:2}, two_pair:{flavor:20,heat:2},
  three_kind:{flavor:30,heat:3}, straight:{flavor:30,heat:4}, flush:{flavor:35,heat:4},
  full_house:{flavor:40,heat:4}, four_kind:{flavor:60,heat:7}, straight_flush:{flavor:100,heat:8},
  five_kind:{flavor:120,heat:10}, full_family:{flavor:130,heat:12}, perfect_palate:{flavor:160,heat:14}
};
// recipe leveling — Festival Cards raise a recipe's base flavor & heat for the run.
// This is the exponential-scaling engine (Balatro's planet cards): leveled base × utensil
// multipliers is what lets late-city scores reach the big targets. Level 1 = no bonus.
const LEVEL_BONUS={
  high_card:{flavor:4,heat:1}, pair:{flavor:8,heat:1}, two_pair:{flavor:12,heat:1},
  three_kind:{flavor:16,heat:2}, straight:{flavor:20,heat:2}, flush:{flavor:22,heat:2},
  full_house:{flavor:28,heat:3}, four_kind:{flavor:40,heat:4}, straight_flush:{flavor:70,heat:5},
  five_kind:{flavor:80,heat:6}, full_family:{flavor:90,heat:7}, perfect_palate:{flavor:110,heat:8}
};
const GENERIC={high_card:'High Card',pair:'Pair',two_pair:'Two Pair',three_kind:'Three of a Kind',
  straight:'Straight',flush:'Flush',full_house:'Full House',four_kind:'Four of a Kind',straight_flush:'Straight Flush',
  five_kind:'Five of a Kind',full_family:'Family Feast',perfect_palate:'Perfect Palate'};

// regional dish names per city (concept doc §2.1) — pure data, zero mechanical cost
const DISH_NAMES={
  kochi:{high_card:'Street Snack',pair:'Chaat',two_pair:'Meals Combo',three_kind:'Curry',straight:'Sadya',flush:'Signature Thali',full_house:'Feast',four_kind:'Royal Curry',straight_flush:'Royal Biryani',five_kind:'Royal Sadya',full_family:'Purist Thali',perfect_palate:'The Maharaja'},
  tokyo:{high_card:'Bento Bite',pair:'Onigiri',two_pair:'Teishoku',three_kind:'Ramen',straight:'Sushi Set',flush:'Omakase',full_house:'Donburi Feast',four_kind:'Wagyu Course',straight_flush:'Kaiseki',five_kind:"Emperor's Kaiseki",full_family:'Pure Omakase',perfect_palate:'The Shogun'},
  naples:{high_card:'Cicchetti',pair:'Bruschetta',two_pair:'Antipasti',three_kind:'Risotto',straight:'Primi e Secondi',flush:'Margherita',full_house:'Festa',four_kind:'Quattro Formaggi',straight_flush:"Nonna's Feast",five_kind:'Grand Festa',full_family:'Monovarietale',perfect_palate:'Il Capolavoro'}
};

// 20 M0 utensils (spec §6). effect DSL. NOTE: a few condition/effect keys
// (num_cards, all_cards_same_family, pattern_at_least, heat_per_card) extend the
// spec's starter list to express Wok/Bamboo/Emperor/Butcher/Griddle — carry them to Dart.
const UTENSILS=[
  // commons (cost 4)
  {id:'iron_tawa',name:'Iron Tawa',rarity:'common',cost:4,trigger:'on_dish',condition:{min_cards:3},effect:{flavor_add:30},text:'+30 flavor if the dish has 3+ ingredients'},
  {id:'mint_garnish',name:'Mint Garnish',rarity:'common',cost:4,trigger:'on_dish',condition:{contains_family:'sour'},effect:{heat_add:4},text:'+4 heat if the dish contains a Sour ingredient'},
  {id:'salt_cellar',name:'Salt Cellar',rarity:'common',cost:4,trigger:'on_dish',condition:{contains_family:'salty'},effect:{heat_add:3},text:'+3 heat if the dish contains a Salty ingredient'},
  {id:'honey_jar',name:'Honey Jar',rarity:'common',cost:4,trigger:'on_dish',condition:{contains_family:'sweet'},effect:{flavor_add:25},text:'+25 flavor if the dish contains a Sweet ingredient'},
  {id:'stock_pot',name:'Stock Pot',rarity:'common',cost:4,trigger:'on_dish',condition:{contains_family:'umami'},effect:{heat_add:2},text:'+2 heat if the dish contains an Umami ingredient'},
  {id:'street_cart',name:'Street Cart',rarity:'common',cost:4,trigger:'on_dish',condition:null,effect:{coin_add:1},text:'+1 coin per dish played'},
  {id:'big_spoon',name:'Big Spoon',rarity:'common',cost:4,trigger:'on_dish',condition:{pattern_is:'pair'},effect:{flavor_add:20},text:'+20 flavor if the recipe is a Pair'},
  {id:'rice_cooker',name:'Rice Cooker',rarity:'common',cost:4,trigger:'on_dish',condition:{pattern_is:'three_kind'},effect:{flavor_add:30},text:'+30 flavor if the recipe is Three of a Kind'},
  // uncommons (cost 6)
  {id:'tandoor',name:'Tandoor',rarity:'uncommon',cost:6,trigger:'on_dish',condition:{all_cards_family:'spicy'},effect:{heat_mult:1.5},text:'×1.5 heat if every ingredient is Spicy'},
  {id:'pressure_cooker',name:'Pressure Cooker',rarity:'uncommon',cost:6,trigger:'on_card',condition:null,effect:{retrigger_highest:true},text:'Retrigger the highest-intensity ingredient'},
  {id:'wok',name:'Wok',rarity:'uncommon',cost:6,trigger:'on_dish',condition:{all_cards_same_family:true},effect:{heat_mult:1.5},text:'×1.5 heat if all ingredients share a flavor family'},
  {id:'chai_stall',name:'Chai Stall',rarity:'uncommon',cost:6,trigger:'on_dish',condition:{pattern_is:'pair'},effect:{coin_add:2},text:'+2 coins when you cook a Pair'},
  {id:'bamboo_steamer',name:'Bamboo Steamer',rarity:'uncommon',cost:6,trigger:'on_dish',condition:{num_cards:3},effect:{heat_add:5},text:'+5 heat if exactly 3 ingredients'},
  {id:'butchers_block',name:"Butcher's Block",rarity:'uncommon',cost:6,trigger:'on_dish',condition:{pattern_at_least:'full_house'},effect:{flavor_add:40},text:'+40 flavor if the recipe is Full House or better'},
  {id:'ice_box',name:'Ice Box',rarity:'uncommon',cost:6,trigger:'on_dish',condition:{is_first_dish:true},effect:{heat_mult:2},text:'First dish of each service gets ×2 heat'},
  {id:'griddle',name:'Griddle',rarity:'uncommon',cost:6,trigger:'on_dish',condition:null,effect:{heat_per_card:1},text:'+1 heat per ingredient played'},
  // rares (cost 9)
  {id:'clay_handi',name:'Clay Handi',rarity:'rare',cost:9,trigger:'on_dish',condition:{is_last_dish:true},effect:{heat_mult:3},text:'Last dish of each service gets ×3 heat'},
  {id:'grandmother_ladle',name:"Grandmother's Ladle",rarity:'rare',cost:9,trigger:'on_dish',condition:null,effect:{copy_right:true},text:'Copies the effect of the utensil to its right'},
  {id:'golden_sieve',name:'Golden Sieve',rarity:'rare',cost:9,trigger:'on_dish',condition:{pattern_is:'flush'},effect:{flavor_add:50,heat_add:3},text:'Flushes get +50 flavor and +3 heat'},
  {id:'emperors_wok',name:"Emperor's Wok",rarity:'rare',cost:9,trigger:'on_dish',condition:{num_cards:5},effect:{heat_mult:2},text:'×2 heat if the dish uses 5 ingredients'}
];
const UTIL_BY_ID=Object.fromEntries(UTENSILS.map(u=>[u.id,u]));
const RARITY_WEIGHTS=[['common',60],['uncommon',30],['rare',10]];

// 6 spice blends (consumables). `select` = how many held cards to target.
const BLENDS=[
  {id:'chili_oil',name:'Chili Oil',cost:3,select:2,desc:'Turn up to 2 selected ingredients Spicy 🌶️'},
  {id:'sea_salt',name:'Sea Salt',cost:3,select:2,desc:'Turn up to 2 selected ingredients Salty 🧂'},
  {id:'fermentation',name:'Fermentation',cost:3,select:1,desc:'+3 intensity to 1 selected ingredient'},
  {id:'sun_dry',name:'Sun-Dry',cost:3,select:1,desc:'Duplicate 1 selected ingredient into your hand'},
  {id:'sharpen',name:'Whetstone',cost:4,select:1,desc:'Set 1 selected ingredient to intensity 10'},
  {id:'mise',name:'Mise en Place',cost:3,select:0,desc:'Draw 2 extra ingredients this turn'}
];
const BLEND_BY_ID=Object.fromEntries(BLENDS.map(b=>[b.id,b]));

// Festival Cards (planet-analog): each permanently levels one recipe for the run.
// This is the scaling engine — leveled base × utensils is how late-city scores reach the big targets.
const FESTIVALS=[
  {id:'fest_pair',    pattern:'pair',          name:'Sankranti',  cost:3},
  {id:'fest_three',   pattern:'three_kind',    name:'Onam',       cost:3},
  {id:'fest_straight',pattern:'straight',      name:'Baisakhi',   cost:3},
  {id:'fest_flush',   pattern:'flush',         name:'Holi',       cost:3},
  {id:'fest_full',    pattern:'full_house',    name:'Diwali',     cost:3},
  {id:'fest_four',    pattern:'four_kind',     name:'Pongal',     cost:4},
  {id:'fest_sflush',  pattern:'straight_flush',name:'Kumbh Mela', cost:4}
];
const FEST_BY_ID=Object.fromEntries(FESTIVALS.map(f=>[f.id,f]));

// city palates (spec §7). Different shapes on purpose.
const PALATES={
  kochi:{city:'kochi',label:'Sour ingredients give +50% intensity as flavor',perCardFlavorPct:{family:'sour',pct:50}},
  tokyo:{city:'tokyo',label:'Umami ingredients give +2 heat each',perCardHeat:{family:'umami',add:2}},
  naples:{city:'naples',label:'Flush dishes get +40 flavor',dishFlavorIfPattern:{pattern:'flush',add:40}}
};
// critics (boss demands)
const CRITICS={
  minimalist:{id:'minimalist',name:'The Minimalist',rule:'Dishes may use at most 3 ingredients',max_cards:3},
  traditionalist:{id:'traditionalist',name:'The Traditionalist',rule:'Sweet ingredients contribute 0 intensity (and no palate bonus)',debuff:'sweet'}
};
// 3-city mini-run (spec §7)
const CITIES=[
  {id:'kochi', name:'Kochi 🇮🇳',  targets:[300,800,1200],     critic:'minimalist'},
  {id:'tokyo', name:'Tokyo 🇯🇵',  targets:[3500,6000,11000],  critic:'traditionalist'},
  {id:'naples',name:'Naples 🇮🇹', targets:[18000,30000,50000],critic:'traditionalist'}
];
const SERVICE_NAMES=['Lunch Rush','Dinner Rush','The Food Critic'];

/* =====================================================================
   §ENGINE  (game_core)  — pattern detection + exact scoring order-of-ops.
   Pure functions. No state, no DOM.
   ===================================================================== */
function bestPattern(cards){
  const n=cards.length, byRank={}, byFam={};
  cards.forEach(c=>{byRank[c.rank]=(byRank[c.rank]||0)+1; byFam[c.family]=(byFam[c.family]||0)+1;});
  const uniq=Object.keys(byRank).map(Number).sort((a,b)=>a-b);
  const isFlush=n===5 && Object.keys(byFam).length===1;
  const isStraight=n===5 && uniq.length===5 && (uniq[4]-uniq[0]===4);
  const oneFamily=Object.keys(byFam).length===1;
  const ranksWith=(k)=>Object.keys(byRank).map(Number).filter(r=>byRank[r]>=k);
  const take=(ranks,per)=>{const t={},out=[];for(const c of cards){if(ranks.includes(c.rank)){t[c.rank]=t[c.rank]||0;if(t[c.rank]<per){out.push(c);t[c.rank]++;}}}return out;};
  // SECRET recipes (only reachable via blend manipulation) — check first
  const fives=ranksWith(5);
  if(n===5&&fives.length&&oneFamily) return {pattern:'perfect_palate',scoring:cards.slice()};
  if(n===5&&fives.length) return {pattern:'five_kind',scoring:cards.slice()};
  const trip0=ranksWith(3);
  if(n===5&&oneFamily&&trip0.length&&ranksWith(2).some(r=>r!==Math.max(...trip0))) return {pattern:'full_family',scoring:cards.slice()};
  if(isFlush&&isStraight) return {pattern:'straight_flush',scoring:cards.slice()};
  const fours=ranksWith(4); if(fours.length) return {pattern:'four_kind',scoring:take([Math.max(...fours)],4)};
  const trips=ranksWith(3);
  if(n===5&&trips.length){const t=Math.max(...trips); if(ranksWith(2).some(r=>r!==t)) return {pattern:'full_house',scoring:cards.slice()};}
  if(isFlush) return {pattern:'flush',scoring:cards.slice()};
  if(isStraight) return {pattern:'straight',scoring:cards.slice()};
  if(trips.length) return {pattern:'three_kind',scoring:take([Math.max(...trips)],3)};
  const pairs=ranksWith(2);
  if(pairs.length>=2) return {pattern:'two_pair',scoring:take(pairs.sort((a,b)=>b-a).slice(0,2),2)};
  if(pairs.length===1) return {pattern:'pair',scoring:take([pairs[0]],2)};
  let hi=cards[0]; for(const c of cards) if(c.rank>hi.rank) hi=c;
  return {pattern:'high_card',scoring:[hi]};
}

// how much one scoring card adds (intensity + prized + per-card palate + critic debuff)
function cardContribution(card,ctx){
  const debuffed=ctx.critic&&ctx.critic.debuff===card.family;
  let intensity=debuffed?0:card.rank, dF=intensity, dH=0;
  if(card.prized&&!debuffed) dF+=PRIZED_BONUS;
  if(!debuffed&&ctx.palate){
    const p=ctx.palate;
    if(p.perCardFlavorPct&&p.perCardFlavorPct.family===card.family) dF+=intensity*p.perCardFlavorPct.pct/100;
    if(p.perCardHeat&&p.perCardHeat.family===card.family) dH+=p.perCardHeat.add;
  }
  return {dF,dH};
}

// resolve a utensil slot's effective effect (handles Grandmother's Ladle copy, non-recursive)
function resolveSlot(utensils,i){
  const u=utensils[i]; if(!u) return null;
  if(u.effect&&u.effect.copy_right){
    const r=utensils[i+1];
    if(r&&!(r.effect&&r.effect.copy_right)) return {name:u.name+' → '+r.name, trigger:r.trigger, condition:r.condition, effect:r.effect};
    return {name:u.name, trigger:'on_dish', condition:null, effect:{}};
  }
  return u;
}
function condMet(cond,c){
  if(!cond) return true;
  const p=c.playedCards;
  if(cond.all_cards_family&&!p.every(x=>x.family===cond.all_cards_family)) return false;
  if(cond.contains_family&&!p.some(x=>x.family===cond.contains_family)) return false;
  if(cond.all_cards_same_family){const f=p[0].family; if(!p.every(x=>x.family===f)) return false;}
  if(cond.min_cards!=null&&p.length<cond.min_cards) return false;
  if(cond.num_cards!=null&&p.length!==cond.num_cards) return false;
  if(cond.pattern_is&&c.pattern!==cond.pattern_is) return false;
  if(cond.pattern_at_least&&PORDER.indexOf(c.pattern)<PORDER.indexOf(cond.pattern_at_least)) return false;
  if(cond.is_first_dish&&!c.isFirstDish) return false;
  if(cond.is_last_dish&&!c.isLastDish) return false;
  return true;
}

// THE HEART — scoreDish. ctx: {palate, utensils[], critic, isFirstDish, isLastDish}
function scoreDish(playedCards, ctx){
  const {pattern,scoring}=bestPattern(playedCards);
  const base=RECIPE[pattern];
  const lvl=ctx.kitchenLevel||1;
  const lb=LEVEL_BONUS[pattern]||{flavor:0,heat:0};
  const baseF=base.flavor+(lvl-1)*lb.flavor, baseH=base.heat+(lvl-1)*lb.heat;
  const S={flavor:baseF, heat:baseH, coins:0};
  const steps=[]; const log=(t,cls)=>steps.push({t,cls});
  log(`${GENERIC[pattern]}${lvl>1?' Lv'+lvl:''} · base ${baseF} flavor × ${baseH} heat`,'');

  // dish-level palate (Naples flush)
  if(ctx.palate&&ctx.palate.dishFlavorIfPattern&&ctx.palate.dishFlavorIfPattern.pattern===pattern){
    S.flavor+=ctx.palate.dishFlavorIfPattern.add; log(`Palate +${ctx.palate.dishFlavorIfPattern.add} flavor`,'plus');
  }
  // per-card, left→right in played order
  for(const card of scoring){
    const {dF,dH}=cardContribution(card,ctx);
    S.flavor+=dF; S.heat+=dH;
    let d=`${card.display} +${round1(dF)} flavor`+(dH?` +${dH} heat`:'');
    if(ctx.critic&&ctx.critic.debuff===card.family) d=`${card.display} (${card.family} debuffed → 0)`;
    log(d,'plus');
  }
  // retriggers (Pressure Cooker / Ladle-copied): re-run the highest scoring card
  let hi=scoring[0]||null; for(const c of scoring) if(c.rank>hi.rank) hi=c;
  utensils_loop_retrigger(ctx.utensils, hi, ctx, S, log);

  // per-dish utensil triggers, left→right in slot order (additive before multiplicative)
  const c={playedCards, pattern, isFirstDish:ctx.isFirstDish, isLastDish:ctx.isLastDish};
  for(let i=0;i<ctx.utensils.length;i++){
    const eff=resolveSlot(ctx.utensils,i); if(!eff||!eff.effect) continue;
    const e=eff.effect; if(e.retrigger_highest||e.copy_right) continue;
    if(!condMet(eff.condition,c)) continue;
    const before={f:S.flavor,h:S.heat};
    if(e.flavor_add) S.flavor+=e.flavor_add;
    if(e.heat_add) S.heat+=e.heat_add;
    if(e.flavor_per_card) S.flavor+=e.flavor_per_card*playedCards.length;
    if(e.heat_per_card) S.heat+=e.heat_per_card*playedCards.length;
    if(e.coin_add) S.coins+=e.coin_add;
    if(e.heat_mult) S.heat*=e.heat_mult;
    const parts=[];
    if(S.flavor!==before.f) parts.push(`${S.flavor>before.f?'+':''}${round1(S.flavor-before.f)} flavor`);
    if(e.heat_mult) parts.push(`×${e.heat_mult} heat`);
    else if(S.heat!==before.h) parts.push(`+${round1(S.heat-before.h)} heat`);
    if(e.coin_add) parts.push(`+${e.coin_add}🪙`);
    log(`${eff.name}: ${parts.join(', ')||'—'}`, e.heat_mult?'mult':'plus');
  }
  const score=Math.floor(S.flavor*S.heat);
  log(`= ${round1(S.flavor)} flavor × ${round1(S.heat)} heat`,'');
  return {pattern, scoring, flavor:S.flavor, heat:S.heat, coins:S.coins, score, steps};
}
function utensils_loop_retrigger(utensils, hi, ctx, S, log){
  if(!hi) return;
  for(let i=0;i<utensils.length;i++){
    const eff=resolveSlot(utensils,i); if(!eff||!eff.effect||!eff.effect.retrigger_highest) continue;
    const {dF,dH}=cardContribution(hi,ctx);
    S.flavor+=dF; S.heat+=dH;
    log(`${eff.name}: retrigger ${hi.display} (+${round1(dF)} flavor${dH?` +${dH} heat`:''})`,'plus');
  }
}
function round1(n){return Math.round(n*10)/10;}

// dish validity (critic pre-checks) — used to gate COOK
function dishError(playedCards, critic){
  if(playedCards.length<1) return 'Select 1–5 ingredients';
  if(playedCards.length>5) return 'Max 5 ingredients';
  if(critic&&critic.max_cards&&playedCards.length>critic.max_cards) return `${critic.name}: max ${critic.max_cards} ingredients`;
  if(critic&&critic.min_cards&&playedCards.length<critic.min_cards) return `${critic.name}: min ${critic.min_cards} ingredients`;
  if(critic&&critic.require_family&&!playedCards.some(c=>c.family===critic.require_family)) return `${critic.name}: needs a ${critic.require_family[0].toUpperCase()+critic.require_family.slice(1)} ingredient`;
  return null;
}

/* =====================================================================
   §PROGRESSION (game_core + meta) — stakes, decks, achievements, unlocks,
   and the local meta-save. Data mirrors web/data/*.json (schemas §1,§2,§4).
   ===================================================================== */
const STAKES=[
  {id:1,name:'Paprika',chili_icon:'🌶️',modifiers:[]},
  {id:2,name:'Jalapeño',chili_icon:'🌶️',modifiers:[{type:'service_reward_zero',value:'lunch'}]},
  {id:3,name:'Serrano',chili_icon:'🌶️🌶️',modifiers:[{type:'target_scale',from_city:3,pct:25}]},
  {id:4,name:'Cayenne',chili_icon:'🌶️🌶️',modifiers:[{type:'swaps_delta',value:-1}]},
  {id:5,name:"Bird's Eye",chili_icon:'🌶️🌶️🌶️',modifiers:[{type:'shop_inflation_per_city',value:1}]},
  {id:6,name:'Habanero',chili_icon:'🌶️🌶️🌶️',modifiers:[{type:'minor_critic_on_dinner',value:true}]},
  {id:7,name:'Ghost Pepper',chili_icon:'🌶️🌶️🌶️🌶️',modifiers:[{type:'cooks_delta',value:-1}]},
  {id:8,name:'Carolina Reaper',chili_icon:'🔥',modifiers:[{type:'utensil_slots',value:4}]}
];
const STAKE_BY_ID=Object.fromEntries(STAKES.map(s=>[s.id,s]));
// resolve the cumulative config for a stake (each stake includes all below it)
function stakeConfig(stakeId){
  const cfg={cooksDelta:0,swapsDelta:0,utensilSlots:5,lunchRewardZero:false,targetScale:null,shopInflationPerCity:0,minorCriticOnDinner:false};
  for(const st of STAKES){ if(st.id>stakeId) break;
    for(const m of st.modifiers){
      if(m.type==='service_reward_zero') cfg.lunchRewardZero=true;
      else if(m.type==='target_scale') cfg.targetScale={fromCity:m.from_city,pct:m.pct};
      else if(m.type==='swaps_delta') cfg.swapsDelta+=m.value;
      else if(m.type==='cooks_delta') cfg.cooksDelta+=m.value;
      else if(m.type==='shop_inflation_per_city') cfg.shopInflationPerCity+=m.value;
      else if(m.type==='minor_critic_on_dinner') cfg.minorCriticOnDinner=true;
      else if(m.type==='utensil_slots') cfg.utensilSlots=m.value;
    }
  }
  return cfg;
}
// milder critics for Dinner Rush at Habanero+ (a separate, milder pool)
const MINOR_CRITICS=[
  {id:'sweet_tooth',name:'The Sweet Tooth',rule:'Every dish must contain a Sweet ingredient',require_family:'sweet',minor:true},
  {id:'sour_skeptic',name:'The Sour Skeptic',rule:'Sour ingredients are debuffed (0 intensity)',debuff:'sour',minor:true},
  {id:'small_plates',name:'Small Plates',rule:'Dishes may use at most 4 ingredients',max_cards:4,minor:true},
  {id:'salt_hater',name:'The Salt Hater',rule:'Salty ingredients are debuffed',debuff:'salty',minor:true}
];
// --- Decks (decks.json) ---
const DECKS=[
  {id:'home',name:'Home Kitchen',identity:'Balanced 52-card pantry'},
  {id:'coastal',name:'Coastal Pantry',identity:'+4 Sour, −4 Salty; start with 1 Sun-Dry',build:{family_delta:{sour:4,salty:-4}},start_blends:['sun_dry']},
  {id:'royal',name:'Royal Kitchen',identity:'44 cards; start with a random Rare utensil',build:{trim:8},start_rare_utensil:true},
  {id:'hawker',name:'Street Hawker',identity:'Cooks 5, utensil slots 4',cooks:5,utensil_slots:4},
  {id:'monsoon',name:'Monsoon Larder',identity:'Ships with v1.1 Monsoon Mode',reserved:true}
];
const DECK_BY_ID=Object.fromEntries(DECKS.map(d=>[d.id,d]));
const START_UTENSILS=['iron_tawa','salt_cellar','honey_jar','stock_pot','street_cart','big_spoon','mint_garnish','rice_cooker','wok','griddle','pressure_cooker','ice_box'];
const STAKE_GATED_UTENSILS={grandmother_ladle:3}; // cleared this stake (any deck) unlocks it
const VENDOR_IDS=['street_cart','chai_stall'];
// --- Achievements (achievements.json). `cond` is the generalized `threshold`. ---
const ACHIEVEMENTS=[
  {id:'first_dish',name:'Service Started',event:'dish_played',cond:{},reward:{type:'cardback',id:'parchment'},teaches:'You cooked your first dish'},
  {id:'first_flush',name:'First Flush',event:'dish_played',cond:{pattern:'flush'},reward:{type:'utensil',id:'golden_sieve'},teaches:'Flushes are a build, not luck'},
  {id:'feast_mode',name:'Feast Mode',event:'dish_played',cond:{pattern:'full_house'},reward:{type:'utensil',id:'butchers_block'},teaches:'Pattern hierarchy'},
  {id:'big_batch',name:'Big Batch',event:'dish_played',cond:{cards:5},reward:{type:'utensil',id:'emperors_wok'},teaches:'Wide dishes'},
  {id:'ten_grand',name:'Ten Grand',event:'dish_played',cond:{min_score:10000},reward:{type:'utensil',id:'clay_handi'},teaches:'Multiplier stacking'},
  {id:'pure_heat',name:'Pure Heat',event:'dish_played',cond:{all_family:'spicy',min_cards:3},reward:{type:'utensil',id:'tandoor'},teaches:'All-Spicy synergy'},
  {id:'three_peat',name:"Three's Company",event:'dish_played',cond:{pattern:'three_kind'},reward:{type:'cardback',id:'curry'},teaches:'Three of a kind'},
  {id:'two_pair_pro',name:'Double Up',event:'dish_played',cond:{pattern:'two_pair'},reward:{type:'cardback',id:'combo'},teaches:'Two pair'},
  {id:'straight_up',name:'Straight Up',event:'dish_played',cond:{pattern:'straight'},reward:{type:'cardback',id:'sadya'},teaches:'Straights'},
  {id:'four_star',name:'Four-Star Dish',event:'dish_played',cond:{pattern:'four_kind'},reward:{type:'cardback',id:'royal_cb'},teaches:'Four of a kind'},
  {id:'masterpiece',name:'Masterpiece',event:'dish_played',cond:{pattern:'straight_flush'},reward:{type:'cardback',id:'masterpiece'},teaches:'Straight flush',hidden:true},
  {id:'high_roller',name:'High Roller',event:'dish_played',cond:{min_score:1000},reward:{type:'cardback',id:'saffron'},teaches:'Scaling a single dish'},
  {id:'heat_wave',name:'Heat Wave',event:'dish_played',cond:{min_heat:20},reward:{type:'cardback',id:'ember'},teaches:'Heat is the multiplier track'},
  {id:'money_lender',name:'Money Lender',event:'coins_held',cond:{min:20},reward:{type:'utensil',id:'chai_stall'},teaches:'Interest economy'},
  {id:'window_shopper',name:'Window Shopper',event:'reroll_count',cond:{min:10},reward:{type:'cardback',id:'ledger'},teaches:'Reroll value'},
  {id:'kitchen_master',name:'Kitchen Master',event:'kitchen_level',cond:{min:8},reward:{type:'cardback',id:'festival_cb'},teaches:'Festival leveling compounds'},
  {id:'minimal_effort',name:'Minimal Effort',event:'service_cleared',cond:{critic:true,max_cards_all:3},reward:{type:'utensil',id:'bamboo_steamer'},teaches:'Playing around rules'},
  {id:'steady_hands',name:'Steady Hands',event:'service_cleared',cond:{no_swaps:true},reward:{type:'cardback',id:'steady'},teaches:'Discipline with swaps'},
  {id:'globetrotter',name:'Globetrotter',event:'reached_city',cond:{city:2},reward:{type:'cardback',id:'route'},teaches:'The full journey'},
  {id:'first_route',name:'The Route is Yours',event:'run_won',cond:{},reward:{type:'deck',id:'coastal'},teaches:'Beat a full run'},
  {id:'feeling_heat',name:'Feeling the Heat',event:'run_won',cond:{min_stake:2},reward:{type:'deck',id:'royal'},teaches:'Winning at a higher stake'},
  {id:'street_smart',name:'Street Smart',event:'run_won',cond:{vendors:2},reward:{type:'deck',id:'hawker'},teaches:'Vendor (coin) builds'},
  {id:'street_legend',name:'Street Legend',event:'dish_played',cond:{pattern:'five_kind'},reward:{type:'cardback',id:'legend'},teaches:'Duplicate ranks with blends',hidden:true},
  {id:'family_feast',name:'Family Feast',event:'dish_played',cond:{pattern:'full_family'},reward:{type:'cardback',id:'family'},teaches:'Convert a family with Chili Oil',hidden:true},
  {id:'perfect_palate',name:'Perfect Palate',event:'dish_played',cond:{pattern:'perfect_palate'},reward:{type:'cardback',id:'perfect'},teaches:'The apex dish',hidden:true}
];
const ACH_BY_ID=Object.fromEntries(ACHIEVEMENTS.map(a=>[a.id,a]));

// --- Meta-save (localStorage, schema §4) — write-through on every change ---
const PROFILE_KEY='tadka_profile_v1';
function defaultProfile(){return {profile_version:1,unlocks:{utensils:[],blends:[],decks:['home'],cardbacks:[]},achievements_done:[],recipes_discovered:[],stake_progress:{home:1},stats:{runs:0,wins:0,best_dish:0,best_distance:0,total_dishes:0},daily:{last_played:'',streak:0,best_daily_score:0},endless_top10:[]};}
function loadProfile(){try{const p=JSON.parse(localStorage.getItem(PROFILE_KEY)); if(p&&p.profile_version){const d=defaultProfile(); d.unlocks=Object.assign(d.unlocks,p.unlocks||{}); return Object.assign(d,p,{unlocks:d.unlocks});}}catch(e){} return defaultProfile();}
let PROFILE=loadProfile();
function saveProfile(){try{localStorage.setItem(PROFILE_KEY,JSON.stringify(PROFILE));}catch(e){}}
function isUnlocked(type,id){
  if(type==='deck') return id==='home' || PROFILE.unlocks.decks.includes(id);
  if(type==='utensil') return START_UTENSILS.includes(id) || PROFILE.unlocks.utensils.includes(id);
  return (PROFILE.unlocks[type+'s']||[]).includes(id);
}
function unlockThing(type,id){ const k=type+'s'; PROFILE.unlocks[k]=PROFILE.unlocks[k]||[]; if(!PROFILE.unlocks[k].includes(id)){PROFILE.unlocks[k].push(id); saveProfile(); return true;} return false; }
function unlockedUtensilPool(){ return UTENSILS.filter(u=>isUnlocked('utensil',u.id)); }
function unlockedDecks(){ return DECKS.filter(d=>!d.reserved && isUnlocked('deck',d.id)); }
function maxStake(deckId){ return PROFILE.stake_progress[deckId]||1; }
function setStakeProgress(deckId,stake){ if(stake>(PROFILE.stake_progress[deckId]||1)){PROFILE.stake_progress[deckId]=Math.min(8,stake); saveProfile();} }
function recordRecipe(pattern){ if(!PROFILE.recipes_discovered.includes(pattern)){PROFILE.recipes_discovered.push(pattern); saveProfile(); if(SECRET_PATTERNS.includes(pattern)) queueUnlock('🍽 Secret recipe found: '+GENERIC[pattern]);} }
function bumpStat(k,v){ PROFILE.stats[k]=(PROFILE.stats[k]||0)+v; saveProfile(); }
function setBest(k,v){ if(v>(PROFILE.stats[k]||0)){PROFILE.stats[k]=v; saveProfile();} }

// --- Achievement / unlock event bus ---
let unlockQueue=[];
function queueUnlock(msg){ unlockQueue.push(msg); }
function rewardLabel(r){ if(r.type==='utensil') return (UTIL_BY_ID[r.id]||{}).name||r.id; if(r.type==='deck') return (DECK_BY_ID[r.id]||{}).name||r.id; if(r.type==='blend') return (BLEND_BY_ID[r.id]||{}).name||r.id; if(r.type==='cardback') return 'a card back'; return r.id; }
function grantReward(r){ if(r.type==='utensil')return unlockThing('utensil',r.id); if(r.type==='deck')return unlockThing('deck',r.id); if(r.type==='blend')return unlockThing('blend',r.id); if(r.type==='cardback')return unlockThing('cardback',r.id); return false; }
function condMetAch(cond,pl){
  for(const k in cond){ const v=cond[k];
    if(k==='pattern'){ if(pl.pattern!==v) return false; }
    else if(k==='cards'){ if(pl.cards!==v) return false; }
    else if(k==='min_cards'){ if(!(pl.cards>=v)) return false; }
    else if(k==='min_score'){ if(!(pl.score>=v)) return false; }
    else if(k==='min_heat'){ if(!(pl.heat>=v)) return false; }
    else if(k==='all_family'){ if(!(pl.allSameFamily&&pl.family===v)) return false; }
    else if(k==='min'){ if(!(pl.value>=v)) return false; }
    else if(k==='min_stake'){ if(!(pl.stake>=v)) return false; }
    else if(k==='vendors'){ if(!(pl.vendors>=v)) return false; }
    else if(k==='city'){ if(pl.city!==v) return false; }
    else if(k==='critic'){ if(!pl.critic) return false; }
    else if(k==='max_cards_all'){ if(!(pl.maxCardsAll<=v)) return false; }
    else if(k==='no_swaps'){ if(!pl.noSwaps) return false; }
  }
  return true;
}
function emit(event,payload){
  payload=payload||{};
  for(const a of ACHIEVEMENTS){
    if(a.event!==event || PROFILE.achievements_done.includes(a.id)) continue;
    if(!condMetAch(a.cond||{},payload)) continue;
    PROFILE.achievements_done.push(a.id); const got=grantReward(a.reward); saveProfile();
    queueUnlock('🏆 '+a.name+(got?' — unlocked '+rewardLabel(a.reward):''));
  }
}

/* =====================================================================
   §RUN  (game_core)  — run state machine, economy, bazaar.
   ===================================================================== */
function newRun(opts){
  if(typeof opts==='string') opts={seed:opts};
  const seedStr=opts.seed, stake=Math.max(1,Math.min(8,opts.stake||1)), deckId=opts.deckId||'home';
  const deckCfg=DECK_BY_ID[deckId]||DECK_BY_ID.home;
  const rng=makeRng(seedStr);
  const naplesCritic = rng.next()<0.5 ? 'minimalist':'traditionalist';
  const sc=stakeConfig(stake);
  const cooksBase=(deckCfg.cooks||4)+sc.cooksDelta;
  const swapsBase=3+sc.swapsDelta;
  const utensilSlots=Math.min(deckCfg.utensil_slots||5, sc.utensilSlots);
  let finalBaseTarget=CITIES[2].targets[2];
  if(sc.targetScale && 3>=sc.targetScale.fromCity) finalBaseTarget=Math.round(finalBaseTarget*(1+sc.targetScale.pct/100));
  const run={
    seed:seedStr, rng, naplesCritic, stake, deckId, deckCfg, sc,
    cooksBase, swapsBase, utensilSlots,
    cityIndex:0, serviceIndex:0,
    coins:4, utensils:[], blends:[], kitchenLevel:1,
    history:[], status:'playing', totalScore:0, rerolls:0,
    endless:false, endlessCity:0, endlessBase:0, endlessCityObj:null, distance:0, finalBaseTarget,
    deck:[], hand:[], target:0, score:0, cooksLeft:cooksBase, swapsLeft:swapsBase, dishesPlayed:0, critic:null,
    svcMaxCards:0, svcSwapsUsed:0
  };
  if(deckCfg.start_blends) for(const bid of deckCfg.start_blends){ const b=BLEND_BY_ID[bid]; if(b) run.blends.push({...b}); }
  if(deckCfg.start_rare_utensil){ const rares=UTENSILS.filter(u=>u.rarity==='rare'); if(rares.length) run.utensils.push({...rng.pick(rares)}); }
  bumpStat('runs',1);
  startService(run);
  return run;
}
function cityOf(run){ return run.endless ? run.endlessCityObj : CITIES[run.cityIndex]; }
function activeCritic(run){
  if(run.endless) return run.serviceIndex===2 ? run.endlessCityObj.criticObj : null;
  if(run.serviceIndex===2){ const c=cityOf(run); let id=c.critic; if(id==='random') id=run.naplesCritic; return CRITICS[id]; }
  if(run.serviceIndex===1 && run.sc.minorCriticOnDinner) return run.rng.pick(MINOR_CRITICS);
  return null;
}
function startService(run){
  const city=cityOf(run);
  run.deck=run.rng.shuffle(buildPantry(run.deckCfg));
  run.hand=run.deck.splice(0,8);
  let tgt=city.targets[run.serviceIndex];
  if(!run.endless && run.sc.targetScale && (run.cityIndex+1)>=run.sc.targetScale.fromCity) tgt=Math.round(tgt*(1+run.sc.targetScale.pct/100));
  run.target=tgt;
  run.score=0; run.cooksLeft=run.cooksBase; run.swapsLeft=run.swapsBase; run.dishesPlayed=0;
  run.svcMaxCards=0; run.svcSwapsUsed=0;
  run.critic=activeCritic(run);
  if(!run.endless) emit('reached_city',{city:run.cityIndex});
}
function mergeCritics(a,b){
  const m={id:'legend',name:'Legend — '+a.name.replace('The ','')+' + '+b.name.replace('The ',''),rule:a.rule+' · '+b.rule,legend:true};
  ['max_cards','min_cards','debuff','require_family'].forEach(k=>{ if(a[k]!=null)m[k]=a[k]; if(b[k]!=null)m[k]=b[k]; });
  if(a.max_cards&&b.max_cards) m.max_cards=Math.min(a.max_cards,b.max_cards);
  return m;
}
function startEndlessCity(run,k){
  run.endless=true; run.endlessCity=k;
  const G=2.0+0.25*(k-1);
  run.endlessBase=(k===1?run.finalBaseTarget:run.endlessBase)*G;
  const cid=run.rng.pick(['kochi','tokyo','naples']);
  const majors=[CRITICS.minimalist,CRITICS.traditionalist];
  const critic=(k%3===0)?mergeCritics(run.rng.pick(majors),run.rng.pick(MINOR_CRITICS)):run.rng.pick(majors.concat(MINOR_CRITICS));
  run.endlessCityObj={id:cid, name:'The Long Route · '+k, targets:[Math.round(run.endlessBase*0.6),Math.round(run.endlessBase),Math.round(run.endlessBase*1.6)], criticObj:critic};
  run.serviceIndex=0;
  startService(run);
}
function onRunWon(run){
  bumpStat('wins',1);
  setStakeProgress(run.deckId, Math.min(8,run.stake+1));
  for(const id in STAKE_GATED_UTENSILS){ if(run.stake>=STAKE_GATED_UTENSILS[id] && unlockThing('utensil',id)) queueUnlock('🔓 Stake reward: '+(UTIL_BY_ID[id]||{}).name); }
  const vendors=run.utensils.filter(u=>VENDOR_IDS.includes(u.id)).length;
  emit('run_won',{stake:run.stake, deck:run.deckId, vendors});
}
function drawUp(run, to=8){ while(run.hand.length<to && run.deck.length) run.hand.push(run.deck.shift()); }

function ctxFor(run){
  return {
    palate:PALATES[cityOf(run).id], utensils:run.utensils, critic:run.critic, kitchenLevel:run.kitchenLevel,
    isFirstDish:run.dishesPlayed===0, isLastDish:run.cooksLeft===1
  };
}
// commit a cook. returns {result, outcome:'won'|'lost'|'continue'}
function doCook(run, idxs){
  const played=idxs.map(i=>run.hand[i]);
  const err=dishError(played, run.critic); if(err) return {error:err};
  const result=scoreDish(played, ctxFor(run));
  run.score+=result.score; run.coins+=result.coins; run.totalScore+=result.score;
  run.dishesPlayed++; run.cooksLeft--;
  run.svcMaxCards=Math.max(run.svcMaxCards, played.length);
  bumpStat('total_dishes',1); setBest('best_dish',result.score); recordRecipe(result.pattern);
  const fams=[...new Set(played.map(c=>c.family))];
  emit('dish_played',{pattern:result.pattern,score:result.score,heat:result.heat,cards:played.length,allSameFamily:fams.length===1,family:fams[0]});
  // remove played from hand
  run.hand=run.hand.filter((_,i)=>!idxs.includes(i));
  drawUp(run,8);
  let outcome='continue';
  if(run.score>=run.target) outcome='won';
  else if(run.cooksLeft<=0) outcome='lost';
  return {result, outcome};
}
function doSwap(run, idxs){
  if(idxs.length<1) return {error:'Select ingredients to swap'};
  if(run.swapsLeft<=0) return {error:'No swaps left'};
  run.swapsLeft--; run.svcSwapsUsed++;
  run.hand=run.hand.filter((_,i)=>!idxs.includes(i));
  drawUp(run,8);
  return {ok:true};
}
// economy on service win (spec §2 + stakes)
function bankService(run){
  const lunchZero = run.sc.lunchRewardZero && run.serviceIndex===0 && !run.endless;
  const unused=lunchZero?0:run.cooksLeft;
  const interest=Math.min(5, Math.floor(run.coins/5));
  const earned=lunchZero?0:4+run.cooksLeft;
  run.coins+=earned+interest;
  if(run.endless){ run.distance++; setBest('best_distance',run.distance); }
  emit('coins_held',{value:run.coins});
  emit('kitchen_level',{value:run.kitchenLevel});
  emit('service_cleared',{critic:!!run.critic, maxCardsAll:run.svcMaxCards, noSwaps:run.svcSwapsUsed===0});
  run.history.push({city:cityOf(run).name, svc:(run.endless?'Route +'+run.endlessCity:SERVICE_NAMES[run.serviceIndex]), score:run.score, target:run.target, win:true});
  return {base:lunchZero?0:4, unused, interest, earned:earned+interest};
}
function recordLoss(run){
  run.history.push({city:cityOf(run).name, svc:(run.endless?'Route +'+run.endlessCity:SERVICE_NAMES[run.serviceIndex]), score:run.score, target:run.target, win:false});
  run.status='lost';
  if(run.endless) recordEndless(run);
}
function recordEndless(run){
  PROFILE.endless_top10.push({seed:run.seed, distance:run.distance, score:run.totalScore, deck:run.deckId, stake:run.stake});
  PROFILE.endless_top10.sort((a,b)=> b.distance-a.distance || b.score-a.score);
  PROFILE.endless_top10=PROFILE.endless_top10.slice(0,10); saveProfile();
}
// advance after bazaar. sets status 'won' when the whole run is cleared.
function advance(run){
  if(run.endless){
    run.serviceIndex++;
    if(run.serviceIndex>2) startEndlessCity(run, run.endlessCity+1); else startService(run);
    return;
  }
  run.serviceIndex++;
  if(run.serviceIndex>2){ run.serviceIndex=0; run.cityIndex++; }
  if(run.cityIndex>2){ run.status='won'; return; }
  startService(run);
}
function isFinalService(run){ return !run.endless && run.cityIndex===2 && run.serviceIndex===2; }

// bazaar offers
function rollOffers(run){
  const offers=[]; const infl=run.sc.shopInflationPerCity*(run.cityIndex+run.endlessCity);
  const pool=unlockedUtensilPool();
  for(let k=0;k<3;k++){
    const roll=run.rng.next();
    if(roll<0.28){
      const f=run.rng.pick(FESTIVALS);
      offers.push({kind:'festival', id:f.id, name:f.name, cost:f.cost+infl, pattern:f.pattern, rarity:'festival'});
    }else if(roll<0.46){
      const b=run.rng.pick(BLENDS);
      offers.push({kind:'blend', id:b.id, name:b.name, cost:b.cost+infl, desc:b.desc, rarity:'blend'});
    }else{
      const rar=run.rng.weighted(RARITY_WEIGHTS);
      let poolR=pool.filter(u=>u.rarity===rar); if(!poolR.length) poolR=pool;
      const u=run.rng.pick(poolR);
      offers.push({kind:'utensil', id:u.id, name:u.name, cost:u.cost+infl, desc:u.text, rarity:u.rarity});
    }
  }
  return offers;
}


export { makeRng, buildPantry, scoreDish, bestPattern, dishError, cardContribution, newRun,
  startService, ctxFor, bankService, advance, isFinalService, rollOffers, cityOf, activeCritic,
  startEndlessCity, PALATES, CRITICS, MINOR_CRITICS, CITIES, UTENSILS, UTIL_BY_ID, FESTIVALS, BLENDS,
  RARITY_WEIGHTS, STAKES, STAKE_BY_ID, stakeConfig, DECKS, DECK_BY_ID, PROFILE, GENERIC, PORDER };

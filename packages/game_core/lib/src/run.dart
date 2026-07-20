/// §RUN — the run state machine, economy and bazaar.
///
/// A faithful port of the web build, which is the behavioural reference (CLAUDE.md).
/// `test/runs_test.dart` replays scripted runs recorded from the JS engine and compares
/// every field after every action, so any divergence shows up as a trace mismatch.
///
/// **Determinism is the load-bearing property here.** [RunState] owns one [Rng], and every
/// shuffle, critic roll and shop roll draws from it in a fixed order. A run is therefore a
/// pure function of (seed, stake, deck, player choices) — which is what makes seed sharing,
/// reproducible bug reports and the future Daily Route possible. Adding, removing or
/// reordering an RNG draw silently changes every run from that point on, so treat the call
/// order below as part of the contract, not as an implementation detail.
///
/// One deliberate exception to purity: the achievement bus in `progression.dart` reads and
/// writes the global [profile]. Unlocking a utensil mid-run widens the bazaar pool, so run
/// output depends on meta-progress as well as the seed. That is the web build's behaviour
/// and the tests pin it by resetting the profile before each scripted run.
library;

import 'catalog.dart';
import 'engine.dart';
import 'models.dart';
import 'progression.dart';
import 'rng.dart';

/// JS `Math.round`, which is `floor(x + 0.5)` — not Dart's round-half-away-from-zero.
/// Only reached on positive targets, but kept exact so a retune can't drift by one.
int _jsRound(double n) => (n + 0.5).floor();

/// One completed service, for the summary screen.
class ServiceRecord {
  const ServiceRecord({
    required this.city,
    required this.svc,
    required this.score,
    required this.target,
    required this.win,
  });

  final String city;

  /// Service label — `Lunch Rush` / `Dinner Rush` / `The Food Critic`, or `Route +N`.
  final String svc;
  final int score;
  final int target;
  final bool win;
}

/// One bazaar slot.
class Offer {
  const Offer({
    required this.kind,
    required this.id,
    required this.name,
    required this.cost,
    required this.rarity,
    this.desc = '',
    this.pattern,
  });

  /// `festival` | `blend` | `utensil`.
  final String kind;
  final String id;
  final String name;
  final int cost;

  /// `festival` | `blend` for those kinds, else the utensil's rarity — it drives the badge.
  final String rarity;

  /// Empty for festivals: the UI writes its own copy for those, naming the next Kitchen level.
  final String desc;

  /// Festivals only — the recipe the festival is themed on.
  final String? pattern;
}

/// The result of [doCook]. Either [error] is set and nothing happened, or [result] and
/// [outcome] are set and the dish was committed.
class CookOutcome {
  const CookOutcome({this.error, this.result, this.outcome});

  /// Why the dish was rejected, from [dishError]. Null on success.
  final String? error;
  final ScoreResult? result;

  /// `won` (target reached) | `lost` (out of cooks) | `continue`.
  final String? outcome;
}

/// The result of [doSwap].
class SwapOutcome {
  const SwapOutcome({this.error, this.ok = false});

  final String? error;
  final bool ok;
}

/// The service-clear payout breakdown, for the banking animation.
class BankResult {
  const BankResult({
    required this.base,
    required this.unused,
    required this.interest,
    required this.earned,
  });

  /// Flat service reward — 4, or 0 when the stake zeroes out the Lunch reward.
  final int base;

  /// Unused cooks, paid 1 coin each.
  final int unused;

  /// 1 coin per 5 held, capped at 5. The reason banking coins is a real decision.
  final int interest;

  /// Total added to the purse this service, interest included.
  final int earned;
}

/// Everything about a run in progress. Mutable by design: the engine is a reducer over this
/// object, and the UI reads it directly.
class RunState {
  RunState._({
    required this.seed,
    required this.rng,
    required this.naplesCritic,
    required this.stake,
    required this.deckId,
    required this.deckCfg,
    required this.sc,
    required this.cooksBase,
    required this.swapsBase,
    required this.utensilSlots,
    required this.finalBaseTarget,
  }) : cooksLeft = cooksBase,
       swapsLeft = swapsBase;

  final String seed;

  /// The one seeded source for the entire run. See the library doc.
  final Rng rng;

  /// Pre-rolled at run start so a `critic: 'random'` city resolves the same way whenever it
  /// is reached. Unused by the shipped 3-city route, which fixes Naples to the Traditionalist.
  final String naplesCritic;
  final int stake;
  final String deckId;
  final Deck deckCfg;
  final StakeConfig sc;

  /// Cooks and swaps granted at the start of every service, after deck and stake modifiers.
  final int cooksBase;
  final int swapsBase;
  final int utensilSlots;

  /// Naples' finale target after stake scaling — the base the Long Route grows from.
  final int finalBaseTarget;

  int cityIndex = 0;
  int serviceIndex = 0;
  int coins = 4;
  List<Utensil> utensils = <Utensil>[];
  List<Blend> blends = <Blend>[];
  int kitchenLevel = 1;
  List<ServiceRecord> history = <ServiceRecord>[];

  /// `playing` | `won` | `lost`.
  String status = 'playing';
  int totalScore = 0;
  int rerolls = 0;

  bool endless = false;

  /// Long Route index, 1-based. 0 while on the normal route.
  int endlessCity = 0;

  /// Compounding target base for the Long Route. Fractional — only the targets are rounded.
  double endlessBase = 0;

  /// The generated Long Route city, carrying its own rolled critic.
  City? endlessCityObj;

  /// Long Route services cleared. The endless leaderboard sorts on this.
  int distance = 0;

  List<Card> deck = <Card>[];
  List<Card> hand = <Card>[];
  int target = 0;
  int score = 0;
  int cooksLeft;
  int swapsLeft;
  int dishesPlayed = 0;
  Critic? critic;

  /// Widest dish this service, for the Minimal Effort achievement.
  int svcMaxCards = 0;

  /// Swaps used this service, for the Steady Hands achievement.
  int svcSwapsUsed = 0;
}

/// Starts a run and deals the first service.
///
/// RNG draw order — changing it re-rolls every existing seed:
/// 1. the Naples critic coin-flip, 2. the Royal deck's free Rare (that deck only),
/// 3. the first service's shuffle, 4. the Dinner minor critic at Habanero+.
RunState newRun({required String seed, int stake = 1, String deckId = 'home'}) {
  final clamped = stake < 1 ? 1 : (stake > 8 ? 8 : stake);
  final deckCfg = kDeckById[deckId] ?? kDeckById['home']!;
  final rng = Rng(seed);
  final naplesCritic = rng.next() < 0.5 ? 'minimalist' : 'traditionalist';
  final sc = stakeConfig(clamped);
  final deckSlots = deckCfg.utensilSlots ?? 5;

  var finalBaseTarget = kCities[2].targets[2];
  final ts = sc.targetScale;
  if (ts != null && 3 >= ts.fromCity) {
    finalBaseTarget = _jsRound(finalBaseTarget * (1 + ts.pct / 100));
  }

  final run = RunState._(
    seed: seed,
    rng: rng,
    naplesCritic: naplesCritic,
    stake: clamped,
    deckId: deckId,
    deckCfg: deckCfg,
    sc: sc,
    cooksBase: (deckCfg.cooks ?? 4) + sc.cooksDelta,
    swapsBase: 3 + sc.swapsDelta,
    utensilSlots: deckSlots < sc.utensilSlots ? deckSlots : sc.utensilSlots,
    finalBaseTarget: finalBaseTarget,
  );

  for (final bid in deckCfg.startBlends) {
    final b = kBlendById[bid];
    if (b != null) run.blends.add(b);
  }
  if (deckCfg.startRareUtensil) {
    final rares = kUtensils.where((u) => u.rarity == 'rare').toList();
    if (rares.isNotEmpty) run.utensils.add(rng.pick(rares));
  }
  bumpStat('runs', 1);
  startService(run);
  return run;
}

/// The city being played. On the Long Route this is the generated city, not a [kCities] entry.
City cityOf(RunState run) => run.endless ? run.endlessCityObj! : kCities[run.cityIndex];

/// The critic for the current service, or null when there is none.
///
/// Draws from [Rng] on the Habanero+ Dinner branch, so it must be called exactly once per
/// service — [startService] caches the result into `run.critic`.
Critic? activeCritic(RunState run) {
  if (run.endless) return run.serviceIndex == 2 ? run.endlessCityObj!.criticObj : null;
  if (run.serviceIndex == 2) {
    final c = cityOf(run);
    var id = c.critic;
    if (id == 'random') id = run.naplesCritic;
    return kCritics[id];
  }
  if (run.serviceIndex == 1 && run.sc.minorCriticOnDinner) return run.rng.pick(kMinorCritics);
  return null;
}

/// Reshuffles the pantry, deals 8, and resets the per-service counters.
///
/// The deck is rebuilt from scratch every service — cards played are not gone for the run,
/// only for the service.
void startService(RunState run) {
  final city = cityOf(run);
  final shuffled = run.rng.shuffle(buildPantry(run.deckCfg));
  run.hand = shuffled.sublist(0, 8);
  run.deck = shuffled.sublist(8);

  var tgt = city.targets[run.serviceIndex];
  final ts = run.sc.targetScale;
  if (!run.endless && ts != null && (run.cityIndex + 1) >= ts.fromCity) {
    tgt = _jsRound(tgt * (1 + ts.pct / 100));
  }
  run.target = tgt;
  run.score = 0;
  run.cooksLeft = run.cooksBase;
  run.swapsLeft = run.swapsBase;
  run.dishesPlayed = 0;
  run.svcMaxCards = 0;
  run.svcSwapsUsed = 0;
  run.critic = activeCritic(run);
  if (!run.endless) emit('reached_city', AchievementPayload(city: run.cityIndex));
}

/// Combines two critics into one Long Route "Legend" demand.
///
/// [b] wins each shared field, except that two card caps take the tighter of the two.
Critic mergeCritics(Critic a, Critic b) {
  var maxCards = b.maxCards ?? a.maxCards;
  if (a.maxCards != null && b.maxCards != null) {
    maxCards = a.maxCards! < b.maxCards! ? a.maxCards : b.maxCards;
  }
  return Critic(
    id: 'legend',
    name: 'Legend — ${a.name.replaceFirst('The ', '')} + ${b.name.replaceFirst('The ', '')}',
    rule: '${a.rule} · ${b.rule}',
    maxCards: maxCards,
    minCards: b.minCards ?? a.minCards,
    debuff: b.debuff ?? a.debuff,
    requireFamily: b.requireFamily ?? a.requireFamily,
    legend: true,
  );
}

/// Generates Long Route city [k] (1-based) and starts its Lunch service.
///
/// Targets compound: each city multiplies the previous base by 2.0 + 0.25 per city, so the
/// route ends when the numbers outrun the build rather than at a fixed length. Every third
/// city stacks two critics via [mergeCritics].
void startEndlessCity(RunState run, int k) {
  run.endless = true;
  run.endlessCity = k;
  final g = 2.0 + 0.25 * (k - 1);
  run.endlessBase = (k == 1 ? run.finalBaseTarget.toDouble() : run.endlessBase) * g;
  final cid = run.rng.pick(const ['kochi', 'tokyo', 'naples']);
  final majors = [kCritics['minimalist']!, kCritics['traditionalist']!];
  final Critic critic;
  if (k % 3 == 0) {
    // Argument order is an RNG draw order — major first, then minor.
    final major = run.rng.pick(majors);
    final minor = run.rng.pick(kMinorCritics);
    critic = mergeCritics(major, minor);
  } else {
    critic = run.rng.pick([...majors, ...kMinorCritics]);
  }
  run.endlessCityObj = City(
    id: cid,
    name: 'The Long Route · $k',
    targets: [
      _jsRound(run.endlessBase * 0.6),
      _jsRound(run.endlessBase),
      _jsRound(run.endlessBase * 1.6),
    ],
    criticObj: critic,
  );
  run.serviceIndex = 0;
  startService(run);
}

/// Books a completed run: stats, stake progression, stake-gated unlocks, achievements.
///
/// Does not set `status` — the caller does, because the victory screen shows before the
/// summary and the Long Route continues from the same state.
void onRunWon(RunState run) {
  bumpStat('wins', 1);
  setStakeProgress(run.deckId, run.stake + 1 > 8 ? 8 : run.stake + 1);
  for (final e in kStakeGatedUtensils.entries) {
    if (run.stake >= e.value && unlockThing('utensil', e.key)) {
      queueUnlock('🔓 Stake reward: ${kUtensilById[e.key]?.name}');
    }
  }
  final vendors = run.utensils.where((u) => kVendorIds.contains(u.id)).length;
  emit('run_won', AchievementPayload(stake: run.stake, deck: run.deckId, vendors: vendors));
}

/// Refills the hand from the top of the deck.
void drawUp(RunState run, [int to = 8]) {
  while (run.hand.length < to && run.deck.isNotEmpty) {
    run.hand.add(run.deck.removeAt(0));
  }
}

/// The scoring context for the current service state.
ScoreContext ctxFor(RunState run) => ScoreContext(
  palate: kPalates[cityOf(run).id],
  utensils: run.utensils,
  critic: run.critic,
  kitchenLevel: run.kitchenLevel,
  isFirstDish: run.dishesPlayed == 0,
  isLastDish: run.cooksLeft == 1,
);

/// Cooks the hand cards at [idxs] — the dish's cards, in that order.
///
/// Order matters twice over: it decides which cards a pattern's `take` keeps, and utensils
/// fire against the played order. On a rejected dish nothing is mutated.
CookOutcome doCook(RunState run, List<int> idxs) {
  final played = idxs.map((i) => run.hand[i]).toList();
  final err = dishError(played, run.critic);
  if (err != null) return CookOutcome(error: err);

  final result = scoreDish(played, ctxFor(run));
  run.score += result.score;
  run.coins += result.coins;
  run.totalScore += result.score;
  run.dishesPlayed++;
  run.cooksLeft--;
  if (played.length > run.svcMaxCards) run.svcMaxCards = played.length;
  bumpStat('total_dishes', 1);
  setBest('best_dish', result.score);
  recordRecipe(result.pattern);

  final fams = <String>{for (final c in played) c.family}.toList();
  emit('dish_played', AchievementPayload(
    pattern: result.pattern,
    score: result.score,
    heat: result.heat,
    cards: played.length,
    allSameFamily: fams.length == 1,
    family: fams.first,
  ));

  final kept = <Card>[];
  for (var i = 0; i < run.hand.length; i++) {
    if (!idxs.contains(i)) kept.add(run.hand[i]);
  }
  run.hand = kept;
  drawUp(run);

  var outcome = 'continue';
  if (run.score >= run.target) {
    outcome = 'won';
  } else if (run.cooksLeft <= 0) {
    outcome = 'lost';
  }
  return CookOutcome(result: result, outcome: outcome);
}

/// Discards the hand cards at [idxs] and redraws. Costs one swap regardless of how many.
SwapOutcome doSwap(RunState run, List<int> idxs) {
  if (idxs.isEmpty) return const SwapOutcome(error: 'Select ingredients to swap');
  if (run.swapsLeft <= 0) return const SwapOutcome(error: 'No swaps left');
  run.swapsLeft--;
  run.svcSwapsUsed++;
  final kept = <Card>[];
  for (var i = 0; i < run.hand.length; i++) {
    if (!idxs.contains(i)) kept.add(run.hand[i]);
  }
  run.hand = kept;
  drawUp(run);
  return const SwapOutcome(ok: true);
}

/// Pays out a cleared service and files it in the history.
///
/// Interest is 1 coin per 5 held, capped at 5 — the cap is what stops hoarding from
/// dominating, so retuning it changes the whole economy. Unused cooks pay 1 each on top of
/// the flat 4, which is what makes an efficient clear worth more than a narrow one.
BankResult bankService(RunState run) {
  final lunchZero = run.sc.lunchRewardZero && run.serviceIndex == 0 && !run.endless;
  final unused = lunchZero ? 0 : run.cooksLeft;
  final rawInterest = run.coins ~/ 5;
  final interest = rawInterest > 5 ? 5 : rawInterest;
  final earned = lunchZero ? 0 : 4 + run.cooksLeft;
  run.coins += earned + interest;
  if (run.endless) {
    run.distance++;
    setBest('best_distance', run.distance);
  }
  emit('coins_held', AchievementPayload(value: run.coins));
  emit('kitchen_level', AchievementPayload(value: run.kitchenLevel));
  emit('service_cleared', AchievementPayload(
    critic: run.critic != null,
    maxCardsAll: run.svcMaxCards,
    noSwaps: run.svcSwapsUsed == 0,
  ));
  run.history.add(ServiceRecord(
    city: cityOf(run).name,
    svc: run.endless ? 'Route +${run.endlessCity}' : kServiceNames[run.serviceIndex],
    score: run.score,
    target: run.target,
    win: true,
  ));
  return BankResult(base: lunchZero ? 0 : 4, unused: unused, interest: interest, earned: earned + interest);
}

/// Ends the run in defeat and files the failed service.
void recordLoss(RunState run) {
  run.history.add(ServiceRecord(
    city: cityOf(run).name,
    svc: run.endless ? 'Route +${run.endlessCity}' : kServiceNames[run.serviceIndex],
    score: run.score,
    target: run.target,
    win: false,
  ));
  run.status = 'lost';
  if (run.endless) recordEndless(run);
}

/// Files a Long Route attempt on the local leaderboard: top 10 by distance, then score.
void recordEndless(RunState run) {
  profile.endlessTop10.add(EndlessEntry(
    seed: run.seed,
    distance: run.distance,
    score: run.totalScore,
    deck: run.deckId,
    stake: run.stake,
  ));
  profile.endlessTop10.sort((a, b) {
    final d = b.distance - a.distance;
    return d != 0 ? d : b.score - a.score;
  });
  if (profile.endlessTop10.length > 10) {
    profile.endlessTop10 = profile.endlessTop10.sublist(0, 10);
  }
  saveProfile();
}

/// Moves to the next service after the bazaar, setting `status` to `won` when the route ends.
void advance(RunState run) {
  if (run.endless) {
    run.serviceIndex++;
    if (run.serviceIndex > 2) {
      startEndlessCity(run, run.endlessCity + 1);
    } else {
      startService(run);
    }
    return;
  }
  run.serviceIndex++;
  if (run.serviceIndex > 2) {
    run.serviceIndex = 0;
    run.cityIndex++;
  }
  if (run.cityIndex > 2) {
    run.status = 'won';
    return;
  }
  startService(run);
}

/// True on Naples' Food Critic — clearing it wins the run rather than opening a bazaar.
bool isFinalService(RunState run) => !run.endless && run.cityIndex == 2 && run.serviceIndex == 2;

/// Rolls three bazaar offers: ~28% festival, ~18% blend, else a utensil by rarity weight.
///
/// The unlocked pool is snapshotted once, before the loop, so an unlock landing mid-roll
/// cannot change the offers around it. A fresh profile has no Rare unlocked, in which case
/// a Rare roll falls back to the whole pool rather than producing nothing.
List<Offer> rollOffers(RunState run) {
  final offers = <Offer>[];
  final infl = run.sc.shopInflationPerCity * (run.cityIndex + run.endlessCity);
  final pool = unlockedUtensilPool();
  for (var k = 0; k < 3; k++) {
    final roll = run.rng.next();
    if (roll < 0.28) {
      final f = run.rng.pick(kFestivals);
      offers.add(Offer(kind: 'festival', id: f.id, name: f.name, cost: f.cost + infl, pattern: f.pattern, rarity: 'festival'));
    } else if (roll < 0.46) {
      final b = run.rng.pick(kBlends);
      offers.add(Offer(kind: 'blend', id: b.id, name: b.name, cost: b.cost + infl, desc: b.desc, rarity: 'blend'));
    } else {
      final rar = run.rng.weighted(kRarityWeights);
      var poolR = pool.where((u) => u.rarity == rar).toList();
      if (poolR.isEmpty) poolR = pool;
      final u = run.rng.pick(poolR);
      offers.add(Offer(kind: 'utensil', id: u.id, name: u.name, cost: u.cost + infl, desc: u.text, rarity: u.rarity));
    }
  }
  return offers;
}

/// Differential tests for §PROGRESSION and §RUN: the Dart run must unfold exactly like the JS one.
///
/// `vectors_test.dart` proves a single dish scores identically. That says nothing about the
/// machine around it — draw order, the economy, when a critic shows up, which achievement
/// fires, or how an unlock reshapes the next bazaar. Those are where a port drifts, and the
/// drift compounds: one coin fewer in Kochi changes what you can afford for the rest of the
/// run. So `tools/gen-vectors.mjs` plays whole runs through the JS engine under a fixed
/// policy and records the state after every action; this file replays the identical policy
/// and asserts every field.
///
/// **The policy is shared code in two languages.** `_chooseCook`, `_chooseBest`,
/// `_candidateIdxs` and `_policyBuy` mirror the generator's functions line for line, right
/// down to the tie-break order. They are test scaffolding, not engine behaviour — if you
/// change one side you must change the other, or the traces stop lining up and the failure
/// will look like an engine bug when it is not.
///
/// The profile is global in both engines and feeds `rollOffers`, so each case resets it
/// first. Without that, achievements earned by case 3 would widen case 4's shop.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Snapshots — must stay key-for-key identical to the generator's.
// ---------------------------------------------------------------------------

Map<String, Object?>? _criticSnap(Critic? c) => c == null
    ? null
    : {
        'id': c.id,
        'name': c.name,
        'max_cards': c.maxCards,
        'min_cards': c.minCards,
        'debuff': c.debuff,
        'require_family': c.requireFamily,
        'minor': c.minor,
        'legend': c.legend,
      };

/// Everything is copied. The profile's lists and maps are mutated in place as the run goes
/// on, so a snapshot holding references would silently show the *final* state at every step
/// and the whole trace would compare equal to itself.
Map<String, Object?> _profileSnap() => {
  'utensils': List<String>.of(profile.unlocks['utensils'] ?? const []),
  'blends': List<String>.of(profile.unlocks['blends'] ?? const []),
  'decks': List<String>.of(profile.unlocks['decks'] ?? const []),
  'cardbacks': List<String>.of(profile.unlocks['cardbacks'] ?? const []),
  'achievements': List<String>.of(profile.achievementsDone),
  'recipes': List<String>.of(profile.recipesDiscovered),
  'stats': Map<String, int>.of(profile.stats),
  'stake_progress': Map<String, int>.of(profile.stakeProgress),
  'endless_top10': profile.endlessTop10.map((e) => e.toJson()).toList(),
};

Map<String, Object?> _coreSnap(RunState run) {
  final city = (run.endless || run.cityIndex <= 2) ? cityOf(run) : null;
  return {
    'cityIndex': run.cityIndex,
    'serviceIndex': run.serviceIndex,
    'cityName': city?.name,
    'cityTargets': city == null ? null : List<int>.of(city.targets),
    'target': run.target,
    'score': run.score,
    'coins': run.coins,
    'kitchenLevel': run.kitchenLevel,
    'cooksLeft': run.cooksLeft,
    'swapsLeft': run.swapsLeft,
    'dishesPlayed': run.dishesPlayed,
    'totalScore': run.totalScore,
    'hand': run.hand.map((c) => c.id).toList(),
    'deckLen': run.deck.length,
    'critic': _criticSnap(run.critic),
    'status': run.status,
    'utensils': run.utensils.map((u) => u.id).toList(),
    'blends': run.blends.map((b) => b.id).toList(),
    'endless': run.endless,
    'endlessCity': run.endlessCity,
    'distance': run.distance,
    'svcMaxCards': run.svcMaxCards,
    'svcSwapsUsed': run.svcSwapsUsed,
    'historyLen': run.history.length,
  };
}

Map<String, Object?> _snap(RunState run, String tag, [Map<String, Object?>? extra]) => {
  'tag': tag,
  ..._coreSnap(run),
  'unlocks': drainUnlockQueue(),
  'profile': _profileSnap(),
  ...?extra,
};

Map<String, Object?> _offerSnap(Offer o) => {
  'kind': o.kind,
  'id': o.id,
  'name': o.name,
  'cost': o.cost,
  'rarity': o.rarity,
  'desc': o.desc,
  'pattern': o.pattern,
};

// ---------------------------------------------------------------------------
// The scripted policy — mirrors tools/gen-vectors.mjs exactly.
// ---------------------------------------------------------------------------

/// Every size-1..cap subset of hand indices, depth first. The order is the tie-break for
/// [_chooseBest], so it is part of the policy contract.
List<List<int>> _candidateIdxs(int handLen, int cap) {
  final out = <List<int>>[];
  final acc = <int>[];
  void rec(int start) {
    if (acc.isNotEmpty) out.add(List<int>.of(acc));
    if (acc.length == cap) return;
    for (var i = start; i < handLen; i++) {
      acc.add(i);
      rec(i + 1);
      acc.removeLast();
    }
  }

  rec(0);
  return out;
}

/// JS `run.critic && run.critic.max_cards ? run.critic.max_cards : 5` — 0 is falsy there.
int _capOf(RunState run) {
  final mc = run.critic?.maxCards;
  return (mc != null && mc != 0) ? mc : 5;
}

/// Policy B: the highest-scoring legal dish, ties to the earliest candidate.
List<int>? _chooseBest(RunState run) {
  final raw = _capOf(run);
  final cap = raw < 5 ? raw : 5;
  final ctx = ctxFor(run);
  List<int>? best;
  var bestScore = -1;
  for (final idxs in _candidateIdxs(run.hand.length, cap)) {
    final cards = idxs.map((i) => run.hand[i]).toList();
    if (dishError(cards, run.critic) != null) continue;
    final s = scoreDish(cards, ctx).score;
    if (s > bestScore) {
      bestScore = s;
      best = idxs;
    }
  }
  return best;
}

/// Policy A: the first N hand indices, narrowed to whatever the critic allows.
List<int>? _chooseCook(RunState run) {
  final cap = _capOf(run);
  var n = 5;
  if (cap < n) n = cap;
  if (run.hand.length < n) n = run.hand.length;
  if (n < 1) return null;
  var idxs = <int>[for (var i = 0; i < n; i++) i];
  final req = run.critic?.requireFamily;
  if (req != null && !idxs.any((i) => run.hand[i].family == req)) {
    final j = run.hand.indexWhere((c) => c.family == req);
    if (j < 0) return null;
    idxs[idxs.length - 1] = j;
  }
  idxs = idxs.toSet().toList()..sort();
  final mn = run.critic?.minCards;
  final min = (mn != null && mn != 0) ? mn : 0;
  if (idxs.length < min) return null;
  return idxs;
}

const Map<String, int> _buyPriority = {'festival': 0, 'utensil': 1, 'blend': 2};

bool _canBuy(RunState run, Offer o) =>
    run.coins >= o.cost &&
    !(o.kind == 'utensil' && run.utensils.length >= run.utensilSlots) &&
    !(o.kind == 'blend' && run.blends.length >= 3);

/// Buys by priority then slot index, repeating while anything is affordable. Skips the two
/// cosmetic emits §UI does on purchase, exactly as the generator does.
List<Map<String, Object?>> _policyBuy(RunState run, List<Offer> offers) {
  final bought = <Map<String, Object?>>[];
  final remaining = List<Offer>.of(offers);
  while (true) {
    var pick = -1;
    for (var i = 0; i < remaining.length; i++) {
      if (!_canBuy(run, remaining[i])) continue;
      if (pick < 0 || _buyPriority[remaining[i].kind]! < _buyPriority[remaining[pick].kind]!) {
        pick = i;
      }
    }
    if (pick < 0) break;
    final o = remaining[pick];
    run.coins -= o.cost;
    if (o.kind == 'utensil') {
      run.utensils.add(kUtensilById[o.id]!);
    } else if (o.kind == 'festival') {
      run.kitchenLevel++;
    } else {
      run.blends.add(kBlendById[o.id]!);
    }
    bought.add({'kind': o.kind, 'id': o.id, 'cost': o.cost});
    remaining.removeAt(pick);
  }
  return bought;
}

List<Map<String, Object?>> _playRun(Map<String, dynamic> combo) {
  profile = defaultProfile();
  drainUnlockQueue();
  final steps = <Map<String, Object?>>[];
  final run = newRun(
    seed: combo['seed'] as String,
    stake: combo['stake'] as int,
    deckId: combo['deckId'] as String,
  );
  steps.add(_snap(run, 'start', {
    'cooksBase': run.cooksBase,
    'swapsBase': run.swapsBase,
    'utensilSlots': run.utensilSlots,
    'finalBaseTarget': run.finalBaseTarget,
    'naplesCritic': run.naplesCritic,
  }));

  final boost = combo['boost'] as int?;
  if (boost != null) {
    run.cityIndex = 2;
    run.serviceIndex = 2;
    run.kitchenLevel = boost;
    startService(run);
    steps.add(_snap(run, 'boost'));
  }

  final useBest = combo['policy'] == 'best';
  final swapFirst = combo['swapFirst'] as bool;
  var swapped = false;
  var guard = 0;
  while (run.status == 'playing' && guard < 600) {
    guard++;
    if (swapFirst && !swapped && run.swapsLeft > 0 && run.dishesPlayed == 0) {
      swapped = true;
      final sw = doSwap(run, [0, 1]);
      steps.add(_snap(run, 'swap', {'swapError': sw.error, 'swapOk': sw.ok}));
      continue;
    }
    final idxs = useBest ? _chooseBest(run) : _chooseCook(run);
    if (idxs == null) {
      steps.add(_snap(run, 'stuck'));
      break;
    }
    final res = doCook(run, idxs);
    steps.add(_snap(run, 'cook', {
      'idxs': idxs,
      'cookError': res.error,
      'pattern': res.result?.pattern,
      'dishScore': res.result?.score,
      'dishFlavor': res.result?.flavor,
      'dishHeat': res.result?.heat,
      'dishCoins': res.result?.coins,
      'outcome': res.outcome,
    }));
    if (res.error != null) {
      steps.add(_snap(run, 'stuck'));
      break;
    }

    if (res.outcome == 'won') {
      final bank = bankService(run);
      steps.add(_snap(run, 'bank', {
        'bank': {
          'base': bank.base,
          'unused': bank.unused,
          'interest': bank.interest,
          'earned': bank.earned,
        },
      }));
      if (isFinalService(run)) {
        onRunWon(run);
        run.status = 'won';
        steps.add(_snap(run, 'runWon'));
        break;
      }
      final offers = rollOffers(run);
      steps.add(_snap(run, 'offers', {'offers': offers.map(_offerSnap).toList()}));
      steps.add(_snap(run, 'buy', {'bought': _policyBuy(run, offers)}));
      advance(run);
      steps.add(_snap(run, 'advance'));
      swapped = false;
      continue;
    }
    if (res.outcome == 'lost') {
      recordLoss(run);
      steps.add(_snap(run, 'loss'));
      break;
    }
  }
  return steps;
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

/// Structural equality that treats JSON's 3 and Dart's 3.0 as equal — `jsonDecode` narrows
/// whole doubles to int, and flavour/heat are genuinely fractional.
bool _deepEq(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEq(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

String _show(Object? v) {
  try {
    return jsonEncode(v);
  } catch (_) {
    return '$v';
  }
}

/// Compares one recorded snapshot against the replay's, field by field so the failure names
/// the field that moved rather than dumping two large maps.
void _expectSnap(Map<String, dynamic> want, Map<String, Object?> got, String where) {
  expect(got.keys.toSet(), equals(want.keys.toSet()),
      reason: '$where — snapshot fields differ; the Dart and JS snapshots must match key for key');
  for (final k in want.keys) {
    expect(_deepEq(want[k], got[k]), isTrue,
        reason: '$where · $k\n    recorded (JS): ${_show(want[k])}\n    replayed (Dart): ${_show(got[k])}');
  }
}

void main() {
  final file = File('test/vectors.json');
  if (!file.existsSync()) {
    throw StateError('test/vectors.json missing — regenerate with: node tools/gen-vectors.mjs');
  }
  final v = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  if (!v.containsKey('runs')) {
    throw StateError('test/vectors.json predates the §RUN traces — regenerate with: node tools/gen-vectors.mjs');
  }

  test('a fresh meta-save serializes byte for byte like tadka_profile_v1', () {
    expect(jsonEncode(defaultProfile().toJson()), equals(v['defaultProfile']));
  });

  test('stakeConfig resolves cumulatively for every stake', () {
    for (final c in (v['stakes'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final id = c['id'] as int;
      final cfg = stakeConfig(id);
      final ts = cfg.targetScale;
      _expectSnap(c, {
        'id': id,
        'cooksDelta': cfg.cooksDelta,
        'swapsDelta': cfg.swapsDelta,
        'utensilSlots': cfg.utensilSlots,
        'lunchRewardZero': cfg.lunchRewardZero,
        'targetScale': ts == null ? null : {'fromCity': ts.fromCity, 'pct': ts.pct},
        'shopInflationPerCity': cfg.shopInflationPerCity,
        'minorCriticOnDinner': cfg.minorCriticOnDinner,
      }, 'stake $id');
    }
  });

  test('stake modifiers describe themselves in the web build\'s words', () {
    // Hand-checked against §UI's modLabel in web/tadka.html — the stake picker shows these.
    expect(
      kStakes.expand((s) => s.modifiers).map((m) => m.describe()).toList(),
      equals([
        'Lunch Rush pays 0 coins',
        '+25% targets from city 3',
        '-1 swap (2 total)',
        'shop prices +1 per city',
        'Dinner Rush also carries a minor critic',
        '-1 cook',
        'utensil slots → 4',
      ]),
    );
    expect(const StakeModifier(type: 'future_thing').describe(), equals('future_thing'));
  });

  group('scripted runs replay the JS engine step for step', () {
    final cases = (v['runs'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final label = 'run $i · ${c['seed']} · stake ${c['stake']} · ${c['deckId']} · '
          '${c['policy']}${c['boost'] != null ? ' · boost ${c['boost']}' : ''}';
      test(label, () {
        final want = (c['steps'] as List<dynamic>).cast<Map<String, dynamic>>();
        final got = _playRun(c);
        final n = want.length < got.length ? want.length : got.length;
        for (var s = 0; s < n; s++) {
          _expectSnap(want[s], got[s], '$label · step $s (${want[s]['tag']})');
        }
        expect(got.length, equals(want.length), reason: '$label — the run took a different number of actions');
      });
    }
  });

  test('the Long Route generates identical cities, targets and merged critics', () {
    final cases = (v['endless'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final c in cases) {
      profile = defaultProfile();
      drainUnlockQueue();
      final run = newRun(
        seed: c['seed'] as String,
        stake: c['stake'] as int,
        deckId: c['deckId'] as String,
      );
      drainUnlockQueue();
      final label = 'endless ${c['seed']} · stake ${c['stake']} · ${c['deckId']}';
      for (final w in (c['cities'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final k = w['k'] as int;
        startEndlessCity(run, k);
        final city = run.endlessCityObj!;
        expect(_deepEq(w['endlessBase'], run.endlessBase), isTrue,
            reason: '$label · +$k endlessBase — recorded ${_show(w['endlessBase'])}, got ${run.endlessBase}');
        expect(city.id, equals(w['cityId']), reason: '$label · +$k city id');
        expect(city.name, equals(w['cityName']), reason: '$label · +$k city name');
        expect(_deepEq(w['targets'], city.targets), isTrue,
            reason: '$label · +$k targets — recorded ${_show(w['targets'])}, got ${_show(city.targets)}');
        _expectSnap(
          (w['criticObj'] as Map<String, dynamic>),
          _criticSnap(city.criticObj)!,
          '$label · +$k critic',
        );
        _expectSnap(w['lunch'] as Map<String, dynamic>, _coreSnap(run), '$label · +$k lunch');
        // The finale is the only service where activeCritic reads the city's rolled critic.
        run.serviceIndex = 2;
        startService(run);
        _expectSnap(w['finale'] as Map<String, dynamic>, _coreSnap(run), '$label · +$k finale');
      }
      _expectSnap(c['profile'] as Map<String, dynamic>, _profileSnap(), '$label · profile');
      drainUnlockQueue();
    }
  });

  test('onRunWon awards stake progression, gated utensils and the run_won ladder', () {
    for (final c in (v['runsWon'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      profile = defaultProfile();
      drainUnlockQueue();
      final run = newRun(
        seed: c['seed'] as String,
        stake: c['stake'] as int,
        deckId: c['deckId'] as String,
      );
      drainUnlockQueue();
      for (final id in (c['vendors'] as List<dynamic>).cast<String>()) {
        run.utensils.add(kUtensilById[id]!);
      }
      onRunWon(run);
      final label = 'onRunWon ${c['seed']} · stake ${c['stake']} · ${c['deckId']}';
      expect(drainUnlockQueue(), equals((c['unlocks'] as List<dynamic>).cast<String>()),
          reason: '$label — unlock toasts');
      _expectSnap(c['profile'] as Map<String, dynamic>, _profileSnap(), '$label · profile');
    }
  });

  test('bankService pays out identically across the economy matrix', () {
    // Purse sizes straddle every interest step, including the 25 where the cap of 5 bites.
    // Mutation testing put this here: the scripted runs spend their coins each bazaar and so
    // never reached the cap, which left it free to drift.
    for (final c in (v['banks'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      profile = defaultProfile();
      drainUnlockQueue();
      final stake = c['stake'] as int;
      final coins = c['coins'] as int;
      final run = newRun(seed: 'BANK-$stake-$coins', stake: stake, deckId: 'home');
      if (c['endless'] as bool) startEndlessCity(run, 1);
      drainUnlockQueue();
      run.serviceIndex = c['serviceIndex'] as int;
      run.coins = coins;
      run.cooksLeft = c['cooksLeft'] as int;
      run.svcMaxCards = c['cooksLeft'] as int;
      run.svcSwapsUsed = c['serviceIndex'] as int;
      final bank = bankService(run);
      final label = 'bank stake $stake · ${(c['endless'] as bool) ? 'endless' : 'route'} · '
          'svc ${c['serviceIndex']} · cooksLeft ${c['cooksLeft']} · coins $coins';
      _expectSnap(c['bank'] as Map<String, dynamic>, {
        'base': bank.base,
        'unused': bank.unused,
        'interest': bank.interest,
        'earned': bank.earned,
      }, '$label · payout');
      expect(run.coins, equals(c['coinsAfter']), reason: '$label — purse after banking');
      expect(run.distance, equals(c['distance']), reason: '$label — distance');
      expect(drainUnlockQueue(), equals((c['unlocks'] as List<dynamic>).cast<String>()),
          reason: '$label — unlock toasts');
      final history = run.history
          .map((h) => {'city': h.city, 'svc': h.svc, 'score': h.score, 'target': h.target, 'win': h.win})
          .toList();
      expect(_deepEq(c['history'], history), isTrue,
          reason: '$label — history\n    recorded (JS): ${_show(c['history'])}\n'
              '    replayed (Dart): ${_show(history)}');
      _expectSnap(c['profile'] as Map<String, dynamic>, _profileSnap(), '$label · profile');
    }
  });

  test('the Long Route leaderboard sorts, caps at 10 and breaks exact ties stably', () {
    profile = defaultProfile();
    drainUnlockQueue();
    for (final row in (v['leaderboard'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final run = newRun(seed: row['seed'] as String, stake: 2, deckId: 'home');
      run.distance = row['d'] as int;
      run.totalScore = row['s'] as int;
      recordEndless(run);
      drainUnlockQueue();
      final got = profile.endlessTop10.map((e) => e.toJson()).toList();
      expect(_deepEq(row['top10'], got), isTrue,
          reason: 'after ${row['seed']} (${row['d']}/${row['s']})\n'
              '    recorded (JS): ${_show(row['top10'])}\n    replayed (Dart): ${_show(got)}');
    }
  });

  group('meta-save persistence', () {
    test('loadProfile fills in fields an older save never wrote', () {
      final saved = profileStore;
      final store = MemoryProfileStore()
        // A v1 save from before recipes_discovered / daily / endless_top10 existed, whose
        // unlocks carry only one of the four buckets. Every absent field must come back as
        // its default rather than null — this is the "unlocks are never lost" invariant.
        ..write(jsonEncode({
          'profile_version': 1,
          'unlocks': {'utensils': ['tandoor', 'clay_handi']},
          'achievements_done': ['first_dish'],
          'stake_progress': {'home': 4, 'royal': 2},
          'stats': {'runs': 9},
        }));
      profileStore = store;
      final p = loadProfile();
      expect(p.unlocks['utensils'], equals(['tandoor', 'clay_handi']), reason: 'stored bucket kept');
      expect(p.unlocks['decks'], equals(['home']), reason: 'absent bucket keeps its default');
      expect(p.unlocks['blends'], isEmpty);
      expect(p.unlocks['cardbacks'], isEmpty);
      expect(p.achievementsDone, equals(['first_dish']));
      expect(p.recipesDiscovered, isEmpty, reason: 'field added later must not read as null');
      expect(p.stakeProgress, equals({'home': 4, 'royal': 2}));
      expect(p.stats['runs'], equals(9));
      // `stats` is replaced wholesale, not merged — JS does `Object.assign(d, p)` and so a
      // stat the old save never wrote stays absent. Nothing reads it raw: bumpStat and
      // setBest both coalesce a missing key to 0, so the behaviour is identical either way.
      expect(p.stats.containsKey('wins'), isFalse);
      profile = p;
      bumpStat('wins', 1);
      setBest('best_dish', 500);
      expect(profile.stats['wins'], equals(1), reason: 'a missing stat must count from 0');
      expect(profile.stats['best_dish'], equals(500));
      expect(p.daily.lastPlayed, equals(''));
      expect(p.endlessTop10, isEmpty);
      profileStore = saved;
    });

    test('an unreadable or version-less save falls back to a fresh profile', () {
      final saved = profileStore;
      for (final raw in ['', 'not json at all', '{}', '{"profile_version":0}', '[1,2,3]']) {
        profileStore = MemoryProfileStore()..write(raw);
        expect(jsonEncode(loadProfile().toJson()), equals(v['defaultProfile']),
            reason: 'save ${_show(raw)} should not survive as a partial profile');
      }
      profileStore = saved;
    });

    test('saveProfile round-trips through an injected store', () {
      final saved = profileStore;
      profileStore = MemoryProfileStore();
      profile = defaultProfile();
      unlockThing('utensil', 'tandoor');
      setStakeProgress('royal', 5);
      bumpStat('runs', 3);
      final reloaded = loadProfile();
      expect(reloaded.unlocks['utensils'], equals(['tandoor']));
      expect(reloaded.stakeProgress['royal'], equals(5));
      expect(reloaded.stats['runs'], equals(3));
      profileStore = saved;
      profile = defaultProfile();
    });
  });
}

// Headless balance simulator — the Dart successor to tools/sim.mjs.
//
//   dart run tools/sim                     # win-rate ladder, all 8 stakes
//   dart run tools/sim --stake 3
//   dart run tools/sim --stake 8 -n 2000 --deck royal
//   dart run tools/sim --compare           # ladder side by side with the JS numbers
//
// The bot policy is a deliberate port of tools/sim.mjs's greedy bot — same value table,
// same dig heuristic, same buy order — so the two ladders are comparable. Matching win
// rates across two independent implementations is an end-to-end check on the port that
// complements the per-step trace tests: those prove the engine agrees step by step, this
// proves the whole game still plays the same.
import 'dart:io';

import 'package:game_core/game_core.dart';

/// Crude value heuristic for the shop bot; heat is scarce, so it's weighted high.
/// Mirrors VAL in tools/sim.mjs exactly — changing one without the other invalidates any
/// comparison between the two ladders.
const Map<String, int> _value = {
  'clay_handi': 100, 'emperors_wok': 75, 'ice_box': 80, 'tandoor': 70, 'wok': 70,
  'bamboo_steamer': 85, 'griddle': 78, 'salt_cellar': 60, 'mint_garnish': 62,
  'stock_pot': 55, 'golden_sieve': 90, 'butchers_block': 65, 'iron_tawa': 70,
  'rice_cooker': 58, 'honey_jar': 52, 'big_spoon': 45, 'pressure_cooker': 74,
  'grandmother_ladle': 66, 'street_cart': 20, 'chai_stall': 22,
};
int _uval(String id) => _value[id] ?? 40;

/// All index combinations of size k from n, precomputed for the 8-card hand.
List<List<int>> _combos(int n, int k) {
  final res = <List<int>>[];
  if (k > n) return res;
  final idx = List<int>.generate(k, (i) => i);
  while (true) {
    res.add(List<int>.of(idx));
    var i = k - 1;
    while (i >= 0 && idx[i] == i + n - k) {
      i--;
    }
    if (i < 0) break;
    idx[i]++;
    for (var j = i + 1; j < k; j++) {
      idx[j] = idx[j - 1] + 1;
    }
  }
  return res;
}

final Map<int, List<List<int>>> _cb = {for (var s = 1; s <= 5; s++) s: _combos(8, s)};

({int score, List<int> idxs}) _bestDish(RunState run, int maxCards) {
  final ctx = ctxFor(run);
  var best = (score: -1, idxs: <int>[0]);
  for (var s = 1; s <= maxCards; s++) {
    for (final c in _cb[s] ?? _combos(run.hand.length, s)) {
      if (c.last >= run.hand.length) continue;
      final cards = c.map((i) => run.hand[i]).toList();
      if (dishError(cards, run.critic) != null) continue;
      final r = scoreDish(cards, ctx);
      if (r.score > best.score) best = (score: r.score, idxs: c);
    }
  }
  return best;
}

/// Which cards to throw away: keep the dominant family when going wide, otherwise keep
/// pairs, and dump the lowest ranks.
List<int> _digIdx(RunState run, int maxCards) {
  final fa = <String, int>{};
  final rk = <int, int>{};
  for (final c in run.hand) {
    fa[c.family] = (fa[c.family] ?? 0) + 1;
    rk[c.rank] = (rk[c.rank] ?? 0) + 1;
  }
  final topFam = (fa.keys.toList()..sort((a, b) => fa[b]!.compareTo(fa[a]!))).first;
  final keep = <int>{};
  if (maxCards >= 5 && (fa[topFam] ?? 0) >= 3) {
    for (var i = 0; i < run.hand.length; i++) {
      if (run.hand[i].family == topFam) keep.add(i);
    }
  } else {
    for (var i = 0; i < run.hand.length; i++) {
      if ((rk[run.hand[i].rank] ?? 0) >= 2) keep.add(i);
    }
  }
  final cand = <(int, int)>[];
  for (var i = 0; i < run.hand.length; i++) {
    if (!keep.contains(i)) cand.add((i, run.hand[i].rank));
  }
  cand.sort((a, b) => a.$2.compareTo(b.$2));
  return cand.take(5).map((e) => e.$1).toList();
}

bool _playService(RunState run) {
  final maxCards = run.critic?.maxCards ?? 5;
  while (run.cooksLeft > 0 && run.score < run.target) {
    final best = _bestDish(run, maxCards);
    final pace = ((run.target - run.score) / run.cooksLeft).ceil();
    if (run.swapsLeft > 0 && run.cooksLeft > 1 && best.score < pace) {
      final d = _digIdx(run, maxCards);
      if (d.isNotEmpty) {
        doSwap(run, d..sort());
        continue;
      }
    }
    final out = doCook(run, List<int>.of(best.idxs)..sort());
    if (out.error != null) break;
  }
  return run.score >= run.target;
}

void _shop(RunState run) {
  final offers = rollOffers(run);
  final utensils = offers.where((o) => o.kind == 'utensil').toList()
    ..sort((a, b) => _uval(b.id).compareTo(_uval(a.id)));
  // first pass: fill up to 3 slots with the best-valued utensils
  final cap = run.utensilSlots < 3 ? run.utensilSlots : 3;
  for (final o in utensils) {
    if (run.utensils.length >= cap) break;
    if (run.coins >= o.cost) {
      run.utensils.add(kUtensilById[o.id]!);
      run.coins -= o.cost;
    }
  }
  var bought = 0;
  for (final o in offers) {
    if (o.kind == 'festival' && run.coins >= o.cost && bought < 2) {
      run.kitchenLevel++;
      run.coins -= o.cost;
      bought++;
    }
  }
  for (final o in utensils) {
    if (run.coins < o.cost) continue;
    if (run.utensils.length < run.utensilSlots) {
      run.utensils.add(kUtensilById[o.id]!);
      run.coins -= o.cost;
    } else {
      break;
    }
  }
}

bool _simRun(String seed, int stake, String deckId) {
  final run = newRun(seed: seed, stake: stake, deckId: deckId);
  for (var guard = 0; guard < 40; guard++) {
    if (!_playService(run)) return false;
    final wasBoss = run.serviceIndex == 2;
    bankService(run);
    if (wasBoss) run.kitchenLevel += 3;
    if (isFinalService(run)) return true;
    _shop(run);
    advance(run);
    if (run.status == 'won') return true;
  }
  return false;
}

int _winRate(int stake, int n, String deckId) {
  var wins = 0;
  for (var s = 0; s < n; s++) {
    if (_simRun('L$s', stake, deckId)) wins++;
  }
  return (wins / n * 100).round();
}

/// The JS ladder at 200 runs on the home deck (`node tools/sim.mjs -n 200`), recorded so
/// the Dart ladder can be compared without needing Node installed.
const Map<int, int> _jsLadder200 = {1: 26, 2: 3, 3: 0, 4: 0, 5: 0, 6: 1, 7: 0, 8: 0};

void main(List<String> arguments) {
  String? opt(String flag) {
    final i = arguments.indexOf(flag);
    return i >= 0 && i + 1 < arguments.length ? arguments[i + 1] : null;
  }

  final n = int.tryParse(opt('-n') ?? '') ?? 500;
  final deckId = opt('--deck') ?? 'home';
  final stakeArg = opt('--stake');
  final compare = arguments.contains('--compare');

  // Headless profile: unlock the full pool so the bot represents an experienced build,
  // matching what tools/sim.mjs does.
  profile.unlocks['utensils'] = kUtensils.map((u) => u.id).toList();

  if (stakeArg != null) {
    final st = int.parse(stakeArg);
    final wr = _winRate(st, n, deckId);
    stdout.writeln('Stake $st (${kStakeById[st]!.name}) · deck $deckId · $n runs → $wr% win');
    return;
  }

  stdout.writeln('Stake ladder · deck $deckId · $n runs each:');
  if (compare && deckId == 'home') {
    stdout.writeln('  (dart vs js@200 — the JS ladder is the reference)');
  }
  for (var s = 1; s <= 8; s++) {
    final wr = _winRate(s, n, deckId);
    final stake = kStakeById[s]!;
    final row = '  $s  ${stake.chiliIcon}  ${stake.name.padRight(16)} $wr%';
    if (compare && deckId == 'home') {
      final js = _jsLadder200[s];
      stdout.writeln('$row${js == null ? '' : ' (js $js%)'}');
    } else {
      stdout.writeln(row);
    }
  }
}

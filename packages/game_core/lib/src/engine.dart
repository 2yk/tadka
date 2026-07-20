/// §ENGINE — pattern detection and the exact scoring order of operations.
///
/// Pure functions: no state, no I/O, no Flutter. A faithful port of the web build, which
/// is the behavioural reference; `test/vectors_test.dart` proves equivalence against
/// thousands of cases generated from it.
///
/// Order of operations (build spec §4) — the sequence is normative, because utensils fire
/// left to right and additive-before-multiplicative, so slot order changes the score:
///   1. detect the best pattern; only pattern cards are "scoring" cards
///   2. start from the recipe base, grown by Kitchen level
///   3. apply dish-level palate
///   4. per scoring card, left to right: intensity, prized bonus, per-card palate
///   5. retriggers
///   6. per-dish utensils in slot order
///   7. score = floor(flavor x heat)
library;

import 'catalog.dart';
import 'models.dart';

/// The detected recipe plus the subset of cards that actually score.
class PatternMatch {
  const PatternMatch(this.pattern, this.scoring);

  final String pattern;
  final List<Card> scoring;
}

/// Detects the strongest recipe in [cards], evaluating strongest to weakest.
///
/// Extras played beyond the pattern still trigger "any card" effects but contribute no
/// intensity — that's why [PatternMatch.scoring] is returned separately from the input.
PatternMatch bestPattern(List<Card> cards) {
  final n = cards.length;
  final byRank = <int, int>{};
  final byFam = <String, int>{};
  for (final c in cards) {
    byRank[c.rank] = (byRank[c.rank] ?? 0) + 1;
    byFam[c.family] = (byFam[c.family] ?? 0) + 1;
  }
  final uniq = byRank.keys.toList()..sort();
  final isFlush = n == 5 && byFam.length == 1;
  final isStraight = n == 5 && uniq.length == 5 && (uniq[4] - uniq[0] == 4);
  final oneFamily = byFam.length == 1;

  // ascending, matching JS integer-key iteration order
  List<int> ranksWith(int k) => (byRank.keys.where((r) => byRank[r]! >= k).toList()..sort());

  /// Takes up to [per] cards of each listed rank, in played order.
  List<Card> take(List<int> ranks, int per) {
    final seen = <int, int>{};
    final out = <Card>[];
    for (final c in cards) {
      if (ranks.contains(c.rank)) {
        final t = seen[c.rank] ?? 0;
        if (t < per) {
          out.add(c);
          seen[c.rank] = t + 1;
        }
      }
    }
    return out;
  }

  // Secret recipes first — only reachable via blend manipulation.
  final fives = ranksWith(5);
  if (n == 5 && fives.isNotEmpty && oneFamily) return PatternMatch('perfect_palate', List.of(cards));
  if (n == 5 && fives.isNotEmpty) return PatternMatch('five_kind', List.of(cards));
  final trip0 = ranksWith(3);
  if (n == 5 && oneFamily && trip0.isNotEmpty && ranksWith(2).any((r) => r != trip0.reduce((a, b) => a > b ? a : b))) {
    return PatternMatch('full_family', List.of(cards));
  }

  if (isFlush && isStraight) return PatternMatch('straight_flush', List.of(cards));
  final fours = ranksWith(4);
  if (fours.isNotEmpty) return PatternMatch('four_kind', take([fours.reduce((a, b) => a > b ? a : b)], 4));
  final trips = ranksWith(3);
  if (n == 5 && trips.isNotEmpty) {
    final t = trips.reduce((a, b) => a > b ? a : b);
    if (ranksWith(2).any((r) => r != t)) return PatternMatch('full_house', List.of(cards));
  }
  if (isFlush) return PatternMatch('flush', List.of(cards));
  if (isStraight) return PatternMatch('straight', List.of(cards));
  if (trips.isNotEmpty) return PatternMatch('three_kind', take([trips.reduce((a, b) => a > b ? a : b)], 3));
  final pairs = ranksWith(2);
  if (pairs.length >= 2) {
    final top2 = (pairs.toList()..sort((a, b) => b - a)).take(2).toList();
    return PatternMatch('two_pair', take(top2, 2));
  }
  if (pairs.length == 1) return PatternMatch('pair', take([pairs[0]], 2));

  var hi = cards[0];
  for (final c in cards) {
    if (c.rank > hi.rank) hi = c;
  }
  return PatternMatch('high_card', [hi]);
}

/// What one scoring card adds: intensity, prized bonus, per-card palate, critic debuff.
({double dF, double dH}) cardContribution(Card card, ScoreContext ctx) {
  final debuffed = ctx.critic?.debuff == card.family;
  final intensity = debuffed ? 0 : card.rank;
  var dF = intensity.toDouble();
  var dH = 0.0;
  if (card.prized && !debuffed) dF += kPrizedBonus;
  if (!debuffed && ctx.palate != null) {
    final p = ctx.palate!;
    if (p.perCardFlavorPctFamily == card.family && p.perCardFlavorPct != null) {
      dF += intensity * p.perCardFlavorPct! / 100;
    }
    if (p.perCardHeatFamily == card.family && p.perCardHeatAdd != null) {
      dH += p.perCardHeatAdd!;
    }
  }
  return (dF: dF, dH: dH);
}

/// A utensil slot's effective behaviour after resolving Grandmother's Ladle.
class _Slot {
  const _Slot(this.name, this.condition, this.effect);

  final String name;
  final Map<String, Object?>? condition;
  final Map<String, Object?> effect;
}

/// Resolves slot [i], following Grandmother's Ladle one hop right (never recursive, so two
/// adjacent Ladles can't loop).
_Slot? _resolveSlot(List<Utensil> utensils, int i) {
  if (i >= utensils.length) return null;
  final u = utensils[i];
  if (u.effect['copy_right'] == true) {
    final r = i + 1 < utensils.length ? utensils[i + 1] : null;
    if (r != null && r.effect['copy_right'] != true) {
      return _Slot('${u.name} → ${r.name}', r.condition, r.effect);
    }
    return _Slot(u.name, null, const {});
  }
  return _Slot(u.name, u.condition, u.effect);
}

bool _condMet(Map<String, Object?>? cond, List<Card> played, String pattern, ScoreContext ctx) {
  if (cond == null) return true;
  final allFam = cond['all_cards_family'];
  if (allFam != null && !played.every((x) => x.family == allFam)) return false;
  final containsFam = cond['contains_family'];
  if (containsFam != null && !played.any((x) => x.family == containsFam)) return false;
  if (cond['all_cards_same_family'] == true) {
    final f = played[0].family;
    if (!played.every((x) => x.family == f)) return false;
  }
  final minCards = cond['min_cards'] as int?;
  if (minCards != null && played.length < minCards) return false;
  final numCards = cond['num_cards'] as int?;
  if (numCards != null && played.length != numCards) return false;
  final patternIs = cond['pattern_is'];
  if (patternIs != null && pattern != patternIs) return false;
  final atLeast = cond['pattern_at_least'];
  if (atLeast != null && kPatternOrder.indexOf(pattern) < kPatternOrder.indexOf(atLeast as String)) {
    return false;
  }
  if (cond['is_first_dish'] == true && !ctx.isFirstDish) return false;
  if (cond['is_last_dish'] == true && !ctx.isLastDish) return false;
  return true;
}

/// JS `Math.round(n*10)/10`. Math.round is floor(x + 0.5), which differs from Dart's
/// round-half-away-from-zero on negative halves — matched here so breakdown text agrees.
double _round1(double n) => (n * 10 + 0.5).floorToDouble() / 10;

/// Formats a number the way JS string interpolation does: 3.0 prints as "3", not "3.0".
String _num(num n) {
  if (n is int) return '$n';
  final d = n.toDouble();
  return d == d.truncateToDouble() ? '${d.toInt()}' : '$d';
}

/// THE HEART. Scores one dish; see the library doc for the order of operations.
ScoreResult scoreDish(List<Card> playedCards, ScoreContext ctx) {
  final match = bestPattern(playedCards);
  final pattern = match.pattern;
  final scoring = match.scoring;
  final base = kRecipe[pattern]!;
  final lvl = ctx.kitchenLevel;
  final lb = kLevelBonus[pattern] ?? (0, 0);
  final baseF = base.$1 + (lvl - 1) * lb.$1;
  final baseH = base.$2 + (lvl - 1) * lb.$2;

  var flavor = baseF.toDouble();
  var heat = baseH.toDouble();
  var coins = 0;
  final steps = <ScoreStep>[];
  void log(String t, String cls) => steps.add(ScoreStep(t, cls));

  log('${kGenericNames[pattern]}${lvl > 1 ? ' Lv$lvl' : ''} · base $baseF flavor × $baseH heat', '');

  // dish-level palate (Naples: flushes)
  final p = ctx.palate;
  if (p != null && p.dishFlavorPattern == pattern && p.dishFlavorAdd != null) {
    flavor += p.dishFlavorAdd!;
    log('Palate +${p.dishFlavorAdd} flavor', 'plus');
  }

  // per scoring card, left to right in played order
  for (final card in scoring) {
    final c = cardContribution(card, ctx);
    flavor += c.dF;
    heat += c.dH;
    var d = '${card.display} +${_num(_round1(c.dF))} flavor${c.dH != 0 ? ' +${_num(c.dH)} heat' : ''}';
    if (ctx.critic?.debuff == card.family) {
      d = '${card.display} (${card.family} debuffed → 0)';
    }
    log(d, 'plus');
  }

  // retriggers re-run the highest scoring card only
  if (scoring.isNotEmpty) {
    var hi = scoring[0];
    for (final c in scoring) {
      if (c.rank > hi.rank) hi = c;
    }
    for (var i = 0; i < ctx.utensils.length; i++) {
      final eff = _resolveSlot(ctx.utensils, i);
      if (eff == null || eff.effect['retrigger_highest'] != true) continue;
      // Conditions apply here too. This pass used to skip _condMet entirely, which never
      // mattered because Pressure Cooker is unconditional — but a conditional retrigger
      // would have fired on every dish and its shop text would have been a lie. Verified a
      // strict no-op against every existing vector before the change.
      if (!_condMet(eff.condition, playedCards, pattern, ctx)) continue;
      final c = cardContribution(hi, ctx);
      flavor += c.dF;
      heat += c.dH;
      log('${eff.name}: retrigger ${hi.display} (+${_num(_round1(c.dF))} flavor'
          '${c.dH != 0 ? ' +${_num(c.dH)} heat' : ''})', 'plus');
    }
  }

  // per-dish utensils, left to right in slot order; additive before multiplicative
  for (var i = 0; i < ctx.utensils.length; i++) {
    final eff = _resolveSlot(ctx.utensils, i);
    if (eff == null) continue;
    final e = eff.effect;
    if (e['retrigger_highest'] == true || e['copy_right'] == true) continue;
    if (!_condMet(eff.condition, playedCards, pattern, ctx)) continue;

    final beforeF = flavor;
    final beforeH = heat;
    final flavorAdd = e['flavor_add'] as num?;
    if (flavorAdd != null && flavorAdd != 0) flavor += flavorAdd;
    final heatAdd = e['heat_add'] as num?;
    if (heatAdd != null && heatAdd != 0) heat += heatAdd;
    final flavorPer = e['flavor_per_card'] as num?;
    if (flavorPer != null && flavorPer != 0) flavor += flavorPer * playedCards.length;
    final heatPer = e['heat_per_card'] as num?;
    if (heatPer != null && heatPer != 0) heat += heatPer * playedCards.length;
    final coinAdd = e['coin_add'] as num?;
    if (coinAdd != null && coinAdd != 0) coins += coinAdd.toInt();
    // Multiplicative terms land after every additive one in this slot, matching heat.
    final flavorMult = e['flavor_mult'] as num?;
    if (flavorMult != null && flavorMult != 0) flavor *= flavorMult;
    final heatMult = e['heat_mult'] as num?;
    if (heatMult != null && heatMult != 0) heat *= heatMult;

    final parts = <String>[];
    if (flavorMult != null && flavorMult != 0) {
      parts.add('×${_num(flavorMult)} flavor');
    } else if (flavor != beforeF) {
      parts.add('${flavor > beforeF ? '+' : ''}${_num(_round1(flavor - beforeF))} flavor');
    }
    if (heatMult != null && heatMult != 0) {
      parts.add('×${_num(heatMult)} heat');
    } else if (heat != beforeH) {
      parts.add('+${_num(_round1(heat - beforeH))} heat');
    }
    if (coinAdd != null && coinAdd != 0) parts.add('+${_num(coinAdd)}🪙');
    final isMult = (heatMult != null && heatMult != 0) || (flavorMult != null && flavorMult != 0);
    log('${eff.name}: ${parts.isEmpty ? '—' : parts.join(', ')}', isMult ? 'mult' : 'plus');
  }

  final score = (flavor * heat).floor();
  log('= ${_num(_round1(flavor))} flavor × ${_num(_round1(heat))} heat', '');
  return ScoreResult(
    pattern: pattern,
    scoring: scoring,
    flavor: flavor,
    heat: heat,
    coins: coins,
    score: score,
    steps: steps,
  );
}

/// Validity check gating the COOK button. Returns null when the dish is legal.
String? dishError(List<Card> playedCards, Critic? critic) {
  if (playedCards.isEmpty) return 'Select 1–5 ingredients';
  if (playedCards.length > 5) return 'Max 5 ingredients';
  if (critic != null) {
    final maxCards = critic.maxCards;
    if (maxCards != null && playedCards.length > maxCards) {
      return '${critic.name}: max $maxCards ingredients';
    }
    final minCards = critic.minCards;
    if (minCards != null && playedCards.length < minCards) {
      return '${critic.name}: min $minCards ingredients';
    }
    final req = critic.requireFamily;
    if (req != null && !playedCards.any((c) => c.family == req)) {
      return '${critic.name}: needs a ${req[0].toUpperCase()}${req.substring(1)} ingredient';
    }
  }
  return null;
}

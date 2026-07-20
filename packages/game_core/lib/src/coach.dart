/// The Coach — a brute-force dish solver and an honest bazaar valuer.
///
/// A port of §UI's Coach from the web build (`web/tadka.html` ~1014–1320) with the DOM left
/// behind: this layer returns values, and the app decides how to draw them.
///
/// **The rule that makes the Coach worth having (CLAUDE.md): it drives the live engine.**
/// Every number here comes back from [scoreDish] under the run's own [ctxFor] context —
/// nothing is recomputed, estimated or approximated. A parallel solver that drifts is worse
/// than no Coach at all, because the player would be told a number the game then refuses to
/// pay. `test/coach_test.dart` asserts the equality directly.
///
/// Two consequences of that rule worth knowing before you edit anything:
///
/// **The Coach must not touch the RNG.** [rankOffers] takes the offers `rollOffers` already
/// produced rather than rolling its own — calling `rollOffers` here would advance `run.rng`
/// and silently change every later shuffle and shop roll in the run. Nothing in this file
/// draws from [RunState.rng] or mutates run state; the Coach is a pure read.
///
/// **Offer value is measured in dish score, so coins are undervalued.** [rankOffers] scores
/// benchmark dishes with and without the purchase, which is the only honest way to compare a
/// utensil against a Festival. Coin utensils add no dish score, so they measure as zero and
/// sort last — the web Coach has the same blind spot. They are tagged `economy` and explained
/// in words instead. If coin-to-score conversion ever gets modelled, that is the place.
library;

import 'catalog.dart';
import 'engine.dart';
import 'models.dart';
import 'run.dart';

// ---------------------------------------------------------------------------
// Dish solver
// ---------------------------------------------------------------------------

/// One suggested dish the player could cook right now.
class DishSuggestion {
  const DishSuggestion({
    required this.handIndexes,
    required this.result,
    required this.why,
  });

  /// Indexes into `run.hand`, ascending — pass straight to `doCook`.
  final List<int> handIndexes;

  /// Straight from [scoreDish] under [ctxFor]; never recomputed, so `result.score` is
  /// exactly what cooking these cards will pay.
  final ScoreResult result;

  /// One line of plain-text strategy, derived from [result] and the run context. No markup:
  /// the app owns presentation.
  final String why;
}

/// Every ascending `k`-subset of `0..n-1`, in the web build's `kcombs` order.
List<List<int>> _combinations(int n, int k) {
  final out = <List<int>>[];
  if (k > n || k < 1) return out;
  final idx = List<int>.generate(k, (i) => i);
  while (true) {
    out.add(List<int>.of(idx));
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
  return out;
}

/// A solver candidate before it is dressed up as a [DishSuggestion].
class _Candidate {
  _Candidate(this.indexes, this.cards, this.result);

  final List<int> indexes;
  final List<Card> cards;
  final ScoreResult result;

  /// Discovery order, filled in before the sort. Dart's `List.sort` is not stable but JS's
  /// is, so the final tie-break has to be explicit or the two builds can disagree on the
  /// order of two equal-scoring rows.
  int order = 0;
}

/// The best legal dish per recipe pattern, strongest score first.
///
/// Brute-forces every combination of 1..5 cards in the hand (tightened to the critic's card
/// cap), scores each with the live engine, and keeps only the best-scoring example of each
/// distinct pattern — so the list reads as a ladder of genuinely different options rather
/// than twenty near-identical Pairs. Ties go to the dish that spends fewer cards.
///
/// Obeys the active critic: anything [dishError] rejects is skipped, so a suggestion is
/// always cookable as-is. Returns an empty list only for an empty hand or a critic whose
/// demand the hand cannot satisfy at all.
///
/// Cost is `sum(C(n, 1..5))` scoring calls — 218 for a full 8-card hand. See the timing
/// test in `test/coach_test.dart`.
List<DishSuggestion> suggestDishes(RunState run, {int limit = 6}) {
  final hand = run.hand;
  final n = hand.length;
  if (n == 0 || limit <= 0) return const <DishSuggestion>[];

  final ctx = ctxFor(run);
  final maxCards = run.critic?.maxCards ?? 5;
  final widest = maxCards < n ? maxCards : n;

  // Insertion-ordered by construction, which is the tie-break of last resort below.
  final best = <String, _Candidate>{};
  for (var size = 1; size <= widest; size++) {
    for (final combo in _combinations(n, size)) {
      final cards = [for (final i in combo) hand[i]];
      if (dishError(cards, run.critic) != null) continue;
      final res = scoreDish(cards, ctx);
      final cur = best[res.pattern];
      if (cur == null ||
          res.score > cur.result.score ||
          (res.score == cur.result.score && combo.length < cur.indexes.length)) {
        best[res.pattern] = _Candidate(combo, cards, res);
      }
    }
  }

  final ordered = best.values.toList();
  for (var i = 0; i < ordered.length; i++) {
    ordered[i].order = i;
  }
  ordered.sort((a, b) {
    final byScore = b.result.score - a.result.score;
    if (byScore != 0) return byScore;
    final byWidth = a.indexes.length - b.indexes.length;
    if (byWidth != 0) return byWidth;
    return a.order - b.order;
  });

  final take = ordered.length < limit ? ordered.length : limit;
  return [
    for (var i = 0; i < take; i++)
      DishSuggestion(
        handIndexes: ordered[i].indexes,
        result: ordered[i].result,
        why: _dishWhy(ordered[i].result, ctx),
      ),
  ];
}

/// Recipes whose base is high enough that reaching one *is* the play. Web `BIG_PATTERNS`.
const List<String> _kBigPatterns = [
  'flush', 'straight', 'full_house', 'four_kind',
  'straight_flush', 'five_kind', 'full_family', 'perfect_palate',
];

/// JS `round1` + JS string interpolation: `Math.round(n*10)/10`, and `3.0` prints as `3`.
String _num1(double n) {
  final r = (n * 10 + 0.5).floorToDouble() / 10;
  return r == r.truncateToDouble() ? '${r.toInt()}' : '$r';
}

/// True when any utensil in [ctx] gates on [key] *and* this dish meets that gate — so the
/// timing note below can only ever describe something that actually fired.
bool _timingFired(ScoreContext ctx, String key, bool active) =>
    active && ctx.utensils.any((u) => u.condition?[key] == true);

/// The strategic one-liner: names the recipe, then the single biggest thing that moved the
/// number.
///
/// Every clause is read off [res] or [ctx] — the step list the engine itself produced, the
/// palate it applied, the cards it counted as scoring. Nothing is asserted that the engine
/// did not do, which is what stops the Coach from teaching the player a rule the game does
/// not have. Priority is the web build's, widened with the palate, prized and retrigger
/// cases: a heat multiplier scales the whole flavour total, so it always dominates.
String _dishWhy(ScoreResult res, ScoreContext ctx) {
  final name = kGenericNames[res.pattern] ?? res.pattern;
  final totals = '${_num1(res.flavor)} flavor × ${_num1(res.heat)} heat';

  final mults = res.steps.where((s) => s.cls == 'mult').toList();
  if (mults.isNotEmpty) {
    final who = mults.map((s) => s.text.split(':').first).join(' + ');
    var timing = '';
    if (_timingFired(ctx, 'is_last_dish', ctx.isLastDish)) {
      timing = ' This spends your last cook, which is the only time it fires.';
    } else if (_timingFired(ctx, 'is_first_dish', ctx.isFirstDish)) {
      timing = ' It only fires on a service\'s first dish, and this is it.';
    }
    return '$name — $who multiplies heat, and heat scales your whole flavor total, so one '
        'big ×heat beats piling on flavor ($totals).$timing';
  }

  final palate = ctx.palate;
  if (palate != null &&
      palate.dishFlavorPattern == res.pattern &&
      palate.dishFlavorAdd != null) {
    return '$name — the local palate pays +${palate.dishFlavorAdd} flavor for exactly this '
        'recipe, so it is worth more here than in any other city ($totals).';
  }

  if (_kBigPatterns.contains(res.pattern)) {
    return '$name — reaching it is the win: the big recipes start from a far higher base '
        'than singles and pairs ($totals).';
  }

  final prized = res.scoring.where((c) => c.prized).toList();
  if (prized.isNotEmpty) {
    return '$name — ${prized.first.display} is prized, worth +$kPrizedBonus flavor on top of '
        'its intensity, so keep it in the dish ($totals).';
  }

  if (palate != null && ctx.critic?.debuff != palate.perCardFlavorPctFamily) {
    final fam = palate.perCardFlavorPctFamily;
    final pct = palate.perCardFlavorPct;
    if (fam != null && pct != null && res.scoring.any((c) => c.family == fam)) {
      return '$name — the local palate turns every scoring $fam ingredient into +$pct% of '
          'its intensity as bonus flavor, so lean $fam while you are here ($totals).';
    }
  }
  if (palate != null && ctx.critic?.debuff != palate.perCardHeatFamily) {
    final fam = palate.perCardHeatFamily;
    final add = palate.perCardHeatAdd;
    if (fam != null && add != null && res.scoring.any((c) => c.family == fam)) {
      return '$name — every scoring $fam ingredient adds +$add heat from the local palate, '
          'and heat multiplies the whole dish ($totals).';
    }
  }

  if (ctx.utensils.any((u) => u.effect['retrigger_highest'] == true)) {
    return '$name — your retrigger scores the highest-intensity ingredient twice, so the '
        'single biggest card in the dish is worth more than the rest ($totals).';
  }

  if (res.heat >= 6) {
    return '$name — $totals. Heat is doing real work here; one more heat source is worth '
        'more than one more point of flavor.';
  }

  return '$name — a small base ($totals). Swap toward matching ranks (Pair → Three → Four '
      'of a Kind), one shared family (Flush), or a heat source to multiply up.';
}

// ---------------------------------------------------------------------------
// Bazaar valuer
// ---------------------------------------------------------------------------

/// What one bazaar offer is actually worth to THIS run.
class OfferValuation {
  const OfferValuation({
    required this.offer,
    required this.marginalValue,
    required this.why,
    required this.category,
  });

  final Offer offer;

  /// Added dish score across the dishes estimated to remain in the run: the best per-dish
  /// delta measured on the benchmark panel, times [_estimatedDishesLeft]. Permanents are
  /// therefore valued over their whole remaining life, which is what lets them be compared
  /// fairly against a one-shot blend. Zero for anything that adds no dish score — see the
  /// library doc on coin utensils.
  final double marginalValue;

  /// Plain-text reasoning, including the measured before → after on the benchmark dish that
  /// showed the offer at its best.
  final String why;

  /// `economy` | `combo` | `scaling` | `situational` | `solid`.
  final String category;
}

/// Flat rank weight for a one-shot blend. Blends change the *cards*, not the scoring rules,
/// so there is no dish to re-score them on; the web build uses this same constant to slot
/// them into the middle of the ladder rather than pretend to a measurement.
const double _kBlendValue = 55;

/// JS `Math.round` — `floor(x + 0.5)`, not Dart's round-half-away-from-zero.
int _jsRound(double n) => (n + 0.5).floor();

/// Roughly how many dishes the run has left, at ~2.5 dishes per remaining service.
///
/// This is the multiplier that makes a permanent comparable to a consumable, and the reason
/// the Coach tells you to buy scaling *early*: the same utensil is worth eight times more in
/// Kochi than on Naples' last service.
int _estimatedDishesLeft(RunState run) {
  if (run.endless) return 8;
  final done = run.cityIndex * 3 + run.serviceIndex + 1;
  final est = _jsRound((9 - done) * 2.5);
  return est < 1 ? 1 : est;
}

/// One benchmark dish and the label used when quoting it back to the player.
class _Bench {
  const _Bench(this.label, this.cards);

  final String label;
  final List<Card> cards;
}

/// First/last-dish variants, so `is_first_dish` (Ice Box) and `is_last_dish` (Clay Handi)
/// utensils are measured at their real best case instead of reading as dead.
class _Variant {
  const _Variant(this.first, this.last, this.tag);

  final bool first;
  final bool last;

  /// Prefix for the quoted example, e.g. `on your last dish, `.
  final String tag;
}

const List<_Variant> _kVariants = [
  _Variant(false, false, ''),
  _Variant(true, false, 'on your first dish, '),
  _Variant(false, true, 'on your last dish, '),
];

/// The run's own card for [family] at [rank], falling back to a synthetic one if the deck
/// trimmed it away. Only family, rank and prized reach the scoring maths — id and display
/// just make the breakdown readable — but pulling real pantry cards keeps the panel honest
/// about what this deck can actually draw.
Card _pantryCard(List<Card> pantry, String family, int rank) {
  for (final c in pantry) {
    if (c.family == family && c.rank == rank && !c.prized) return c;
  }
  return Card(id: 'bench_${family}_$rank', family: family, rank: rank, display: '$rank $family');
}

/// Representative dishes spanning the utensil condition space, built from the run's pantry.
///
/// Ranks are repeated where a recipe needs them (three 9s), which no single pantry can deal —
/// these are yardsticks, not hands. The set is the web build's: it deliberately covers a
/// one-family dish, a big recipe, a wide five-card dish, a three-card dish and a two-card
/// dish, so every M0 condition key fires on at least one of them.
List<_Bench> _benchHands(RunState run) {
  final pantry = buildPantry(run.deckCfg);
  Card c(String family, int rank) => _pantryCard(pantry, family, rank);
  return [
    // Non-consecutive on purpose: a plain Flush, not a Straight Flush.
    _Bench('a 5-Spicy Flush', [c('spicy', 4), c('spicy', 6), c('spicy', 8), c('spicy', 9), c('spicy', 10)]),
    _Bench('a Full House (three 9s, two 6s)', [c('umami', 9), c('umami', 9), c('umami', 9), c('salty', 6), c('salty', 6)]),
    _Bench('a wide 5-card spread', [c('sweet', 10), c('sour', 8), c('salty', 7), c('umami', 6), c('spicy', 5)]),
    _Bench('a Three of a Kind (three 8s)', [c('spicy', 8), c('sweet', 8), c('salty', 8)]),
    _Bench('a Pair (two 9s)', [c('spicy', 9), c('sweet', 9)]),
  ];
}

/// The city the bazaar sits in — the one just played, since `advance` has not run yet.
///
/// Clamped past the end of the route: the Coach is an advisor and must never be the thing
/// that throws on a screen the player can still reach.
City _bazaarCity(RunState run) =>
    (run.endless || run.cityIndex <= 2) ? cityOf(run) : kCities[2];

/// The best per-dish delta an offer achieves anywhere on the benchmark panel.
class _Impact {
  const _Impact({
    required this.delta,
    required this.before,
    required this.after,
    required this.bench,
    required this.when,
  });

  final int delta;
  final int before;
  final int after;
  final String bench;
  final String when;
}

ScoreContext _benchCtx(RunState run, List<Utensil> utensils, int level, _Variant v) => ScoreContext(
  palate: kPalates[_bazaarCity(run).id],
  utensils: utensils,
  // Critic-free on purpose: an offer's value should not swing on whichever boss happens to
  // be next, and the bazaar's own next-service critic is not rolled yet.
  kitchenLevel: level,
  isFirstDish: v.first,
  isLastDish: v.last,
);

/// Scores the whole panel with and without [o], keeping the variant that flatters it most.
///
/// Best case rather than average, deliberately: a conditional utensil is bought *for* the
/// dish it wants, so averaging it against dishes it was never meant to fire on would rate
/// every specialist as junk. Returns null only for an offer that is neither a utensil nor a
/// Festival, or a utensil id missing from the catalog.
_Impact? _offerImpact(RunState run, Offer o, List<_Bench> benches) {
  final utensil = o.kind == 'utensil' ? kUtensilById[o.id] : null;
  if (o.kind == 'utensil' && utensil == null) return null;
  if (o.kind != 'utensil' && o.kind != 'festival') return null;

  _Impact? best;
  for (final b in benches) {
    for (final v in _kVariants) {
      final before = scoreDish(b.cards, _benchCtx(run, run.utensils, run.kitchenLevel, v)).score;
      // A new utensil lands in the next free slot, i.e. at the end — which is also why a
      // Grandmother's Ladle already in the build can start copying it.
      final after = utensil != null
          ? scoreDish(b.cards, _benchCtx(run, [...run.utensils, utensil], run.kitchenLevel, v)).score
          : scoreDish(b.cards, _benchCtx(run, run.utensils, run.kitchenLevel + 1, v)).score;
      final delta = after - before;
      if (best == null || delta > best.delta) {
        best = _Impact(delta: delta, before: before, after: after, bench: b.label, when: v.tag);
      }
    }
  }
  return best;
}

/// What each blend is for. The engine cannot measure these — they rewrite cards rather than
/// scoring rules — so this is authored copy, ported from the web build's `BLEND_COACH`.
const Map<String, String> _kBlendWhy = {
  'chili_oil': 'Turns off-family cards Spicy — completes a Flush, or feeds Spicy synergies '
      'like the Tandoor. e.g. 4 Spicy + 1 stray, convert the stray, and a High Card (base 5) '
      'becomes a Flush (base 35).',
  'sea_salt': 'Same as Chili Oil but Salty — a Salty Flush, or a salt-loving build. Bridges '
      'two families into the one Flush you were a card short of.',
  'fermentation': '+3 intensity on the card you pick: more flavor from it, and it can reach '
      'the rank that finishes a Straight. A 4 becomes a 7.',
  'sharpen': 'Sets a card to intensity 10 — maximum per-card flavor, or forge a pair or trip '
      'with the 10s you already hold.',
  'sun_dry': 'Duplicates a card. Extra copies build toward Four and Five of a Kind and widen '
      'the dish — copy a 9 and four 9s become five.',
  'mise': 'Draw 2 extra ingredients: pure card advantage, and a free dig for the fifth Flush '
      'card without spending a swap.',
};

/// A valuation before the sort, carrying its original position for a stable tie-break.
class _Ranked {
  const _Ranked(this.valuation, this.index);

  final OfferValuation valuation;
  final int index;
}

/// Ranks [offers] by real marginal value, best first — the top entry is the best buy.
///
/// Takes the offers `rollOffers` already produced rather than rolling its own; see the
/// library doc on why the Coach must not touch the RNG.
///
/// Permanents are measured, not guessed: [_offerImpact] re-scores the benchmark panel with
/// and without the purchase and the delta is multiplied out over [_estimatedDishesLeft], so
/// a Festival bought in Kochi correctly beats the same Festival bought in Naples. One-shot
/// blends take a flat weight, since there is no dish to measure them on.
List<OfferValuation> rankOffers(RunState run, List<Offer> offers) {
  if (offers.isEmpty) return const <OfferValuation>[];
  final benches = _benchHands(run);
  final left = _estimatedDishesLeft(run);
  final rows = <_Ranked>[];

  for (var i = 0; i < offers.length; i++) {
    final o = offers[i];
    final impact = _offerImpact(run, o, benches);
    final perDish = (impact != null && impact.delta > 0) ? impact.delta : 0;
    final example = impact == null
        ? ''
        : ' e.g. ${impact.when}on ${impact.bench}: ${impact.before} → ${impact.after}.';

    final String category;
    final double value;
    final String why;

    if (o.kind == 'festival') {
      category = 'scaling';
      value = (perDish * left).toDouble();
      final lvl = run.kitchenLevel;
      why = 'Levels every recipe\'s base flavor and heat (Kitchen Lv $lvl → ${lvl + 1}). This '
          'is the run\'s scaling engine: worth about $perDish per dish now, on the ~$left '
          'dishes you have left, and the next Festival compounds on top of it.$example';
    } else if (o.kind == 'blend') {
      // One-shot, and its value is entirely in the hand it is played on — the honest label
      // is situational even when it is the correct buy.
      category = 'situational';
      value = _kBlendValue;
      why = _kBlendWhy[o.id] ?? o.desc;
    } else {
      final u = kUtensilById[o.id];
      final effect = u?.effect ?? const <String, Object?>{};
      final text = u?.text ?? o.desc;
      final coin = effect['coin_add'];
      if (coin != null) {
        category = 'economy';
        value = 0;
        why = '$text. Pays coins, not dish score, so it measures as zero here — but coins buy '
            'Festivals, which are the real scaling engine. Strong bought early, near-dead late.';
      } else if (effect['copy_right'] == true) {
        category = 'combo';
        value = 0;
        why = '$text. Worth nothing on its own — it needs a strong utensil to its right, and '
            'a purchase lands in the last slot. Beside a Clay Handi it is a second ×3 heat.';
      } else if (perDish > 0) {
        category = 'solid';
        value = (perDish * left).toDouble();
        why = '$text. Measured at +$perDish per dish at its best, about '
            '${perDish * left} across the ~$left dishes you have left.$example';
      } else {
        category = 'situational';
        value = 0;
        why = '$text. No gain on the benchmark dishes — its condition is not met on any of '
            'them. It pays off once you deliberately build the dish it asks for.';
      }
    }

    rows.add(_Ranked(
      OfferValuation(offer: o, marginalValue: value, why: why, category: category),
      i,
    ));
  }

  rows.sort((a, b) {
    final byValue = b.valuation.marginalValue.compareTo(a.valuation.marginalValue);
    // Explicit, because Dart's sort is unstable where JS's is: without this the ladder could
    // reshuffle between builds on equal-value offers.
    return byValue != 0 ? byValue : a.index - b.index;
  });
  return [for (final r in rows) r.valuation];
}

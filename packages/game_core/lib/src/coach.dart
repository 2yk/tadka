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

import 'blends.dart';
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

/// Which track(s) a `mult` step multiplied, read off the step the engine itself logged.
///
/// `scoreDish` writes a slot's parts as `'Name: ×2 flavor, +3 heat'`, tags the line `mult`
/// when either multiplier fired, and no utensil name contains a colon — so splitting on the
/// first colon and looking for `×` inside each part says exactly which axis moved. This
/// matters because the v1.0 pass added nine `flavor_mult` utensils to a catalog that had only
/// ever multiplied heat, and the Coach's one-liner used to tell a player holding a Mole Olla
/// that it "multiplies heat". A Coach that misnames the axis is teaching the wrong build.
Set<String> _multAxes(ScoreStep s) {
  final at = s.text.indexOf(':');
  final tail = at < 0 ? s.text : s.text.substring(at + 1);
  final axes = <String>{};
  for (final part in tail.split(',')) {
    if (!part.contains('×')) continue;
    if (part.contains('flavor')) axes.add('flavor');
    if (part.contains('heat')) axes.add('heat');
  }
  return axes;
}

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
    final axes = <String>{for (final s in mults) ..._multAxes(s)};
    var timing = '';
    if (_timingFired(ctx, 'is_last_dish', ctx.isLastDish)) {
      timing = ' This spends your last cook, which is the only time it fires.';
    } else if (_timingFired(ctx, 'is_first_dish', ctx.isFirstDish)) {
      timing = ' It only fires on a service\'s first dish, and this is it.';
    }
    final String how;
    if (axes.length > 1) {
      how = 'multiplies both tracks, and the two compound — a ×flavor and a ×heat on the '
          'same dish is the largest single jump in the game';
    } else if (axes.contains('flavor')) {
      how = 'multiplies flavor, and it lands after every flat bonus in its slot, so the flavor '
          'you stacked to its left is what gets doubled';
    } else {
      how = 'multiplies heat, and heat scales your whole flavor total, so one big ×heat beats '
          'piling on flavor';
    }
    return '$name — $who $how ($totals).$timing';
  }

  final palate = ctx.palate;
  if (palate != null &&
      palate.dishFlavorPattern == res.pattern &&
      palate.dishFlavorAdd != null) {
    return '$name — the local palate pays +${palate.dishFlavorAdd} flavor for exactly this '
        'recipe, so it is worth more here than in any other city ($totals).';
  }

  // The critic, when it is the thing distorting the number. A debuffed card contributes 0
  // intensity AND loses its palate bonus, so a dish that looks strong scores like a weak one
  // and the player has no way to see why from the total alone. Read off `res.scoring`, so this
  // can only claim a card the engine actually zeroed.
  final critic = ctx.critic;
  final debuff = critic?.debuff;
  if (critic != null && debuff != null) {
    final dead = res.scoring.where((c) => c.family == debuff).toList();
    if (dead.isNotEmpty) {
      final who = dead.length == 1 ? dead.first.display : '${dead.length} of these ingredients';
      return '$name — ${critic.name} zeroes $debuff, so $who adds no intensity and no palate '
          'bonus here. Build the dish out of the other families ($totals).';
    }
  }

  // Per-card palates rank above the generic big-recipe line: "lean Sour while you are here" is
  // a decision the player can act on, where "big recipes score more" is true of every city.
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

  if (_kBigPatterns.contains(res.pattern)) {
    return '$name — reaching it is the win: the big recipes start from a far higher base '
        'than singles and pairs ($totals).';
  }

  final prized = res.scoring.where((c) => c.prized).toList();
  if (prized.isNotEmpty) {
    return '$name — ${prized.first.display} is prized, worth +$kPrizedBonus flavor on top of '
        'its intensity, so keep it in the dish ($totals).';
  }

  // A card floor or a required family is the other way a critic decides the dish. Named only
  // when this dish is actually sitting on the constraint, so it never reads as boilerplate.
  if (critic != null) {
    final need = critic.requireFamily;
    if (need != null) {
      return '$name — ${critic.name} demands a $need ingredient in every dish, so one slot is '
          'spoken for; spend the other four on the recipe ($totals).';
    }
    final floor = critic.minCards;
    if (floor != null && res.scoring.length <= floor) {
      return '$name — ${critic.name} makes you play at least $floor ingredients, so the extras '
          'ride along without adding intensity ($totals).';
    }
    final cap = critic.maxCards;
    if (cap != null && res.scoring.length >= cap) {
      return '$name — ${critic.name} caps you at $cap ingredients, which is why nothing wider '
          'than this is on the list ($totals).';
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
// Blend solver
// ---------------------------------------------------------------------------

/// One blend the player is holding, and the best play the Coach found for it in this hand.
///
/// Blends are the least discoverable system in the game — they edit cards instead of scoring
/// them, they are the only route to the three secret recipes, and nothing on the service
/// screen says what one would do until you spend it. This is the answer to "what happens if I
/// tap this", measured rather than described.
class BlendSuggestion {
  const BlendSuggestion({
    required this.blendIndex,
    required this.blend,
    required this.handIndexes,
    required this.result,
    required this.baseline,
    required this.why,
  });

  /// Index into `run.blends` — pass straight to `applyBlend`.
  final int blendIndex;
  final Blend blend;

  /// The cards to tap, in tap order: for a two-card verb the first is the source. Empty for a
  /// blend that takes no targets, and empty when [result] is null.
  final List<int> handIndexes;

  /// The best dish reachable after playing the blend on [handIndexes], scored by [scoreDish]
  /// on the hand [applyBlend] itself produced. Null when no play the Coach tried beats simply
  /// cooking the hand as it stands.
  final ScoreResult? result;

  /// The best dish available right now, without spending the blend.
  final int baseline;

  /// Added dish score. Zero when [result] is null.
  int get gain => result == null ? 0 : result!.score - baseline;

  /// One plain-text line. When the blend helps, this names the cards to tap and quotes the
  /// real before → after; when it does not, it says what the verb is for instead.
  final String why;
}

/// How many candidate plays the Coach will honestly score per blend.
///
/// The search is bounded, not exhaustive: a two-card verb over an eight-card hand has 56
/// ordered plays and each one costs a fresh dish search, which would put the panel past a
/// frame. Candidates are deduplicated by the hand they produce, ordered by [_handPromise] so
/// the most likely plays are the ones that get measured, and then capped here. A bound can
/// only make the advice *conservative*: every number reported still comes from [scoreDish] on
/// a hand [applyBlend] really built, so the Coach may miss a better play but can never quote
/// one that is not there. `test/coach_test.dart` holds the frame-budget check.
const int kMaxBlendPlays = 12;

/// Dishes worth checking after a blend, given it changed the cards at [must].
///
/// Every subset that avoids [must] scores exactly what it scored before the blend, so it is
/// already covered by the baseline — enumerating only the subsets that contain all of [must]
/// is both cheaper and sufficient. It is also the play the player means: you spend a blend on
/// the cards you intend to cook.
///
/// When the blend touched more cards than a dish can hold — Cold Smoke rewrites the whole hand
/// — the constraint is dropped and everything is searched, which is a superset and so still
/// exact, just slower. Those blends have one candidate play each, so it costs nothing that
/// matters.
ScoreResult? _bestDishWith(
  List<Card> hand,
  ScoreContext ctx,
  Critic? critic,
  List<int> changed,
) {
  final n = hand.length;
  final maxCards = critic?.maxCards ?? 5;
  final widest = maxCards < n ? maxCards : n;
  final must = changed.length > widest ? const <int>[] : changed;
  final rest = [for (var i = 0; i < n; i++) if (!must.contains(i)) i];

  ScoreResult? best;
  void consider(List<int> idxs) {
    final cards = [for (final i in idxs) hand[i]];
    if (dishError(cards, critic) != null) return;
    final res = scoreDish(cards, ctx);
    if (best == null || res.score > best!.score) best = res;
  }

  if (must.isNotEmpty) consider(must);
  for (var extra = 1; extra <= widest - must.length; extra++) {
    for (final combo in _combinations(rest.length, extra)) {
      consider([...must, for (final j in combo) rest[j]]..sort());
    }
  }
  return best;
}

/// The plays worth trying for [blend] over a hand of [n] cards, before deduplication.
///
/// Derived from the blend DSL, never from its id: `select` says how many cards it takes, and
/// [blendReadsSource] says whether the first tap is a source (in which case order matters and
/// a single card is not a legal play at all).
List<List<int>> _blendPlays(int n, Blend blend) {
  if (blend.select <= 0) return const [<int>[]];
  final singles = [for (var i = 0; i < n; i++) [i]];
  if (blend.select == 1) return singles;
  if (blendReadsSource(blend)) {
    return [
      for (var s = 0; s < n; s++)
        for (var t = 0; t < n; t++)
          if (s != t) [s, t],
    ];
  }
  // "Up to 2": one card is a legal, sometimes better, play than two.
  return [
    ...singles,
    for (var a = 0; a < n; a++)
      for (var b = a + 1; b < n; b++) [a, b],
  ];
}

/// A card's identity for the purposes of scoring — everything [scoreDish] can see.
String _cardKey(Card c) => '${c.family}:${c.rank}:${c.prized}';

/// Plays `run.blends[blendIndex]` on [sel] against a scratch copy of the run's card state.
///
/// [applyBlend] needs a [RunState], and it only ever touches `hand`, `deck` and `blends` — no
/// RNG, no score, no profile. So the honest way to answer "what would this blend do" is to let
/// the real interpreter do it to copies of those three lists and put the originals back, which
/// is what this does: the run object is the same object on the way out, holding the same list
/// instances with the same contents. Re-implementing the blend DSL here instead would be
/// exactly the parallel implementation the Coach exists to avoid.
///
/// Returns the hand the blend produced, or null if it refused the play.
List<Card>? _handAfterBlend(RunState run, int blendIndex, List<int> sel) {
  final hand = run.hand;
  final deck = run.deck;
  final blends = run.blends;
  run.hand = List<Card>.of(hand);
  run.deck = List<Card>.of(deck);
  run.blends = List<Blend>.of(blends);
  try {
    final out = applyBlend(run, blendIndex, sel);
    return out.error != null ? null : run.hand;
  } finally {
    run.hand = hand;
    run.deck = deck;
    run.blends = blends;
  }
}

/// Which cards in the produced hand are ones the player did not already have.
///
/// A multiset difference, not a positional one, and that is load-bearing: `merge` and
/// `discard_draw` *remove* cards, which shifts every position after them, so comparing slot by
/// slot would report six untouched cards as changed and the constraint in [_bestDishWith]
/// would collapse. Matching by what a card *is* — everything [scoreDish] can see — leaves
/// exactly the rewritten, merged, duplicated and drawn cards.
List<int> _newCardPositions(List<Card> before, List<Card> after) {
  final pool = <String, int>{};
  for (final c in before) {
    final k = _cardKey(c);
    pool[k] = (pool[k] ?? 0) + 1;
  }
  final out = <int>[];
  for (var i = 0; i < after.length; i++) {
    final k = _cardKey(after[i]);
    final have = pool[k] ?? 0;
    if (have > 0) {
      pool[k] = have - 1;
    } else {
      out.add(i);
    }
  }
  return out;
}

/// A cheap, order-only guess at how good a hand is, used to decide which candidate plays are
/// worth a real dish search when there are more of them than [kMaxBlendPlays].
///
/// It claims nothing and is never shown: the winning play is re-measured by [scoreDish] either
/// way. It just puts the plays that build toward a recipe first — most copies of one intensity
/// (Pair through Five of a Kind), then most cards of one family (Flush), then raw intensity.
int _handPromise(List<Card> hand) {
  final byRank = <int, int>{};
  final byFam = <String, int>{};
  for (final c in hand) {
    byRank[c.rank] = (byRank[c.rank] ?? 0) + 1;
    byFam[c.family] = (byFam[c.family] ?? 0) + 1;
  }
  var ranks = 0;
  for (final v in byRank.values) {
    if (v > ranks) ranks = v;
  }
  var fams = 0;
  for (final v in byFam.values) {
    if (v > fams) fams = v;
  }
  final top = hand.map((c) => c.rank).toList()..sort((a, b) => b - a);
  var intensity = 0;
  for (var i = 0; i < top.length && i < 5; i++) {
    intensity += top[i];
  }
  return ranks * 1000 + fams * 100 + intensity;
}

/// What each blend is for, when the Coach cannot show it doing something better right now.
/// Authored copy, ported from the web build's `BLEND_COACH` — the engine cannot measure a
/// verb, only a play.
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
  // --- the expansion. Same job: say what the verb is FOR, not what it does. ---------------
  'brine': 'Chili Oil in Sour — the bridge card for a Sour Flush, and Sour is the family '
      'Kochi and Lima pay a flavor percentage on.',
  'jaggery': 'Chili Oil in Sweet. Worth knowing which city you are in: Marrakech pays heat '
      'for Sweet, and the Traditionalist zeroes it out entirely.',
  'koji': 'Chili Oil in Umami — a Tokyo palate turns every converted card into +2 heat.',
  'blanch': '-2 intensity. Sounds backwards, and it is the only way to complete a Straight '
      'downward: holding 4-5-6-7 and a 10, blanching the 10 to an 8 does nothing, but on '
      '5-6-7-8 and a 10 it finishes the run of five.',
  'invert': 'Flips intensity end for end — a 2 becomes a 9. The rescue for a hand of low '
      'cards, and the cheapest way to force a pair of 9s out of a 2 and a 9.',
  'cold_smoke': '+1 to every ingredient you hold, no selection needed. Small per card, but it '
      'is the whole hand: on five scoring cards that is +5 flavor before any multiplier.',
  'julienne': 'Copies the first selected card\'s intensity onto the second. Four 10s and a '
      'stray becomes five of a rank — a secret recipe from a hand that looked done.',
  'infusion': 'Copies the first selected card\'s family onto the second, so you are not stuck '
      'converting to whichever family the blend names. Any family, if you hold one.',
  'levain': 'Family AND intensity, copied onto the second card: a true twin. The one blend '
      'that fixes a stray which is wrong in both directions at once.',
  'reduction': 'Boils two cards into one, combined intensity capped at 10. You lose a body, '
      'so it is for the hand that is one big card short, never for one that is short of cards.',
  'conserva': 'Sun-Dry twice over. Two copies is the difference between three of a rank and '
      'five, which is the jump from base 30 to base 120.',
  'varak': 'Gilds a card prized: +25 flavor on top of its intensity, which is more than most '
      'common utensils add for the same coins. Put it on a card you will keep cooking.',
  'winnow': 'Discard up to 2 and draw that many — a swap that costs no swap. Best when the '
      'hand is close and two cards are dead weight.',
  'forage': 'Digs the pantry for the next ingredient sharing the selected card\'s family. The '
      'only targeted draw in the game: it is how you find the fifth Flush card on purpose.',
};

/// What one blend in the rack would do for the hand on screen — one entry per held blend,
/// biggest gain first, ties keeping rack order.
///
/// The whole list comes from the live engine: [applyBlend] builds the hand, [scoreDish] scores
/// the dish, [dishError] keeps it legal under the active critic. Nothing here estimates.
///
/// Never touches `run.rng`, never mutates run state that outlives the call, and never writes
/// the profile — same contract as [suggestDishes]. See [_handAfterBlend].
List<BlendSuggestion> suggestBlends(RunState run) {
  if (run.blends.isEmpty || run.hand.isEmpty) return const <BlendSuggestion>[];
  final ctx = ctxFor(run);
  final baseline = _bestDishWith(run.hand, ctx, run.critic, const [])?.score ?? 0;

  final rows = <BlendSuggestion>[];
  for (var i = 0; i < run.blends.length; i++) {
    final blend = run.blends[i];
    final before = run.hand;

    // Build every distinct hand this blend can produce first — applying one is a few list
    // copies, where measuring one is a whole dish search — then measure the most promising
    // [kMaxBlendPlays] of them.
    final seen = <String>{};
    final shortlist =
        <(List<int> play, List<Card> hand, List<int> changed, int promise, int order)>[];
    for (final play in _blendPlays(before.length, blend)) {
      final after = _handAfterBlend(run, i, play);
      if (after == null) continue;
      if (!seen.add(after.map(_cardKey).join('|'))) continue;
      final changed = _newCardPositions(before, after);
      // A play that leaves every card exactly as it was is the blend burned for nothing.
      if (changed.isEmpty && after.length == before.length) continue;
      shortlist.add((play, after, changed, _handPromise(after), shortlist.length));
    }
    // Discovery order breaks ties explicitly: Dart's sort is unstable, and the Coach showing a
    // different play for the same hand between two rebuilds is the kind of flicker that makes
    // an advisor look like it is guessing.
    shortlist.sort((a, b) => b.$4 != a.$4 ? b.$4 - a.$4 : a.$5 - b.$5);

    List<int>? bestPlay;
    ScoreResult? bestResult;
    final take = shortlist.length < kMaxBlendPlays ? shortlist.length : kMaxBlendPlays;
    for (var k = 0; k < take; k++) {
      final (play, after, changed, _, _) = shortlist[k];
      final res = _bestDishWith(after, ctx, run.critic, changed);
      if (res == null) continue;
      if (bestResult == null || res.score > bestResult.score) {
        bestResult = res;
        bestPlay = play;
      }
    }

    final helps = bestResult != null && bestResult.score > baseline;
    rows.add(BlendSuggestion(
      blendIndex: i,
      blend: blend,
      handIndexes: helps ? List<int>.of(bestPlay!) : const <int>[],
      result: helps ? bestResult : null,
      baseline: baseline,
      why: helps
          ? _blendPlayWhy(blend, before, bestPlay!, bestResult, baseline)
          : (_kBlendWhy[blend.id] ?? blend.desc),
    ));
  }

  rows.sort((a, b) {
    final byGain = b.gain - a.gain;
    // Explicit, because Dart's sort is unstable: equal-gain blends must keep rack order or
    // the rack and the advice list stop lining up between rebuilds.
    return byGain != 0 ? byGain : a.blendIndex - b.blendIndex;
  });
  return rows;
}

/// Everything [suggestBlends] reads, as one comparable string.
///
/// [suggestBlends] is the most expensive thing the Coach does — it is a dish search per
/// candidate play — and the service screen rebuilds on every card tap, where almost nothing it
/// depends on has moved. This lets the view skip the work when the answer cannot have changed.
///
/// **It must cover every input, or the panel will show stale advice**, which is the one thing
/// the Coach may never do. Those inputs are exactly: the hand, the rack, the deck (the draw
/// verbs reach into it, and `draw_matching` can dig to the bottom), and the scoring context
/// `ctxFor` builds — city palate, utensils, critic, Kitchen level, and the two dish-timing
/// flags. `test/coach_test.dart` asserts that moving any one of them moves this key.
String blendAdviceKey(RunState run) {
  final b = StringBuffer()
    ..write(cityOf(run).id)
    ..write('/')
    ..write(run.kitchenLevel)
    ..write('/')
    ..write(run.critic?.id ?? '-')
    ..write('/')
    ..write(run.dishesPlayed == 0)
    ..write('/')
    ..write(run.cooksLeft == 1)
    ..write('/');
  for (final u in run.utensils) {
    b
      ..write(u.id)
      ..write(',');
  }
  b.write('/');
  for (final x in run.blends) {
    b
      ..write(x.id)
      ..write(',');
  }
  b.write('/');
  for (final c in run.hand) {
    b
      ..write(_cardKey(c))
      ..write(',');
  }
  b.write('/');
  for (final c in run.deck) {
    b
      ..write(_cardKey(c))
      ..write(',');
  }
  return b.toString();
}

/// The line for a blend that measurably improves the hand.
///
/// Names the cards to tap and quotes the real before → after, so the player can check the
/// claim by tapping it. Every number in it came back from [scoreDish].
String _blendPlayWhy(
  Blend blend,
  List<Card> hand,
  List<int> play,
  ScoreResult res,
  int baseline,
) {
  final dish = kGenericNames[res.pattern] ?? res.pattern;
  final on = play.isEmpty
      ? ''
      : ' on ${[for (final i in play) hand[i].display].join(' + ')}';
  final order = play.length > 1 && blendReadsSource(blend) ? ' (in that order)' : '';
  return '${blend.name}$on$order makes a $dish — ${res.score}, up from $baseline.';
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

/// Base rank weight for a one-shot blend, and the fallback for a verb this table has not met.
///
/// **This is a sort key, not a score, and the UI must not print it as one.** A blend changes
/// the *cards*, not the scoring rules, so there is no dish to re-score it on: the benchmark
/// panel is five-card dishes, and a blend played on a finished dish does nothing the panel can
/// see. The web build uses the same flat constant. The scale is calibrated against the measured
/// utensils around it — a solid common runs ~30 per dish, so 55 puts a consumable below a live
/// permanent bought early and above one bought on the last service, which is the right ladder.
const double _kBlendValue = 55;

/// Rank weight for [b], from its effect DSL rather than its id, so a new blend is weighted the
/// moment it is authored.
///
/// The ordering is what the blends actually do for a run, worst to best: draws find a card,
/// rank verbs improve one, family verbs bridge one into a Flush, and the two that create
/// material — a second body, a prized card — are how Four and Five of a Kind happen at all.
/// `scope: 'hand'` and a second target both widen whatever the verb is, so both add.
double blendRankWeight(Blend? b) {
  if (b == null) return _kBlendValue;
  final e = b.effect;
  double base;
  if (e['duplicate'] == true || e['set_prized'] == true) {
    base = 75;
  } else if (e['set_family'] != null || e['copy_family'] == true) {
    base = 65;
  } else if (e['copy_rank'] == true || e['merge'] == true) {
    base = 60;
  } else if (e['rank_set'] != null || e['rank_add'] != null || e['rank_invert'] == true) {
    base = 50;
  } else if (e['draw'] != null || e['discard_draw'] == true || e['draw_matching'] == true) {
    base = 40;
  } else {
    base = _kBlendValue;
  }
  if (e['scope'] == 'hand') base += 10;
  if (b.select > 1) base += 5;
  return base;
}

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
  final est = _jsRound((run.route.length * 3 - done) * 2.5);
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
    (run.endless || run.cityIndex < run.route.length) ? cityOf(run) : run.route.last;

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
      // One-shot, and its value is entirely in the hand it is played on. It used to be filed
      // as `situational` — the same bucket as a utensil whose condition never fires — which
      // read as "don't bother" for the system the game most needs a new player to try. It gets
      // its own category and a weight that separates a Conserva from a Winnowing, and the UI
      // does not print the weight, because it is a rank key and not dish score.
      final b = kBlendById[o.id];
      category = 'consumable';
      value = blendRankWeight(b);
      why = '${_kBlendWhy[o.id] ?? o.desc} One-shot: it edits the cards in your hand, so it is '
          'worth most on the hand that is one card short of a recipe.';
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

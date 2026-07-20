/// Spice Blends — the one-shot consumables, and the only route to the secret recipes.
///
/// Blends are the one mechanic that EDITS cards instead of scoring them. `bestPattern`
/// already scores `five_kind`, `full_family` and `perfect_palate`, but nothing in the pantry
/// can produce five of a rank or a one-family full house on its own — the blends are what
/// make those three reachable at all, which is why an app that sells blends without applying
/// them burns coins for nothing.
///
/// ## The effect DSL
///
/// The six ported blends began life as six `case` arms, which meant every new blend was an
/// engine change — the thing the utensil DSL exists to avoid. [applyBlend] is now an
/// interpreter over [Blend.effect], and all twenty blends are catalog data. The key set is
/// deliberately small; every key below is a *verb*, and a blend that needs no new verb needs
/// no new key. `test/blends_test.dart` holds the allow-list and fails on anything else.
///
/// **Card rewrites** — applied to each card in the edit set (see below):
///
/// | key | value | meaning |
/// |---|---|---|
/// | `set_family` | family | the card becomes that family |
/// | `copy_family` | true | the card takes the *source's* family |
/// | `rank_set` | 1..10 | intensity becomes exactly this |
/// | `rank_add` | int | intensity moves by this, clamped to 1..10 (may be negative) |
/// | `rank_invert` | true | intensity becomes `11 - rank`: a 2 becomes a 9 |
/// | `copy_rank` | true | the card takes the *source's* intensity |
/// | `set_prized` | true | the card becomes prized (+[kPrizedBonus] flavour) |
/// | `prefix` | text | prepended to the display name, e.g. `'Chili '` |
///
/// **Hand and deck operations** — applied to the targets, after the rewrites:
///
/// | key | value | meaning |
/// |---|---|---|
/// | `duplicate` | true | append a copy of each target, id suffixed `_copy` |
/// | `merge` | true | targets after the first are consumed; the first takes their combined intensity, capped at 10 |
/// | `discard_draw` | true | the targets leave the hand; draw that many off the deck |
/// | `draw_matching` | true | draw the first deck card sharing the target's family |
/// | `draw` | int | draw this many off the top of the deck |
///
/// **The one modifier**: `scope: 'hand'` redirects the rewrites from the selection to every
/// card in hand. Only meaningful with `select: 0`, which is how Cold Smoke takes no targets
/// and still edits everything.
///
/// ### The edit set, and the source
///
/// Rewrites normally apply to every target, in selection order. `copy_family`, `copy_rank`
/// and `merge` instead read the **first** selected card as a source and leave it untouched —
/// they are the two-card verbs ("make this one like that one"), and the first tap is the
/// "that". `scope: 'hand'` overrides the edit set entirely.
///
/// Order within one blend is fixed and total, so a multi-key effect cannot be ambiguous:
/// family, then rank, then prized, then prefix; then the hand/deck operations in table order.
/// No shipped blend writes the same field twice — `test/blends_test.dart` enforces that a
/// blend carries at most one family verb and at most one rank verb, which keeps the order a
/// documented detail rather than something content has to reason about.
///
/// ## Fidelity to the web build
///
/// The web build is the behavioural reference (CLAUDE.md), and its six survive this rewrite
/// byte for byte — `test/vectors.json`'s 29 recorded cases pin them, including the parts that
/// read like oversights and are not:
///   - only an *empty* selection is refused. A `select: 2` blend played on one card is legal
///     and affects that one card.
///   - selections beyond `select` are ignored rather than rejected — the UI caps selection
///     size anyway, so the tail is simply dropped.
///   - a blend whose effect map does nothing changes nothing but is still consumed.
///   - targets are taken in selection order, which is tap order, not hand order.
///
/// What this port adds is bounds checking. The JS gets away without it because its only
/// caller is a tap handler over the rendered hand, so the indices are true by construction.
/// Here the Coach and `tools/sim` call in too, and an out-of-range index in Dart is a crash
/// on the player's screen rather than a shrug — so every index is checked up front, before
/// anything is mutated. No selection the game can actually produce reaches those branches.
///
/// The one behaviour that is *not* the web's: a two-card verb played on a single card is
/// refused rather than silently wasted. None of the six can reach that branch, so the
/// differential holds; see [kBlendNeedsTwo] for why the newcomers get the guard.
library;

import 'models.dart';
import 'run.dart';

/// The result of [applyBlend]. Either [error] is set and nothing changed, or [ok] is true
/// and the blend was consumed.
class BlendOutcome {
  const BlendOutcome({this.error, this.ok = false});

  /// Why the blend was refused. Null on success.
  final String? error;
  final bool ok;
}

/// Shown when a blend that needs targets is played with an empty selection.
///
/// Pinned to the web build's wording by the differential vectors — the fixture records the
/// flash message verbatim, so this string is part of the port, not copy to be improved.
const String kBlendNoSelection = 'Select ingredient(s) first, then tap the blend';

/// Shown when a two-card verb gets one card.
///
/// `copy_family`, `copy_rank` and `merge` read the first selected card as a source, so with a
/// single target there is a source and nothing to apply it to: the blend would be consumed
/// for no effect. The web build has no such blend and therefore no such message, which is why
/// adding this guard cannot move the differential — but a consumable that silently eats four
/// coins is the worst failure mode this system has, so the newcomers refuse instead.
const String kBlendNeedsTwo = 'Select 2 ingredients — the first one is the source';

/// Effect keys that read the first selected card as a source rather than editing it.
const Set<String> _sourceReading = {'copy_family', 'copy_rank', 'merge'};

int _clampRank(int r) => r < 1 ? 1 : (r > 10 ? 10 : r);

/// Applies `run.blends[blendIndex]` to the hand cards at [handIndexes], in selection order.
///
/// Consumes the blend on success. On any error nothing is mutated — the blend stays in the
/// inventory and the hand is untouched — so a rejected tap is free. Every refusal is decided
/// before the first write for exactly that reason.
///
/// [handIndexes] mirrors the web's selection Set, so callers should pass distinct indices.
/// Duplicates are not rejected: the rewrites apply the effect once per occurrence, which is
/// what the reference does with the same input, and the card-removing verbs dedupe so a
/// repeated index cannot delete a bystander.
BlendOutcome applyBlend(RunState run, int blendIndex, List<int> handIndexes) {
  if (blendIndex < 0 || blendIndex >= run.blends.length) {
    return const BlendOutcome(error: 'No such blend');
  }
  final blend = run.blends[blendIndex];
  if (blend.select > 0 && handIndexes.isEmpty) {
    return const BlendOutcome(error: kBlendNoSelection);
  }
  for (final i in handIndexes) {
    if (i < 0 || i >= run.hand.length) {
      return const BlendOutcome(error: 'That ingredient is no longer in your hand');
    }
  }

  final effect = blend.effect;
  final targets = handIndexes.take(blend.select).toList();
  final needsSource = effect.keys.any(_sourceReading.contains);
  if (needsSource && targets.length < 2) {
    return const BlendOutcome(error: kBlendNeedsTwo);
  }

  // --- card rewrites ---------------------------------------------------------------------
  // The source is read once, up front: `merge` mutates the keeper, and `copy_*` must not see
  // a value it wrote itself if the same index is somehow selected twice.
  final source = needsSource ? run.hand[targets.first] : null;
  final List<int> editSet;
  if (effect['scope'] == 'hand') {
    editSet = [for (var i = 0; i < run.hand.length; i++) i];
  } else if (needsSource) {
    editSet = targets.sublist(1);
  } else {
    editSet = targets;
  }

  final setFamily = effect['set_family'] as String?;
  final copyFamily = effect['copy_family'] == true;
  final rankSet = effect['rank_set'] as int?;
  final rankAdd = effect['rank_add'] as int?;
  final rankInvert = effect['rank_invert'] == true;
  final copyRank = effect['copy_rank'] == true;
  final prized = effect['set_prized'] == true;
  final prefix = effect['prefix'] as String?;

  for (final i in editSet) {
    final card = run.hand[i];
    var family = card.family;
    var rank = card.rank;
    var display = card.display;
    var isPrized = card.prized;

    if (setFamily != null) family = setFamily;
    if (copyFamily) family = source!.family;
    if (rankSet != null) rank = _clampRank(rankSet);
    if (rankAdd != null) rank = _clampRank(rank + rankAdd);
    if (rankInvert) rank = _clampRank(11 - rank);
    if (copyRank) rank = source!.rank;
    if (prized) isPrized = true;
    if (prefix != null) display = '$prefix$display';

    run.hand[i] = card.copyWith(family: family, rank: rank, display: display, prized: isPrized);
  }

  // --- hand and deck operations ----------------------------------------------------------
  if (effect['duplicate'] == true) {
    // The copy keeps every field but the id, which gains a `_copy` suffix. Two Sun-Drys on
    // the same card therefore mint the same id twice; nothing in the engine keys off
    // `Card.id`, so that is harmless — see the note in test/blends_test.dart.
    for (final i in targets) {
      run.hand.add(run.hand[i].copyWith(id: '${run.hand[i].id}_copy'));
    }
  }
  if (effect['merge'] == true) {
    final keeper = targets.first;
    final absorbed = targets.skip(1).toSet().where((i) => i != keeper).toList()..sort();
    var total = run.hand[keeper].rank;
    for (final i in absorbed) {
      total += run.hand[i].rank;
    }
    run.hand[keeper] = run.hand[keeper].copyWith(rank: _clampRank(total));
    // Descending, so an earlier removal cannot shift a later index out from under us.
    for (final i in absorbed.reversed) {
      run.hand.removeAt(i);
    }
  }
  if (effect['discard_draw'] == true) {
    final dropped = targets.toSet().toList()..sort();
    for (final i in dropped.reversed) {
      run.hand.removeAt(i);
    }
    for (var k = 0; k < dropped.length && run.deck.isNotEmpty; k++) {
      run.hand.add(run.deck.removeAt(0));
    }
  }
  if (effect['draw_matching'] == true) {
    // Deck order decides which match you get, so this stays a pure function of the seed.
    for (final i in targets) {
      final family = run.hand[i].family;
      final at = run.deck.indexWhere((c) => c.family == family);
      if (at >= 0) run.hand.add(run.deck.removeAt(at));
    }
  }
  final draw = effect['draw'] as int?;
  if (draw != null) {
    // Stops early on an exhausted deck.
    for (var k = 0; k < draw && run.deck.isNotEmpty; k++) {
      run.hand.add(run.deck.removeAt(0));
    }
  }

  run.blends.removeAt(blendIndex);
  return const BlendOutcome(ok: true);
}

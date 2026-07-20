/// Spice Blends — the one-shot consumables, and the only route to the secret recipes.
///
/// A port of §UI's `useBlend` (`web/tadka.html` ~1289–1305). It sits in the UI layer over
/// there only because it is wired straight to a tap handler; it is unmistakably game logic.
/// `bestPattern` already scores `five_kind`, `full_family` and `perfect_palate`, but nothing
/// in the pantry can produce five of a rank or a one-family full house on its own — the
/// blends are what make those three reachable at all, which is why an app that sells blends
/// without applying them burns coins for nothing.
///
/// The web build is the behavioural reference (CLAUDE.md), so the six cases below are a
/// literal translation, including the parts that read like oversights and are not:
///   - only an *empty* selection is refused. A `select: 2` blend played on one card is legal
///     and affects that one card.
///   - selections beyond `select` are ignored rather than rejected — the UI caps selection
///     size anyway, so the tail is simply dropped.
///   - an unrecognised blend id changes nothing but is still consumed.
///   - targets are taken in selection order, which is tap order, not hand order.
///
/// What this port adds is bounds checking. The JS gets away without it because its only
/// caller is a tap handler over the rendered hand, so the indices are true by construction.
/// Here the Coach and `tools/sim` call in too, and an out-of-range index in Dart is a crash
/// on the player's screen rather than a shrug — so every index is checked up front, before
/// anything is mutated. No selection the game can actually produce reaches those branches.
library;

import 'run.dart';

/// The result of [applyBlend]. Either [error] is set and nothing changed, or [ok] is true
/// and the blend was consumed.
class BlendOutcome {
  const BlendOutcome({this.error, this.ok = false});

  /// Why the blend was refused. Null on success.
  final String? error;
  final bool ok;
}

/// Applies `run.blends[blendIndex]` to the hand cards at [handIndexes], in selection order.
///
/// Consumes the blend on success. On any error nothing is mutated — the blend stays in the
/// inventory and the hand is untouched — so a rejected tap is free.
///
/// [handIndexes] mirrors the web's selection Set, so callers should pass distinct indices.
/// Duplicates are not rejected; they apply the effect once per occurrence, which is what the
/// reference does with the same input.
BlendOutcome applyBlend(RunState run, int blendIndex, List<int> handIndexes) {
  if (blendIndex < 0 || blendIndex >= run.blends.length) {
    return const BlendOutcome(error: 'No such blend');
  }
  final blend = run.blends[blendIndex];
  if (blend.select > 0 && handIndexes.isEmpty) {
    return const BlendOutcome(error: 'Select ingredient(s) first, then tap the blend');
  }
  for (final i in handIndexes) {
    if (i < 0 || i >= run.hand.length) {
      return const BlendOutcome(error: 'That ingredient is no longer in your hand');
    }
  }

  final targets = handIndexes.take(blend.select);
  switch (blend.id) {
    case 'chili_oil':
      for (final i in targets) {
        run.hand[i] = run.hand[i].copyWith(family: 'spicy', display: 'Chili ${run.hand[i].display}');
      }
    case 'sea_salt':
      for (final i in targets) {
        run.hand[i] = run.hand[i].copyWith(family: 'salty', display: 'Salted ${run.hand[i].display}');
      }
    case 'fermentation':
      for (final i in targets) {
        final raised = run.hand[i].rank + 3;
        run.hand[i] = run.hand[i].copyWith(rank: raised > 10 ? 10 : raised);
      }
    case 'sharpen':
      for (final i in targets) {
        run.hand[i] = run.hand[i].copyWith(rank: 10);
      }
    case 'sun_dry':
      // The copy keeps every field but the id, which gains a `_copy` suffix. Two Sun-Drys on
      // the same card therefore mint the same id twice; nothing in the engine keys off
      // `Card.id`, so that is harmless — see the note in test/blends_test.dart.
      for (final i in targets) {
        run.hand.add(run.hand[i].copyWith(id: '${run.hand[i].id}_copy'));
      }
    case 'mise':
      // select is 0, so this needs no targets. Stops early on an exhausted deck.
      for (var k = 0; k < 2 && run.deck.isNotEmpty; k++) {
        run.hand.add(run.deck.removeAt(0));
      }
  }

  run.blends.removeAt(blendIndex);
  return const BlendOutcome(ok: true);
}

/// Tests for the Coach: legality, ordering, and the anti-drift guarantee.
///
/// The load-bearing one is `reports exactly what the engine will pay` — CLAUDE.md's rule is
/// that the Coach drives the live engine rather than shadowing it, and the only way that
/// stays true under future edits is to assert it. Everything else here is scaffolding around
/// that: a suggestion the critic would reject, or a ladder sorted the wrong way, is a bug the
/// player pays for in a lost run.
///
/// The profile is global and feeds `rollOffers`, so it is reset before anything that rolls.
@TestOn('vm')
library;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

Card _card(String family, int rank, {bool prized = false}) => Card(
  id: '${family}_$rank${prized ? '_p' : ''}',
  family: family,
  rank: rank,
  display: '$rank $family',
  prized: prized,
);

/// A run positioned at a known service, with the hand replaced by a fixture.
///
/// Reaching a later city by playing is slow and seed-dependent; every field poked here is
/// public run state the reducer itself writes, so the result is a state the game can be in.
RunState _runWith({
  required List<Card> hand,
  Critic? critic,
  List<Utensil> utensils = const [],
  int kitchenLevel = 1,
  int cityIndex = 0,
  int serviceIndex = 0,
  int cooksLeft = 4,
  int dishesPlayed = 0,
  String seed = 'COACH-TEST',
}) {
  profile = defaultProfile();
  final run = newRun(seed: seed);
  run.hand = List<Card>.of(hand);
  run.critic = critic;
  run.utensils = List<Utensil>.of(utensils);
  run.kitchenLevel = kitchenLevel;
  run.cityIndex = cityIndex;
  run.serviceIndex = serviceIndex;
  run.cooksLeft = cooksLeft;
  run.dishesPlayed = dishesPlayed;
  return run;
}

/// A deliberately rich hand: a spicy trio, a pair, a prized card and a straight's worth of
/// ranks, so the solver has several genuinely different recipes to choose between.
List<Card> _mixedHand() => [
  _card('spicy', 8),
  _card('spicy', 5),
  _card('spicy', 3),
  _card('sweet', 8),
  _card('sour', 4),
  _card('salty', 6),
  _card('umami', 7),
  const Card(id: 'prized_saffron', family: 'umami', rank: 10, display: 'Saffron', prized: true),
];

Utensil _u(String id) => kUtensilById[id]!;

/// The best legal dish in [hand], found the slow, obvious way.
///
/// Deliberately not `suggestDishes` and deliberately not the Coach's own pruned search: the
/// blend tests use this to check the Coach's claim against an independent brute force, so
/// sharing the solver would make the assertion circular.
int _bestScoreOf(List<Card> hand, ScoreContext ctx, Critic? critic) {
  var best = 0;
  final n = hand.length;
  void walk(int start, List<int> acc) {
    if (acc.isNotEmpty) {
      final cards = [for (final i in acc) hand[i]];
      if (dishError(cards, critic) == null) {
        final s = scoreDish(cards, ctx).score;
        if (s > best) best = s;
      }
    }
    if (acc.length == 5) return;
    for (var i = start; i < n; i++) {
      walk(i + 1, [...acc, i]);
    }
  }

  walk(0, const []);
  return best;
}

void main() {
  group('suggestDishes', () {
    test('never suggests a dish the critic would reject', () {
      // Every critic the game can put in front of a player, not a sample of them: a demand
      // the solver mishandles shows up as an illegal suggestion, and the player finds out by
      // tapping COOK and being refused. The v1.0 pass added the first compound majors
      // (Connoisseur, Perfectionist) and the first floor of 5 (Maximalist), which are exactly
      // the shapes a `maxCards`-only cap in the solver would get wrong.
      for (final critic in <Critic?>[
        null,
        ...kCritics.values,
        ...kMinorCritics,
      ]) {
        final run = _runWith(hand: _mixedHand(), critic: critic);
        final out = suggestDishes(run);
        expect(out, isNotEmpty, reason: 'critic ${critic?.id ?? 'none'} — nothing suggested');
        for (final s in out) {
          final cards = [for (final i in s.handIndexes) run.hand[i]];
          expect(
            dishError(cards, run.critic),
            isNull,
            reason: 'critic ${critic?.id ?? 'none'} suggested an illegal dish: '
                '${s.handIndexes} (${s.result.pattern})',
          );
        }
      }
    });

    test('respects the Minimalist card cap', () {
      final run = _runWith(hand: _mixedHand(), critic: kCritics['minimalist']);
      final out = suggestDishes(run);
      expect(out, isNotEmpty);
      for (final s in out) {
        expect(s.handIndexes.length, lessThanOrEqualTo(3), reason: 'over the 3-card cap');
      }
      // And the cap really did bite: unconstrained, the same hand reaches a wider dish.
      final free = suggestDishes(_runWith(hand: _mixedHand()));
      expect(free.any((s) => s.handIndexes.length > 3), isTrue);
    });

    test('is sorted by score, descending, with no repeated pattern', () {
      final run = _runWith(hand: _mixedHand(), utensils: [_u('griddle'), _u('iron_tawa')]);
      final out = suggestDishes(run);
      expect(out.length, greaterThan(1));
      for (var i = 1; i < out.length; i++) {
        expect(
          out[i].result.score,
          lessThanOrEqualTo(out[i - 1].result.score),
          reason: 'row $i outscores the row above it',
        );
      }
      final patterns = out.map((s) => s.result.pattern).toList();
      expect(patterns.toSet().length, equals(patterns.length), reason: 'duplicate pattern rows');
    });

    test('indexes are ascending, in range, and free of duplicates', () {
      final run = _runWith(hand: _mixedHand());
      for (final s in suggestDishes(run)) {
        expect(s.handIndexes, isNotEmpty);
        expect(s.handIndexes.toSet().length, equals(s.handIndexes.length));
        for (var i = 1; i < s.handIndexes.length; i++) {
          expect(s.handIndexes[i], greaterThan(s.handIndexes[i - 1]));
        }
        for (final i in s.handIndexes) {
          expect(i, inInclusiveRange(0, run.hand.length - 1));
        }
      }
    });

    // THE anti-drift guarantee. If this ever fails, the Coach has started doing its own
    // maths and every number it shows the player is a promise the game will not keep.
    test('reports exactly what the engine will pay', () {
      final runs = [
        _runWith(hand: _mixedHand()),
        _runWith(hand: _mixedHand(), critic: kCritics['traditionalist'], kitchenLevel: 4),
        _runWith(
          hand: _mixedHand(),
          utensils: [_u('iron_tawa'), _u('tandoor'), _u('pressure_cooker'), _u('clay_handi')],
          kitchenLevel: 6,
          cityIndex: 2,
          serviceIndex: 1,
          cooksLeft: 1, // is_last_dish, so Clay Handi is live
          dishesPlayed: 3,
        ),
        _runWith(
          hand: _mixedHand(),
          utensils: [_u('grandmother_ladle'), _u('clay_handi')],
          cityIndex: 1,
          cooksLeft: 1,
        ),
      ];
      for (final run in runs) {
        final ctx = ctxFor(run);
        final out = suggestDishes(run, limit: 12);
        expect(out, isNotEmpty);
        for (final s in out) {
          final cards = [for (final i in s.handIndexes) run.hand[i]];
          final truth = scoreDish(cards, ctx);
          final where = '${s.result.pattern} @ ${s.handIndexes}';
          expect(s.result.score, equals(truth.score), reason: '$where — SCORE drift');
          expect(s.result.flavor, equals(truth.flavor), reason: '$where — flavor drift');
          expect(s.result.heat, equals(truth.heat), reason: '$where — heat drift');
          expect(s.result.coins, equals(truth.coins), reason: '$where — coins drift');
          expect(s.result.pattern, equals(truth.pattern), reason: '$where — pattern drift');
        }
      }
    });

    test('cooking the top suggestion scores what it promised', () {
      final run = _runWith(
        hand: _mixedHand(),
        utensils: [_u('iron_tawa'), _u('griddle')],
        kitchenLevel: 3,
      );
      final top = suggestDishes(run).first;
      final promised = top.result.score;
      final cooked = doCook(run, top.handIndexes);
      expect(cooked.error, isNull);
      expect(cooked.result!.score, equals(promised));
      expect(run.score, equals(promised));
    });

    test('never comes back empty for a non-empty hand', () {
      final singles = [
        [_card('spicy', 1)],
        [_card('sweet', 10)],
        [_card('sour', 3), _card('sour', 3)],
      ];
      for (final hand in singles) {
        expect(suggestDishes(_runWith(hand: hand)), isNotEmpty, reason: 'hand $hand');
      }
      // Every hand a real service can deal, across the shuffle.
      for (final seed in ['SPICE-AAAA', 'SPICE-BBBB', 'SPICE-CCCC', 'SPICE-DDDD']) {
        profile = defaultProfile();
        final run = newRun(seed: seed);
        expect(suggestDishes(run), isNotEmpty, reason: 'seed $seed');
      }
    });

    test('is empty only when there is nothing legal to cook', () {
      expect(suggestDishes(_runWith(hand: const [])), isEmpty);
      // The Sweet Tooth demands a Sweet ingredient; this hand has none.
      final starved = _runWith(
        hand: [_card('spicy', 4), _card('sour', 6)],
        critic: kMinorCritics.firstWhere((c) => c.id == 'sweet_tooth'),
      );
      expect(suggestDishes(starved), isEmpty);
    });

    test('honours limit', () {
      final run = _runWith(hand: _mixedHand());
      expect(suggestDishes(run, limit: 2).length, equals(2));
      expect(suggestDishes(run, limit: 1).length, equals(1));
      expect(suggestDishes(run).length, lessThanOrEqualTo(6));
    });

    test('why names the recipe and stays plain text', () {
      final run = _runWith(
        hand: _mixedHand(),
        utensils: [_u('clay_handi')],
        cooksLeft: 1,
        cityIndex: 2,
      );
      for (final s in suggestDishes(run)) {
        expect(s.why, isNotEmpty);
        expect(s.why, contains(kGenericNames[s.result.pattern]));
        expect(s.why, isNot(contains('<')), reason: 'markup leaked into the Coach copy');
      }
      // Clay Handi is live on the last cook, so the top row must credit the multiplier.
      expect(suggestDishes(run).first.why, contains('Clay Handi'));
    });

    // The v1.0 pass added nine flavour multipliers to a catalog that had only ever multiplied
    // heat, and the one-liner said "multiplies heat" for all of them — the Coach naming the
    // wrong axis teaches the wrong build, which is worse than saying nothing.
    group('why names the axis the multiplier actually moved', () {
      String whyWith(List<Utensil> utensils, List<Card> hand) {
        final run = _runWith(hand: hand, utensils: utensils);
        return suggestDishes(run).first.why;
      }

      final allSour = [for (var r = 4; r <= 8; r++) _card('sour', r)];

      test('a heat multiplier says heat', () {
        // Tandoor: ×1.5 heat on an all-Spicy dish.
        final why = whyWith([_u('tandoor')], [for (var r = 4; r <= 8; r++) _card('spicy', r)]);
        expect(why, contains('multiplies heat'));
        expect(why, isNot(contains('multiplies flavor')));
      });

      test('a flavour multiplier says flavor', () {
        // Tamarind Press: ×1.5 flavor on an all-Sour dish.
        final why = whyWith([_u('tamarind_press')], allSour);
        expect(why, contains('multiplies flavor'));
        expect(why, isNot(contains('multiplies heat')));
      });

      test('one of each says both, because that is the biggest jump in the game', () {
        // Konro Grill (×2 heat, one family) beside Clay Tandır (×2 flavor, one family).
        final why = whyWith([_u('konro_grill'), _u('clay_tandir')], allSour);
        expect(why, contains('both tracks'));
      });
    });

    test('why names the critic when the critic is what flattened the dish', () {
      // The Ascetic zeroes Spicy, and this hand's best dish is built from Spicy cards.
      final run = _runWith(
        hand: [
          _card('spicy', 9),
          _card('spicy', 9),
          _card('spicy', 8),
          _card('sweet', 3),
          _card('sour', 2),
        ],
        critic: kCritics['ascetic'],
      );
      final why = suggestDishes(run).first.why;
      expect(why, contains('The Ascetic'));
      expect(why, contains('spicy'));
    });

    test('why names a demand that shaped the dish', () {
      // The Firebrand requires a Spicy card in every dish — a whole slot spoken for. No Sour
      // in the hand, so Kochi's palate has nothing to say and the demand is the story.
      final run = _runWith(
        hand: [_card('spicy', 2), _card('sweet', 9), _card('umami', 7), _card('salty', 4)],
        critic: kCritics['firebrand'],
      );
      expect(suggestDishes(run).first.why, contains('The Firebrand'));
    });

    test('why names the local palate rather than a generic "big recipes are good"', () {
      // Kochi pays +50% of intensity as flavor on Sour, and the best dish here is a Sour
      // Flush — the palate line is the actionable one, so it has to outrank the filler.
      final run = _runWith(hand: [for (var r = 4; r <= 8; r++) _card('sour', r)]);
      final why = suggestDishes(run).first.why;
      expect(why, contains('sour'));
      expect(why, contains('50%'));
    });

    test('is deterministic — same run, same ladder', () {
      final run = _runWith(hand: _mixedHand(), utensils: [_u('ice_box')], dishesPlayed: 0);
      final a = suggestDishes(run);
      final b = suggestDishes(run);
      expect(a.map((s) => s.handIndexes).toList(), equals(b.map((s) => s.handIndexes).toList()));
      expect(a.map((s) => s.why).toList(), equals(b.map((s) => s.why).toList()));
    });
  });

  group('rankOffers', () {
    Offer utensilOffer(String id) {
      final u = _u(id);
      return Offer(kind: 'utensil', id: id, name: u.name, cost: u.cost, rarity: u.rarity, desc: u.text);
    }

    test('returns one entry per offer, sorted descending, order preserved', () {
      profile = defaultProfile();
      final run = newRun(seed: 'BAZAAR-1');
      final offers = rollOffers(run);
      final ranked = rankOffers(run, offers);
      expect(ranked.length, equals(offers.length));
      expect(
        ranked.map((r) => r.offer.id).toSet(),
        equals(offers.map((o) => o.id).toSet()),
      );
      for (var i = 1; i < ranked.length; i++) {
        expect(ranked[i].marginalValue, lessThanOrEqualTo(ranked[i - 1].marginalValue));
      }
      for (final r in ranked) {
        expect(r.why, isNotEmpty);
        expect(
          r.category,
          isIn(const ['economy', 'combo', 'consumable', 'scaling', 'situational', 'solid']),
        );
      }
    });

    test('empty in, empty out', () {
      final run = _runWith(hand: _mixedHand());
      expect(rankOffers(run, const []), isEmpty);
    });

    test('categorises coin utensils as economy and the Ladle as combo', () {
      final run = _runWith(hand: _mixedHand());
      final ranked = rankOffers(run, [
        utensilOffer('street_cart'),
        utensilOffer('chai_stall'),
        utensilOffer('grandmother_ladle'),
        utensilOffer('iron_tawa'),
        const Offer(kind: 'festival', id: 'fest_flush', name: 'Holi', cost: 3, rarity: 'festival', pattern: 'flush'),
        const Offer(kind: 'blend', id: 'chili_oil', name: 'Chili Oil', cost: 3, rarity: 'blend', desc: 'x'),
      ]);
      String catOf(String id) => ranked.firstWhere((r) => r.offer.id == id).category;
      expect(catOf('street_cart'), equals('economy'));
      expect(catOf('chai_stall'), equals('economy'));
      expect(catOf('grandmother_ladle'), equals('combo'));
      expect(catOf('iron_tawa'), equals('solid'));
      expect(catOf('fest_flush'), equals('scaling'));
      // A blend is a one-shot, not a utensil whose condition never fires. `situational` put
      // the two in one bucket and read as "don't bother" for the system a new player most
      // needs to try, so consumables get their own.
      expect(catOf('chili_oil'), equals('consumable'));
    });

    test('blends are weighted by what their verb does, not lumped together', () {
      final run = _runWith(hand: _mixedHand());
      Offer blendOffer(String id) {
        final b = kBlendById[id]!;
        return Offer(kind: 'blend', id: id, name: b.name, cost: b.cost, rarity: 'blend', desc: b.desc);
      }

      final ranked = rankOffers(run, [
        blendOffer('winnow'), // a draw
        blendOffer('fermentation'), // a rank tweak
        blendOffer('chili_oil'), // a family bridge
        blendOffer('conserva'), // creates material
      ]);
      double valueOf(String id) => ranked.firstWhere((r) => r.offer.id == id).marginalValue;
      expect(valueOf('conserva'), greaterThan(valueOf('chili_oil')));
      expect(valueOf('chili_oil'), greaterThan(valueOf('fermentation')));
      expect(valueOf('fermentation'), greaterThan(valueOf('winnow')));
      // Every blend in the catalog must get a weight, or a new one sorts to the bottom
      // silently — which is exactly how a shop stops offering something worth buying.
      for (final b in kBlends) {
        expect(blendRankWeight(b), greaterThan(0), reason: '${b.id} has no weight');
      }
      // Cold Smoke edits the whole hand, so it must outrank the same verb on one card.
      expect(blendRankWeight(kBlendById['cold_smoke']),
          greaterThan(blendRankWeight(kBlendById['fermentation'])));
    });

    // The whole point of measuring rather than guessing: something that fires must beat
    // something that cannot.
    test('values a utensil that fires above one that cannot', () {
      final run = _runWith(hand: _mixedHand());
      final ranked = rankOffers(run, [
        utensilOffer('grandmother_ladle'), // nothing to its right — cannot fire
        utensilOffer('street_cart'), // pays coins, never dish score
        utensilOffer('tandoor'), // ×1.5 heat on the all-Spicy benchmark
      ]);
      double valueOf(String id) => ranked.firstWhere((r) => r.offer.id == id).marginalValue;
      expect(valueOf('tandoor'), greaterThan(0));
      expect(valueOf('tandoor'), greaterThan(valueOf('grandmother_ladle')));
      expect(valueOf('tandoor'), greaterThan(valueOf('street_cart')));
      expect(ranked.first.offer.id, equals('tandoor'));
    });

    test('a multiplier is worth more to a build that already stacks flavor', () {
      final bare = _runWith(hand: _mixedHand());
      final loaded = _runWith(
        hand: _mixedHand(),
        utensils: [_u('iron_tawa'), _u('honey_jar'), _u('butchers_block')],
        kitchenLevel: 5,
      );
      double tandoor(RunState r) =>
          rankOffers(r, [utensilOffer('tandoor')]).single.marginalValue;
      expect(
        tandoor(loaded),
        greaterThan(tandoor(bare)),
        reason: '×heat scales with the flavor total it multiplies — the valuation must see that',
      );
    });

    test('a permanent is worth less the later it is bought', () {
      const festival = Offer(
        kind: 'festival', id: 'fest_flush', name: 'Holi', cost: 3, rarity: 'festival', pattern: 'flush',
      );
      final early = _runWith(hand: _mixedHand(), cityIndex: 0, serviceIndex: 0);
      final late = _runWith(hand: _mixedHand(), cityIndex: 2, serviceIndex: 1);
      final earlyValue = rankOffers(early, [festival]).single.marginalValue;
      final lateValue = rankOffers(late, [festival]).single.marginalValue;
      expect(earlyValue, greaterThan(lateValue));
      expect(lateValue, greaterThan(0), reason: 'a Festival still pays on the last service');
    });

    test('the quoted before → after is a real engine pair', () {
      final run = _runWith(hand: _mixedHand(), kitchenLevel: 2);
      final r = rankOffers(run, [utensilOffer('golden_sieve')]).single;
      expect(r.category, equals('solid'));
      // Golden Sieve is a Flush utensil; the panel's Flush bench is where it shows best.
      expect(r.why, contains('5-Spicy Flush'));
      expect(r.why, contains('→'));
    });

    test('sorting is stable for equal values', () {
      final run = _runWith(hand: _mixedHand());
      final offers = [
        utensilOffer('street_cart'),
        utensilOffer('chai_stall'),
        utensilOffer('grandmother_ladle'),
      ];
      final ranked = rankOffers(run, offers);
      expect(ranked.map((r) => r.marginalValue).toSet(), equals({0.0}));
      expect(
        ranked.map((r) => r.offer.id).toList(),
        equals(offers.map((o) => o.id).toList()),
        reason: 'equal-value offers must keep their bazaar order',
      );
    });

    test('does not touch the run', () {
      profile = defaultProfile();
      final run = newRun(seed: 'PURE-1');
      final offers = rollOffers(run);
      // A second roll from an untouched RNG must match the reference run's second roll.
      profile = defaultProfile();
      final reference = newRun(seed: 'PURE-1');
      rollOffers(reference);
      final expected = rollOffers(reference).map((o) => o.id).toList();

      rankOffers(run, offers);
      suggestDishes(run);
      expect(
        rollOffers(run).map((o) => o.id).toList(),
        equals(expected),
        reason: 'the Coach drew from run.rng and desynced the run',
      );
    });
  });

  group('suggestBlends', () {
    // Every deck now opens with a blend or two, so the rack is set outright rather than
    // appended to — these tests are about a named rack, not about the deck's.
    RunState withBlends(List<String> ids, {List<Card>? hand, Critic? critic}) {
      final run = _runWith(hand: hand ?? _mixedHand(), critic: critic);
      run.blends = [for (final id in ids) kBlendById[id]!];
      return run;
    }

    test('one row per held blend, best gain first, ties keeping rack order', () {
      final run = withBlends(['chili_oil', 'fermentation', 'sun_dry']);
      final out = suggestBlends(run);
      expect(out.length, equals(3));
      expect(out.map((b) => b.blend.id).toSet(), equals({'chili_oil', 'fermentation', 'sun_dry'}));
      for (var i = 1; i < out.length; i++) {
        expect(out[i].gain, lessThanOrEqualTo(out[i - 1].gain));
      }
      final zeros = out.where((b) => b.gain == 0).map((b) => b.blendIndex).toList();
      expect(zeros, equals(List<int>.of(zeros)..sort()), reason: 'equal gains reshuffled');
    });

    test('empty for an empty rack or an empty hand', () {
      expect(suggestBlends(withBlends(const [])), isEmpty);
      expect(suggestBlends(withBlends(['sun_dry'], hand: const [])), isEmpty);
    });

    // THE anti-drift guarantee for blends, and the reason this feature is worth having:
    // every claim is replayed through the real applyBlend and the real scoreDish.
    test('playing the advice produces exactly the dish it promised', () {
      final runs = [
        withBlends(['chili_oil', 'sun_dry', 'fermentation']),
        withBlends(['conserva', 'levain', 'julienne']),
        withBlends(['cold_smoke', 'winnow', 'forage']),
        withBlends(['varak', 'reduction', 'invert']),
        withBlends(['sharpen', 'mise', 'blanch']),
        withBlends(['chili_oil', 'sun_dry'], critic: kCritics['minimalist']),
        withBlends(['koji', 'brine'], critic: kCritics['traditionalist']),
      ];
      for (final run in runs) {
        for (final advice in suggestBlends(run)) {
          if (advice.result == null) {
            expect(advice.handIndexes, isEmpty, reason: 'no play, but cards were named');
            expect(advice.gain, equals(0));
            continue;
          }
          // Replay it for real on a private copy of the run, then cook what it named.
          final replay = withBlends(
            [for (final b in run.blends) b.id],
            hand: run.hand,
            critic: run.critic,
          );
          final ok = applyBlend(replay, advice.blendIndex, advice.handIndexes);
          expect(ok.error, isNull,
              reason: '${advice.blend.id}: the Coach named a play the engine refuses');

          final ctx = ctxFor(replay);
          final best = _bestScoreOf(replay.hand, ctx, replay.critic);
          expect(best, equals(advice.result!.score),
              reason: '${advice.blend.id}: promised ${advice.result!.score}, the hand it '
                  'actually builds pays $best');
          expect(advice.gain, greaterThan(0), reason: 'a row with a result must be an upgrade');
        }
      }
    });

    test('the named cards are real, in range and distinct', () {
      final run = withBlends(['levain', 'conserva', 'reduction']);
      for (final advice in suggestBlends(run)) {
        expect(advice.handIndexes.toSet().length, equals(advice.handIndexes.length));
        for (final i in advice.handIndexes) {
          expect(i, inInclusiveRange(0, run.hand.length - 1));
        }
        if (advice.result != null) {
          expect(advice.handIndexes.length, lessThanOrEqualTo(advice.blend.select));
        }
      }
    });

    // Every critic the game can put in front of a player, not a sample: a blend play that
    // ignores the demand promises a score the COOK button then refuses to pay, which is worse
    // than no advice at all because the blend has already been spent by then.
    test('the promise holds under every critic in the game', () {
      for (final critic in <Critic?>[null, ...kCritics.values, ...kMinorCritics]) {
        final run = withBlends(['chili_oil', 'conserva'], critic: critic);
        for (final advice in suggestBlends(run)) {
          if (advice.result == null) continue;
          final replay = withBlends(['chili_oil', 'conserva'], hand: run.hand, critic: critic);
          expect(applyBlend(replay, advice.blendIndex, advice.handIndexes).error, isNull,
              reason: 'critic ${critic?.id ?? 'none'} — the named play was refused');
          expect(
            _bestScoreOf(replay.hand, ctxFor(replay), critic),
            equals(advice.result!.score),
            reason: 'critic ${critic?.id ?? 'none'} — the promised score is not a legal dish',
          );
        }
      }
    });

    test('a blend that cannot help still says what it is for', () {
      // Five Spicy 9s: already a Perfect Palate, so nothing can improve it.
      final run = withBlends(
        ['chili_oil'],
        hand: [for (var i = 0; i < 5; i++) _card('spicy', 9)],
      );
      final advice = suggestBlends(run).single;
      expect(advice.result, isNull);
      expect(advice.handIndexes, isEmpty);
      expect(advice.why, isNotEmpty);
      expect(advice.why, contains('Flush'), reason: 'the authored line should still teach');
    });

    test('finds the play that reaches a secret recipe', () {
      // Four 9s and a stray: Julienne copies the 9 onto the stray for Five of a Kind, which
      // is unreachable from any pantry and is the whole reason blends exist.
      final run = withBlends(['julienne'], hand: [
        _card('spicy', 9),
        _card('sweet', 9),
        _card('sour', 9),
        _card('salty', 9),
        _card('umami', 2),
      ]);
      final advice = suggestBlends(run).single;
      expect(advice.result, isNotNull);
      expect(advice.result!.pattern, equals('five_kind'));
      expect(advice.why, contains('Five of a Kind'));
    });

    test('does not touch the run — not the RNG, not the hand, not the rack', () {
      profile = defaultProfile();
      final run = newRun(seed: 'BLEND-PURE');
      run.blends = [kBlendById['conserva']!, kBlendById['mise']!, kBlendById['levain']!];
      final hand = run.hand.map((c) => '${c.id}:${c.family}:${c.rank}').toList();
      final deck = run.deck.map((c) => c.id).toList();
      final rack = run.blends.map((b) => b.id).toList();

      profile = defaultProfile();
      final reference = newRun(seed: 'BLEND-PURE');
      final expected = rollOffers(reference).map((o) => o.id).toList();

      suggestBlends(run);

      expect(run.hand.map((c) => '${c.id}:${c.family}:${c.rank}').toList(), equals(hand));
      expect(run.deck.map((c) => c.id).toList(), equals(deck));
      expect(run.blends.map((b) => b.id).toList(), equals(rack));
      expect(rollOffers(run).map((o) => o.id).toList(), equals(expected),
          reason: 'the Coach drew from run.rng and desynced the run');
    });

    test('is deterministic — same hand, same advice', () {
      final run = withBlends(['levain', 'conserva', 'chili_oil']);
      final a = suggestBlends(run);
      final b = suggestBlends(run);
      expect(a.map((x) => x.why).toList(), equals(b.map((x) => x.why).toList()));
      expect(a.map((x) => x.handIndexes).toList(), equals(b.map((x) => x.handIndexes).toList()));
    });

    // The view memoises on this key, so anything it fails to cover becomes stale advice on
    // screen — the one thing the Coach may never show.
    group('blendAdviceKey covers every input', () {
      test('moving any of them moves the key', () {
        RunState fresh() => withBlends(['chili_oil', 'sun_dry']);
        final base = blendAdviceKey(fresh());

        final mutations = <String, void Function(RunState)>{
          'hand': (r) => r.hand[0] = r.hand[0].copyWith(rank: r.hand[0].rank == 10 ? 1 : 10),
          'hand family': (r) => r.hand[1] = r.hand[1].copyWith(family: 'umami'),
          'prized': (r) => r.hand[2] = r.hand[2].copyWith(prized: true),
          'deck': (r) => r.deck.removeLast(),
          'rack': (r) => r.blends.removeLast(),
          'utensils': (r) => r.utensils = [kUtensilById['tandoor']!],
          'kitchen level': (r) => r.kitchenLevel = 7,
          'critic': (r) => r.critic = kCritics['minimalist'],
          'city': (r) => r.cityIndex = 1,
          'first dish': (r) => r.dishesPlayed = 3,
          'last dish': (r) => r.cooksLeft = 1,
        };
        for (final e in mutations.entries) {
          final run = fresh();
          e.value(run);
          expect(blendAdviceKey(run), isNot(equals(base)),
              reason: '${e.key} changed the advice but not the key — the panel would go stale');
        }
      });

      test('an untouched run keeps the same key', () {
        final run = withBlends(['chili_oil']);
        expect(blendAdviceKey(run), equals(blendAdviceKey(run)));
      });
    });
  });

  group('cost', () {
    // The UI calls suggestDishes on every card tap, so this is a frame-budget check, not a
    // micro-benchmark. It asserts a loose ceiling only — the real number is printed.
    test('a full 8-card hand solves inside a frame', () {
      final run = _runWith(
        hand: _mixedHand(),
        utensils: [_u('iron_tawa'), _u('griddle'), _u('pressure_cooker'), _u('tandoor'), _u('clay_handi')],
        kitchenLevel: 6,
      );
      expect(run.hand.length, equals(8));
      for (var i = 0; i < 20; i++) {
        suggestDishes(run); // warm up the JIT
      }
      const reps = 200;
      final sw = Stopwatch()..start();
      for (var i = 0; i < reps; i++) {
        suggestDishes(run);
      }
      sw.stop();
      final perCall = sw.elapsedMicroseconds / reps;
      // ignore: avoid_print
      print('suggestDishes: ${(perCall / 1000).toStringAsFixed(3)} ms '
          'per 8-card hand (${sw.elapsedMicroseconds}us / $reps)');
      expect(perCall, lessThan(16000), reason: 'over one 60fps frame per card tap');
    });

    // suggestBlends is a dish search PER candidate play, so it is an order of magnitude more
    // work than the ladder. The panel memoises it on `blendAdviceKey` and so pays this once
    // per hand rather than once per tap — but a bound that quietly stops holding would put a
    // visible stall between tapping a card and the panel moving. This is the worst rack the
    // game can deal: three blends, two of them two-card verbs, one of which creates cards.
    test('a full rack of two-card blends stays inside a frame', () {
      profile = defaultProfile();
      final run = newRun(seed: 'BLEND-COST');
      run
        ..blends = [kBlendById['levain']!, kBlendById['conserva']!, kBlendById['chili_oil']!]
        ..utensils = [_u('iron_tawa'), _u('griddle'), _u('tandoor')]
        ..kitchenLevel = 6;
      expect(run.hand.length, equals(8));
      for (var i = 0; i < 5; i++) {
        suggestBlends(run);
      }
      const reps = 40;
      final sw = Stopwatch()..start();
      for (var i = 0; i < reps; i++) {
        suggestBlends(run);
      }
      sw.stop();
      final perCall = sw.elapsedMicroseconds / reps;
      // ignore: avoid_print
      print('suggestBlends: ${(perCall / 1000).toStringAsFixed(3)} ms '
          'for a 3-blend rack (${sw.elapsedMicroseconds}us / $reps)');
      expect(perCall, lessThan(16000), reason: 'over one 60fps frame for the worst rack');
    });
  });
}

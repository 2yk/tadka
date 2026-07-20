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

void main() {
  group('suggestDishes', () {
    test('never suggests a dish the critic would reject', () {
      for (final critic in <Critic?>[
        null,
        kCritics['minimalist'],
        kCritics['traditionalist'],
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
          isIn(const ['economy', 'combo', 'scaling', 'situational', 'solid']),
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
      expect(catOf('chili_oil'), equals('situational'));
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
  });
}

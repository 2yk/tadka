/// Content tests for the Festival catalog — the run's scaling engine.
///
/// Festivals are the smallest catalog in the game and the one with the most leverage:
/// [kLevelBonus] grows every recipe's base flavour AND its base heat per Kitchen level, so a
/// dish is quadratic in level and the whole target curve is derived from that (see the tuning
/// notes in `catalog.dart`). A hole here is not a missing card, it is a missing gear.
///
/// Three jobs:
///
/// 1. **Every festival's claim is true.** A Festival names a recipe on the shop card. If
///    [kLevelBonus] has no entry for that recipe — a typo, a recipe renamed, a pattern that
///    never existed — the card promises something the engine will not deliver, and nothing
///    else in the repo notices: the purchase still raises Kitchen level, so the run plays on
///    and only the shop text is a lie.
/// 2. **One festival per recipe, and every recipe a player meets has one.** Two festivals on
///    the same recipe are two shop slots making one offer under two names.
/// 3. **The ported seven are frozen at the head of the list.** `rollOffers` picks by index off
///    the seeded RNG, so appending is safe and inserting is not — the same seeded-list
///    contract that [activeUtensilCatalog] and [activeBlendCatalog] exist to protect.
@TestOn('vm')
library;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

Card _c(String family, int rank) =>
    Card(id: '${family}_$rank', family: family, rank: rank, display: kNames[family]![rank - 1]);

/// A dish that lands on each recipe a festival can name. Every entry is checked against
/// `bestPattern` before it is used, so a fixture that quietly stops being a Full House fails
/// as a fixture rather than as a mysterious scoring assertion.
final Map<String, List<Card>> _dishes = {
  'high_card': [_c('spicy', 2), _c('sweet', 5), _c('sour', 9)],
  'pair': [_c('spicy', 3), _c('sweet', 3)],
  'two_pair': [_c('spicy', 3), _c('sweet', 3), _c('sour', 5), _c('salty', 5)],
  'three_kind': [_c('spicy', 4), _c('sweet', 4), _c('sour', 4)],
  'straight': [_c('spicy', 1), _c('sweet', 2), _c('sour', 3), _c('salty', 4), _c('umami', 5)],
  'flush': [_c('spicy', 1), _c('spicy', 2), _c('spicy', 3), _c('spicy', 4), _c('spicy', 6)],
  'full_house': [
    _c('spicy', 4), _c('sweet', 4), _c('sour', 4), _c('salty', 7), _c('umami', 7),
  ],
  'four_kind': [_c('spicy', 5), _c('sweet', 5), _c('sour', 5), _c('salty', 5)],
  'straight_flush': [
    _c('spicy', 1), _c('spicy', 2), _c('spicy', 3), _c('spicy', 4), _c('spicy', 5),
  ],
  'five_kind': [
    _c('spicy', 5), _c('sweet', 5), _c('sour', 5), _c('salty', 5), _c('umami', 5),
  ],
};

/// The seven the JS build knows, restated literally — independent of [kPortedFestivals], so
/// this still fires if that list is ever edited rather than appended to.
const List<(String, String, String, int)> _ported = [
  ('fest_pair', 'pair', 'Sankranti', 3),
  ('fest_three', 'three_kind', 'Onam', 3),
  ('fest_straight', 'straight', 'Baisakhi', 3),
  ('fest_flush', 'flush', 'Holi', 3),
  ('fest_full', 'full_house', 'Diwali', 3),
  ('fest_four', 'four_kind', 'Pongal', 4),
  ('fest_sflush', 'straight_flush', 'Kumbh Mela', 4),
];

void main() {
  setUp(() {
    profile = defaultProfile();
    drainUnlockQueue();
  });

  group('catalog hygiene', () {
    test('holds 10 festivals with unique ids and names', () {
      expect(kFestivals.length, equals(10));
      expect(kFestivals.map((f) => f.id).toSet().length, equals(10), reason: 'duplicate id');
      expect(kFestivals.map((f) => f.name).toSet().length, equals(10), reason: 'duplicate name');
      expect(kFestivalById.length, equals(kFestivals.length),
          reason: 'the id index lost an entry');
    });

    test('every festival names a real recipe, exactly once', () {
      final patterns = <String>[];
      for (final f in kFestivals) {
        expect(kPatternOrder, contains(f.pattern), reason: '${f.id} names no recipe');
        patterns.add(f.pattern);
      }
      expect(patterns.toSet().length, equals(patterns.length),
          reason: 'two festivals level the same recipe — one shop offer under two names');
    });

    test('names are non-empty and costs stay in the established 3-4 band', () {
      for (final f in kFestivals) {
        expect(f.name.trim(), isNotEmpty, reason: '${f.id} has no name');
        expect(f.cost, inInclusiveRange(3, 4), reason: '${f.id} costs ${f.cost}');
      }
    });
  });

  group('coverage', () {
    test('every recipe a normal run can reach has a festival', () {
      // The nine non-secret recipes. A player who builds around Two Pair should be able to
      // buy into it in the bazaar the same way a Flush player can; before the v1.0 pass,
      // High Card and Two Pair were the two rungs with no card at all.
      final covered = kFestivals.map((f) => f.pattern).toSet();
      for (final p in kPatternOrder.where((p) => !kSecretPatterns.contains(p))) {
        expect(covered, contains(p), reason: 'no festival levels $p');
      }
    });

    test('only the reachable secret recipe is advertised', () {
      // Five of a Kind is the secret a player can actually build toward — Lievito Madre,
      // Conserva and Sun-Dry all make duplicate ranks — so naming it in the shop is a nudge.
      // Family Feast and Perfect Palate show as ??? in the Recipe Book; a Festival for a
      // recipe the player has never seen named would read as a bug, not as a secret.
      final covered = kFestivals.map((f) => f.pattern).toSet();
      expect(covered, contains('five_kind'));
      expect(covered, isNot(contains('full_family')));
      expect(covered, isNot(contains('perfect_palate')));
    });

    test('the celebrations are not all from one place any more', () {
      // The ported seven are all Indian because M0's route was Kochi/Tokyo/Naples. The route
      // is twelve cities now, and the calendar should read like it.
      expect(kFestivals.length - kPortedFestivals.length, equals(3));
      expect(
        kFestivals.skip(kPortedFestivals.length).map((f) => f.name).toList(),
        equals(['Hanami', 'Songkran', 'Inti Raymi']),
      );
    });

    test('no festival name collides with a dish name', () {
      // Both appear in the same UI. "Guelaguetza" as both Oaxaca's Full House and a Festival
      // would be two different things wearing one word.
      final dishNames = {
        for (final city in kCityPool)
          for (final p in kPatternOrder) kDishNames[city.id]![p]!,
      };
      for (final f in kFestivals) {
        expect(dishNames, isNot(contains(f.name)),
            reason: '${f.name} is already a dish name somewhere on the route');
      }
    });
  });

  group('a festival levels the recipe it claims', () {
    for (final f in kFestivals) {
      test('${f.name} — ${f.pattern}', () {
        final dish = _dishes[f.pattern];
        expect(dish, isNotNull, reason: 'no fixture dish for ${f.pattern}');

        // The fixture is self-checking: if this stops being the recipe it is filed under, the
        // scoring assertions below would be silently testing a different rung of the ladder.
        final lv1 = scoreDish(dish!, const ScoreContext());
        expect(lv1.pattern, equals(f.pattern),
            reason: 'the ${f.pattern} fixture actually scores as ${lv1.pattern}');

        // The claim on the card: buying this raises the Kitchen level, and the recipe it
        // names grows by exactly its [kLevelBonus] row — in both flavour AND heat, which is
        // what makes the scaling quadratic rather than linear.
        final lb = kLevelBonus[f.pattern];
        expect(lb, isNotNull, reason: '${f.id} names a recipe with no level bonus at all');
        expect(lb!.$1, greaterThan(0), reason: '${f.pattern} gains no flavour per level');
        expect(lb.$2, greaterThan(0), reason: '${f.pattern} gains no heat per level');

        final lv2 = scoreDish(dish, const ScoreContext(kitchenLevel: 2));
        expect(lv2.flavor - lv1.flavor, equals(lb.$1.toDouble()), reason: 'flavour per level');
        expect(lv2.heat - lv1.heat, equals(lb.$2.toDouble()), reason: 'heat per level');
        expect(lv2.score, greaterThan(lv1.score),
            reason: '${f.name} would be a purchase that changes nothing');

        // And it keeps compounding — a single level is not a one-off bump.
        final lv5 = scoreDish(dish, const ScoreContext(kitchenLevel: 5));
        expect(lv5.score, greaterThan(lv2.score));
      });
    }
  });

  group('the seeded-list contract', () {
    test('the ported seven are unchanged, in order, at the head of the catalog', () {
      expect(kPortedFestivals.length, equals(_ported.length));
      for (var i = 0; i < _ported.length; i++) {
        final f = kFestivals[i];
        expect(f.id, equals(_ported[i].$1), reason: 'ported festival $i moved');
        expect(f.pattern, equals(_ported[i].$2), reason: '${f.id} pattern retuned');
        expect(f.name, equals(_ported[i].$3), reason: '${f.id} renamed');
        expect(f.cost, equals(_ported[i].$4), reason: '${f.id} cost retuned');
      }
    });

    test('kPortedFestivals is the head of kFestivals, not a parallel copy', () {
      // If these ever drift apart, `runs_test.dart` pins the shop to a list the game no
      // longer contains and the differential guarantee quietly becomes a tautology.
      for (var i = 0; i < kPortedFestivals.length; i++) {
        expect(identical(kFestivals[i], kPortedFestivals[i]), isTrue, reason: 'entry $i');
      }
    });

    test('activeFestivalCatalog defaults to the whole catalog', () {
      expect(activeFestivalCatalog, same(kFestivals));
    });

    test('pinning the catalog really does bound what the bazaar can offer', () {
      // The seam is only worth anything if `rollOffers` honours it — this is the assertion
      // that would have caught the two times a catalog grew out from under a recorded seed.
      final portedIds = kPortedFestivals.map((f) => f.id).toSet();
      final allIds = kFestivals.map((f) => f.id).toSet();

      Set<String> offeredOver(int runs) {
        final seen = <String>{};
        for (var i = 0; i < runs; i++) {
          profile = defaultProfile();
          drainUnlockQueue();
          final run = newRun(seed: 'FEST-$i');
          for (var k = 0; k < 6; k++) {
            for (final o in rollOffers(run)) {
              if (o.kind == 'festival') seen.add(o.id);
            }
          }
        }
        return seen;
      }

      activeFestivalCatalog = kPortedFestivals;
      final pinned = offeredOver(60);
      activeFestivalCatalog = kFestivals;
      final wide = offeredOver(60);

      expect(pinned.difference(portedIds), isEmpty,
          reason: 'a pinned shop offered a festival the JS engine has never heard of');
      expect(wide.difference(allIds), isEmpty, reason: 'the shop invented a festival');
      expect(wide.difference(portedIds), isNotEmpty,
          reason: 'the v1.0 festivals can never actually be offered');
    });

    tearDown(() => activeFestivalCatalog = kFestivals);
  });
}

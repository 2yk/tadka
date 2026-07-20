/// The 8-cities-from-12 route: content completeness, the draw, and the target curve.
///
/// `runs_test.dart` proves the run machine still reproduces the JS engine on the 3-city
/// route it knows. Nothing over there can say anything about the 12-city pool — the JS
/// engine has never heard of it — so everything the expansion added is pinned here instead,
/// against properties rather than against a recorded fixture.
@TestOn('vm')
library;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

Card _c(String family, int rank) =>
    Card(id: '${family}_$rank', family: family, rank: rank, display: kNames[family]![rank - 1]);

/// One critic's demand, stated as dishes rather than as fields: what it turns away at the
/// COOK button, and what it lets through. A demand nothing can violate is not a demand.
class _CriticGate {
  const _CriticGate(this.id, {required this.allows, required this.rejects, this.debuffs});

  final String id;

  /// A dish `dishError` must accept.
  final List<Card> allows;

  /// Dishes it must turn away — one per clause, so a compound demand is fully covered.
  final List<List<Card>> rejects;

  /// For scoring demands: the family that must contribute 0 intensity. A debuff critic never
  /// rejects anything, so legality alone would pass it while it silently did nothing.
  final String? debuffs;
}

/// Walks a run's route by clearing every service, and reports what it saw.
///
/// Drives the real state machine — `advance` and `isFinalService` decide when the route
/// ends, which is the thing under test — rather than reading `run.route` and trusting it.
({List<String> cities, int services, String status}) _walk(RunState run) {
  final cities = <String>[];
  var services = 0;
  while (run.status == 'playing' && services < 200) {
    if (run.serviceIndex == 0) cities.add(cityOf(run).id);
    services++;
    if (isFinalService(run)) {
      run.status = 'won';
      break;
    }
    advance(run);
  }
  return (cities: cities, services: services, status: run.status);
}

void main() {
  setUp(() {
    profile = defaultProfile();
    drainUnlockQueue();
  });

  group('the city pool is complete', () {
    test('holds 12 cities with unique ids', () {
      expect(kCityPool.length, equals(12));
      expect(kCityPool.map((c) => c.id).toSet().length, equals(12));
    });

    test('every city has a palate, and it uses one of the three engine-known shapes', () {
      for (final city in kCityPool) {
        final p = kPalates[city.id];
        expect(p, isNotNull, reason: '${city.id} has no palate');
        expect(p!.city, equals(city.id), reason: '${city.id} palate is keyed wrong');
        expect(p.label, isNotEmpty, reason: '${city.id} palate has no player-facing label');

        // A fourth shape would mean an engine change in cardContribution / scoreDish, which
        // is the line this expansion was not allowed to cross.
        final shapes = [
          p.perCardFlavorPctFamily != null,
          p.perCardHeatFamily != null,
          p.dishFlavorPattern != null,
        ].where((x) => x).length;
        expect(shapes, equals(1), reason: '${city.id} palate must use exactly one shape');

        if (p.perCardFlavorPctFamily != null) {
          expect(kFamilies, contains(p.perCardFlavorPctFamily), reason: city.id);
          expect(p.perCardFlavorPct, isNotNull, reason: '${city.id} has a family but no pct');
        }
        if (p.perCardHeatFamily != null) {
          expect(kFamilies, contains(p.perCardHeatFamily), reason: city.id);
          expect(p.perCardHeatAdd, isNotNull, reason: '${city.id} has a family but no heat');
        }
        if (p.dishFlavorPattern != null) {
          expect(kPatternOrder, contains(p.dishFlavorPattern), reason: city.id);
          expect(p.dishFlavorAdd, isNotNull, reason: '${city.id} has a pattern but no flavor');
        }
      }
    });

    test('every city names a critic that exists', () {
      for (final city in kCityPool) {
        expect(kCritics[city.critic], isNotNull,
            reason: '${city.id} names critic "${city.critic}", which is not in kCritics');
      }
    });

    test('every city names all 12 recipes', () {
      for (final city in kCityPool) {
        for (final pattern in kPatternOrder) {
          final name = kDishNames[city.id]?[pattern];
          expect(name, isNotNull,
              reason: '${city.id} has no dish name for "$pattern" — the signature mechanic '
                  'is the whole point, so a hole here is a shipped bug');
          expect(name, isNotEmpty, reason: '${city.id}.$pattern is blank');
        }
        // No duplicates within a city: 12 recipes, 12 distinguishable dishes.
        final names = kPatternOrder.map((p) => kDishNames[city.id]![p]).toSet();
        expect(names.length, equals(kPatternOrder.length),
            reason: '${city.id} reuses a dish name across recipes');
      }
    });

    test('a missing dish name throws rather than falling back', () {
      // The failure mode this guards: a city added to the pool without its dish table, and
      // the player being shown "straight_flush" at the best moment of their run.
      expect(() => dishName('atlantis', 'flush'), throwsStateError);
      expect(() => dishName('kochi', 'sandwich'), throwsStateError);
      for (final city in kCityPool) {
        for (final pattern in kPatternOrder) {
          expect(() => dishName(city.id, pattern), returnsNormally);
        }
      }
    });

    test('every critic states a demand the engine can actually enforce', () {
      for (final c in [...kCritics.values, ...kMinorCritics]) {
        expect(c.rule, isNotEmpty, reason: '${c.id} has no player-facing rule');
        final demands = [c.maxCards, c.minCards, c.debuff, c.requireFamily]
            .where((x) => x != null)
            .length;
        expect(demands, greaterThanOrEqualTo(1), reason: '${c.id} demands nothing');
        if (c.debuff != null) expect(kFamilies, contains(c.debuff), reason: c.id);
        if (c.requireFamily != null) expect(kFamilies, contains(c.requireFamily), reason: c.id);
        // A cap below 3 would hold the player under Three of a Kind even on a Lunch Rush.
        if (c.maxCards != null) expect(c.maxCards, greaterThanOrEqualTo(3), reason: c.id);
      }
    });
  });

  group('every critic demands something a dish can actually fail', () {
    // The field-level check above proves a critic *states* a demand. It cannot tell a demand
    // apart from a typo: `requireFamily: 'ummami'` has a demand, a rule string and no effect
    // whatsoever on play. These cases run the real `dishError` and the real `scoreDish`.
    // Built lazily rather than as a const: `_c` reads display names out of [kNames].
    final table = <_CriticGate>[
      _CriticGate('minimalist',
          allows: [_c('spicy', 3), _c('sweet', 4), _c('sour', 5)],
          rejects: [
            [_c('spicy', 3), _c('sweet', 4), _c('sour', 5), _c('salty', 6)],
          ]),
      _CriticGate('gourmand',
          allows: [_c('spicy', 3), _c('sweet', 4), _c('sour', 5), _c('salty', 6)],
          rejects: [
            [_c('spicy', 3), _c('sweet', 4), _c('sour', 5)],
          ]),
      _CriticGate('firebrand',
          allows: [_c('spicy', 3), _c('sweet', 4)],
          rejects: [
            [_c('umami', 3), _c('sweet', 4)],
          ]),
      _CriticGate('brine_baron',
          allows: [_c('salty', 3), _c('sweet', 4)],
          rejects: [
            [_c('umami', 3), _c('sweet', 4)],
          ]),
      _CriticGate('traditionalist',
          allows: [_c('sweet', 3), _c('sour', 4)], rejects: [], debuffs: 'sweet'),
      _CriticGate('austere',
          allows: [_c('umami', 3), _c('sour', 4)], rejects: [], debuffs: 'umami'),
      _CriticGate('ascetic',
          allows: [_c('spicy', 3), _c('sour', 4)], rejects: [], debuffs: 'spicy'),

      // --- v1.0 pass ---
      // Compound: one rejection per clause, or half the demand goes untested.
      _CriticGate('connoisseur',
          allows: [_c('umami', 3), _c('sweet', 4), _c('sour', 5)],
          rejects: [
            [_c('umami', 3), _c('sweet', 4)], // 2 cards — under the floor
            [_c('spicy', 3), _c('sweet', 4), _c('sour', 5)], // no Umami
          ]),
      _CriticGate('maximalist',
          allows: [
            _c('spicy', 3), _c('sweet', 4), _c('sour', 5), _c('salty', 6), _c('umami', 7),
          ],
          rejects: [
            [_c('spicy', 3), _c('sweet', 4), _c('sour', 5), _c('salty', 6)],
          ]),
      _CriticGate('contrarian',
          allows: [_c('sour', 3), _c('sweet', 4)], rejects: [], debuffs: 'sour'),
      _CriticGate('perfectionist',
          allows: [_c('salty', 3), _c('sweet', 4), _c('sour', 5)],
          rejects: [
            [_c('salty', 3), _c('sweet', 4)],
          ],
          debuffs: 'salty'),
    ];

    test('every major critic has a case', () {
      expect(table.map((g) => g.id).toSet(), equals(kCritics.keys.toSet()),
          reason: 'a critic with no gate case — add one to `table`');
      expect(table.length, equals(kCritics.length), reason: 'duplicate gate case');
    });

    for (final g in table) {
      final c = kCritics[g.id]!;
      test('${g.id} — ${c.rule}', () {
        expect(dishError(g.allows, c), isNull,
            reason: '${g.id} turned away a dish that meets its rule');
        for (var i = 0; i < g.rejects.length; i++) {
          expect(dishError(g.rejects[i], c), isNotNull,
              reason: '${g.id} accepted illegal dish $i — a clause of its rule does nothing');
          // The same dish must be fine with no critic present, or the case proves nothing.
          expect(dishError(g.rejects[i], null), isNull, reason: '${g.id} miss $i is not a legal dish');
        }
        final fam = g.debuffs;
        if (fam != null) {
          // A debuff is invisible to dishError: it lands in cardContribution. Score the same
          // dish with and without the critic and require the debuffed family to go to zero.
          // Three cards, so the dish is legal under every floor in the pool as well — a
          // debuff critic that also has a minCards clause is scored on a dish it would allow.
          final other = fam == 'umami' ? 'sour' : 'umami';
          final dish = [_c(fam, 9), _c(other, 9), _c(other, 8)];
          expect(dishError(dish, c), isNull, reason: '${g.id}: the debuff case must be legal');
          final free = scoreDish(dish, const ScoreContext());
          final judged = scoreDish(dish, ScoreContext(critic: c));
          expect(free.scoring.map((x) => x.family), contains(fam),
              reason: '${g.id}: the debuffed card is not even a scoring card');
          expect(judged.flavor, equals(free.flavor - 9),
              reason: '${g.id} debuffs $fam, but a rank-9 $fam card still scored');
        } else {
          expect(c.debuff, isNull, reason: '${g.id} carries a debuff with no case for it');
        }
      });
    }
  });

  group('the critic pool covers the cities without orphans', () {
    test('every critic is somebody\'s Food Critic, and every city names a real one', () {
      // Both directions at once. Content that no city can roll is content nobody will ever
      // see, which is the quieter half of "does this feel finished".
      expect(kCityPool.map((c) => c.critic).toSet(), equals(kCritics.keys.toSet()));
    });

    test('the finale candidate set is byte-for-byte what drawRoute has always drawn from', () {
      // THE seeded-list trap, reached by a road that is not a `pick` over a catalog.
      // `drawRoute` picks the last city from those whose critic passes criticCanCloseARun, so
      // that filtered list's contents and ORDER decide every existing seed's finale. Swapping
      // a city's critic for one with a different verdict re-rolls all of them silently.
      final candidates = kCityPool
          .where((c) => c.id != kStartCityId && criticCanCloseARun(kCritics[c.critic]!))
          .map((c) => c.id)
          .toList();
      expect(candidates,
          equals(['seoul', 'tokyo', 'beirut', 'marrakech', 'naples', 'oaxaca', 'lima', 'new_orleans']));
    });

    test('the v1.0 critics keep the invariant their host city was placed under', () {
      // Addis Ababa was the Firebrand's second home and must stay unable to close a run;
      // the other three took over from critics that could, and must stay able to.
      expect(criticCanCloseARun(kCritics['connoisseur']!), isFalse,
          reason: 'a required family can make a Flush impossible — it cannot end a run');
      for (final id in ['maximalist', 'contrarian', 'perfectionist']) {
        expect(criticCanCloseARun(kCritics[id]!), isTrue, reason: '$id took over a finale city');
      }
      // The Maximalist is the reason the invariant is about ceilings and not about severity:
      // it is a harsher demand than the Gourmand it replaced, and still perfectly safe,
      // because a floor of 5 leaves the whole recipe ladder reachable.
      expect(kCritics['maximalist']!.maxCards, isNull);
      expect(kCritics['maximalist']!.minCards, equals(5));
    });
  });

  group('drawRoute', () {
    test('visits exactly 8 cities, opens on Kochi, and never repeats', () {
      for (final seed in ['ROUTE-A', 'ROUTE-B', 'SPICE-KOCHI', 'x', '']) {
        final route = drawRoute(seed);
        expect(route.length, equals(kRouteLength), reason: seed);
        expect(route.first.id, equals(kStartCityId), reason: '$seed does not open on Kochi');
        expect(route.map((c) => c.id).toSet().length, equals(kRouteLength),
            reason: '$seed repeats a city');
        for (final c in route) {
          expect(kCityDefById[c.id], isNotNull, reason: '$seed drew "${c.id}", not in the pool');
        }
      }
    });

    test('whatever ends the run cannot cap the recipe ladder', () {
      // The generalized Naples fix. A finale critic with a card cap or a required family
      // puts a ceiling on the best reachable recipe, and no Kitchen level clears a target
      // that has outgrown the ladder — which is why rolling the Minimalist onto Naples'
      // 50k was unwinnable at any level.
      for (var i = 0; i < 400; i++) {
        final route = drawRoute('FINALE-$i');
        final critic = kCritics[route.last.critic]!;
        expect(criticCanCloseARun(critic), isTrue,
            reason: 'seed FINALE-$i ends on ${route.last.id} with ${critic.name}');
      }
      expect(criticCanCloseARun(kCritics['minimalist']!), isFalse);
      expect(criticCanCloseARun(kCritics['firebrand']!), isFalse);
      expect(criticCanCloseARun(kCritics['traditionalist']!), isTrue);
    });

    test('the Minimalist only ever appears on the tutorial city', () {
      // Kochi's 1200 boss is tuned against the 3-card cap. Any later slot assumes the whole
      // recipe ladder is available, so the cap must not travel.
      for (final city in kCityPool) {
        if (city.critic == 'minimalist') expect(city.id, equals(kStartCityId));
      }
      for (var i = 0; i < 200; i++) {
        for (final c in drawRoute('MIN-$i').skip(1)) {
          expect(c.critic, isNot(equals('minimalist')), reason: 'seed MIN-$i put it on ${c.id}');
        }
      }
    });

    test('is deterministic — the same seed draws the same route', () {
      for (final seed in ['DET-1', 'DET-2', 'SPICE-QQQQQ']) {
        final ids = drawRoute(seed).map((c) => c.id).toList();
        expect(drawRoute(seed).map((c) => c.id).toList(), equals(ids));
        expect(newRun(seed: seed).route.map((c) => c.id).toList(), equals(ids),
            reason: 'newRun must place the same route drawRoute does');
        expect(newRun(seed: seed, stake: 7, deckId: 'royal').route.map((c) => c.id).toList(),
            equals(ids),
            reason: 'the route is a function of the seed alone, not of stake or deck');
      }
    });

    test('different seeds draw different routes', () {
      final seen = {for (var i = 0; i < 60; i++) drawRoute('VARY-$i').map((c) => c.id).join()};
      expect(seen.length, greaterThan(40), reason: 'routes barely vary across seeds');
    });

    test('the draw runs off its own RNG and does not disturb the run stream', () {
      // THE property that lets the JS traces survive an 8-city route. If route selection
      // drew from `run.rng`, every recorded seed would deal a different opening hand and
      // roll a different shop, and the differential tests would have had to be regenerated
      // against Dart — which would only prove Dart matches Dart.
      for (final seed in ['SPICE-KOCHI', 'SPICE-TOKYO', 'SPICE-NAPLE']) {
        for (final deck in ['home', 'royal']) {
          final drawn = newRun(seed: seed, deckId: deck);
          profile = defaultProfile();
          drainUnlockQueue();
          final pinned = newRun(seed: seed, deckId: deck, route: kCities);
          expect(pinned.hand.map((c) => c.id).toList(),
              equals(drawn.hand.map((c) => c.id).toList()),
              reason: '$seed/$deck deals a different hand once a route is supplied');
          expect(pinned.naplesCritic, equals(drawn.naplesCritic), reason: '$seed/$deck');
          expect(pinned.utensils.map((u) => u.id).toList(),
              equals(drawn.utensils.map((u) => u.id).toList()),
              reason: "$seed/$deck rolled a different Royal Kitchen Rare");
        }
      }
    });
  });

  group('the run walks the whole route', () {
    test('a drawn run plays 8 cities over 24 services and then wins', () {
      for (final seed in ['WALK-1', 'WALK-2', 'WALK-3']) {
        profile = defaultProfile();
        drainUnlockQueue();
        final run = newRun(seed: seed);
        final w = _walk(run);
        expect(w.services, equals(kRouteLength * 3), reason: seed);
        expect(w.cities.length, equals(kRouteLength), reason: seed);
        expect(w.cities.toSet().length, equals(kRouteLength), reason: '$seed repeated a city');
        expect(w.cities.first, equals(kStartCityId), reason: seed);
        expect(w.status, equals('won'), reason: seed);
        expect(w.cities, equals(run.route.map((c) => c.id).toList()), reason: seed);
      }
    });

    test('a run pinned to the 3-city JS route still ends after 9 services', () {
      // The seam works in both directions: route length is read from the run, not assumed.
      final run = newRun(seed: 'WALK-1', route: kCities);
      final w = _walk(run);
      expect(w.services, equals(9));
      expect(w.cities, equals(['kochi', 'tokyo', 'naples']));
      expect(w.status, equals('won'));
    });

    test('finalBaseTarget follows the route rather than Naples', () {
      final drawn = newRun(seed: 'FBT-1');
      expect(drawn.finalBaseTarget, equals(drawn.route.last.targets[2]));
      expect(drawn.finalBaseTarget, equals(serviceTarget(kRouteLength * 3 - 1)));
      final pinned = newRun(seed: 'FBT-1', route: kCities);
      expect(pinned.finalBaseTarget, equals(50000), reason: 'the pinned route still ends at Naples');
    });

    test('every service on a drawn route can name its dish and read its palate', () {
      // Walks the whole route touching the two per-city lookups the UI does every service.
      final run = newRun(seed: 'LOOKUP-1');
      var services = 0;
      while (run.status == 'playing' && services < 200) {
        services++;
        final city = cityOf(run);
        expect(kPalates[city.id], isNotNull, reason: 'no palate at ${city.id}');
        for (final p in kPatternOrder) {
          expect(() => dishName(city.id, p), returnsNormally, reason: '${city.id}.$p');
        }
        expect(run.target, greaterThan(0));
        if (isFinalService(run)) break;
        advance(run);
      }
      expect(services, equals(kRouteLength * 3));
    });

    test('the Dinner Rush minor critic pool is pinnable per run', () {
      // Habanero and up put a minor critic on the Dinner Rush. The pool grew, so the traces
      // pass the ported four; live play gets all of them.
      final wide = newRun(seed: 'MINOR-1', stake: 6);
      expect(wide.minorCritics, equals(kMinorCritics));
      final pinned = newRun(seed: 'MINOR-1', stake: 6, minorCritics: kPortedMinorCritics);
      expect(pinned.minorCritics.length, equals(4));
      expect(kMinorCritics.length, greaterThan(kPortedMinorCritics.length));
      // The ported four must stay the first four, in order: Rng.pick indexes by position.
      expect(kMinorCritics.take(kPortedMinorCritics.length).map((c) => c.id).toList(),
          equals(kPortedMinorCritics.map((c) => c.id).toList()));
    });
  });

  group('the target curve', () {
    test('rises at every one of the 24 services', () {
      final targets = [
        for (var slot = 0; slot < kRouteLength; slot++) ...routeTargets(slot),
      ];
      expect(targets.length, equals(kRouteLength * 3));
      for (var i = 1; i < targets.length; i++) {
        expect(targets[i], greaterThan(targets[i - 1]),
            reason: 'service $i (${targets[i]}) does not exceed service ${i - 1} '
                '(${targets[i - 1]}) — the two-significant-figure rounding must never '
                'flatten or invert a step');
      }
    });

    test('opens on Kochi\'s hand-tuned triple', () {
      expect(routeTargets(0), equals(kTutorialTargets));
      expect(routeTargets(0), equals([300, 800, 1200]));
    });

    test('a real run\'s targets rise across the whole route, at every stake', () {
      for (var stake = 1; stake <= 8; stake++) {
        profile = defaultProfile();
        drainUnlockQueue();
        final run = newRun(seed: 'CURVE-$stake', stake: stake);
        var last = 0;
        var services = 0;
        while (run.status == 'playing' && services < 200) {
          services++;
          expect(run.target, greaterThan(last),
              reason: 'stake $stake, service $services: ${run.target} after $last');
          last = run.target;
          if (isFinalService(run)) break;
          advance(run);
        }
        expect(services, equals(kRouteLength * 3), reason: 'stake $stake');
      }
    });

    test('the within-city spread narrows as the route goes on', () {
      // Early on a single bazaar can double a build, so a boss four times the Lunch is fair.
      // By the last city a bazaar moves you a few percent, and the same spread would be
      // unclearable. This is a property of the quadratic, not a separate knob — if it ever
      // stops holding, the curve has been replaced by something that needs re-simming.
      var previous = double.infinity;
      for (var slot = 0; slot < kRouteLength; slot++) {
        final t = routeTargets(slot);
        final spread = t[2] / t[0];
        expect(spread, lessThan(previous), reason: 'slot $slot spread $spread');
        expect(spread, greaterThan(1.0), reason: 'slot $slot has no difficulty ramp at all');
        previous = spread;
      }
    });

    test('niceTarget rounds to two significant figures', () {
      expect(niceTarget(22990), equals(23000));
      expect(niceTarget(17987), equals(18000));
      expect(niceTarget(4750), equals(4800));
      expect(niceTarget(300), equals(300));
      expect(niceTarget(0), equals(0));
    });
  });
}

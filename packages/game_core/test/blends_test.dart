/// Tests for blend application — the six card rewrites, and the payoff they unlock.
///
/// Two halves, and the second is the point of the feature. The first pins each blend's exact
/// effect on the hand, including the refusal and the bounds checks the web build has no need
/// for. The second proves the secret recipes are actually reachable: `five_kind`,
/// `full_family` and `perfect_palate` are scored by the engine but cannot be dealt, so until
/// blends could be played they were dead code in `bestPattern` and dead entries in the Recipe
/// Book. Each of those tests takes a hand one blend short of a secret recipe and shows the
/// pattern climbing, so a regression that breaks the route shows up as a named failure rather
/// than as a recipe nobody notices is missing.
///
/// The `blend vectors` group is the differential half, replaying cases recorded from §UI's
/// own `useBlend` by `tools/gen-vectors.mjs`. Those own the question "does this match the web
/// build"; the hand-written tests above own "is this the behaviour we meant".
///
/// A note on duplicate ids: Sun-Dry mints `<id>_copy`, so two Sun-Drys played on the same
/// card produce two cards with the same id. Nothing in `game_core` reads `Card.id` — pattern
/// detection keys off rank and family, and `doCook`/`doSwap` address the hand by index — so
/// the collision is inert, and matching the web build matters more than a tidier id scheme.
/// The `sun_dry twice on the same card` vector locks that behaviour in.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// A pantry-realistic card. Display names come from the real catalog so the prefix
/// assertions ("Chili Fig") read as what a player would actually see.
Card _c(String family, int rank, {String suffix = ''}) => Card(
  id: '${family}_$rank$suffix',
  family: family,
  rank: rank,
  display: kNames[family]![rank - 1],
);

/// A run positioned with a fixture hand, deck and blend inventory.
///
/// `newRun` is used rather than a bare state object so the run is one the game could really
/// be in; every field replaced afterwards is public state the reducer itself writes.
RunState _run({
  required List<Card> hand,
  List<Card> deck = const [],
  List<String> blends = const [],
  String seed = 'BLEND-TEST',
}) {
  profile = defaultProfile();
  final run = newRun(seed: seed);
  run.hand = List<Card>.of(hand);
  run.deck = List<Card>.of(deck);
  run.blends = blends.map((id) => kBlendById[id]!).toList();
  return run;
}

/// Every observable field of a card, so "unchanged" means unchanged and not merely same-length.
String _sig(Card c) => '${c.id}|${c.family}|${c.rank}|${c.display}|${c.prized}';

List<String> _sigs(List<Card> cards) => cards.map(_sig).toList();

/// The recipe's base flavour and heat at [level] — [kRecipe] grown by [kLevelBonus].
(double, double) _leveledBase(String pattern, int level) {
  final base = kRecipe[pattern]!;
  final bonus = kLevelBonus[pattern]!;
  return (
    (base.$1 + (level - 1) * bonus.$1).toDouble(),
    (base.$2 + (level - 1) * bonus.$2).toDouble(),
  );
}

Card _fromJson(Map<String, dynamic> j) => Card(
  id: j['id'] as String,
  family: j['family'] as String,
  rank: j['rank'] as int,
  display: j['display'] as String,
  prized: j['prized'] as bool,
);

List<Card> _cardsFromJson(List<dynamic> j) =>
    j.map((e) => _fromJson(e as Map<String, dynamic>)).toList();

void main() {
  group('each blend rewrites the hand exactly', () {
    test('chili_oil turns the targets Spicy and prefixes the display', () {
      final run = _run(
        hand: [_c('spicy', 8), _c('sweet', 4), _c('umami', 6)],
        blends: ['chili_oil'],
      );
      final out = applyBlend(run, 0, [1, 2]);

      expect(out.error, isNull);
      expect(out.ok, isTrue);
      expect(run.blends, isEmpty, reason: 'the blend is consumed on success');
      expect(_sigs(run.hand), equals([
        'spicy_8|spicy|8|Scotch Bonnet|false', // untouched
        'sweet_4|spicy|4|Chili Fig|false', // family and display rewritten, rank and id kept
        'umami_6|spicy|6|Chili Soy Bean|false',
      ]));
    });

    test('sea_salt turns the targets Salty and prefixes the display', () {
      final run = _run(
        hand: [_c('umami', 9), _c('sweet', 7), _c('sour', 3)],
        blends: ['sea_salt'],
      );
      final out = applyBlend(run, 0, [0, 1]);

      expect(out.ok, isTrue);
      expect(run.blends, isEmpty);
      expect(_sigs(run.hand), equals([
        'umami_9|salty|9|Salted Aged Cheese|false',
        'sweet_7|salty|7|Salted Condensed Milk|false',
        'sour_3|sour|3|Tamarind|false',
      ]));
    });

    test('fermentation adds 3 intensity to one card', () {
      final run = _run(
        hand: [_c('sour', 4), _c('sour', 8)],
        blends: ['fermentation'],
      );
      final out = applyBlend(run, 0, [0]);

      expect(out.ok, isTrue);
      expect(run.blends, isEmpty);
      expect(_sigs(run.hand), equals([
        'sour_4|sour|7|Green Mango|false', // display does not follow the rank
        'sour_8|sour|8|Sumac|false',
      ]));
    });

    test('fermentation caps intensity at 10', () {
      final run = _run(hand: [_c('umami', 8), _c('umami', 10)], blends: ['fermentation', 'fermentation']);

      expect(applyBlend(run, 0, [0]).ok, isTrue);
      expect(run.hand[0].rank, equals(10), reason: '8 + 3 clamps to 10, not 11');

      expect(applyBlend(run, 0, [1]).ok, isTrue);
      expect(run.hand[1].rank, equals(10), reason: 'already at the cap');
      expect(run.blends, isEmpty);
    });

    test('sharpen sets one card to intensity 10', () {
      final run = _run(
        hand: [_c('salty', 1), _c('salty', 5)],
        blends: ['sharpen'],
      );
      final out = applyBlend(run, 0, [0]);

      expect(out.ok, isTrue);
      expect(run.blends, isEmpty);
      expect(_sigs(run.hand), equals([
        'salty_1|salty|10|Sea Salt|false',
        'salty_5|salty|5|Miso|false',
      ]));
    });

    test('sun_dry appends a copy with a _copy id', () {
      final run = _run(
        hand: [_c('spicy', 6), _c('sweet', 2)],
        blends: ['sun_dry'],
      );
      final out = applyBlend(run, 0, [0]);

      expect(out.ok, isTrue);
      expect(run.blends, isEmpty);
      expect(run.hand.length, equals(3), reason: 'the copy is appended, not swapped in');
      expect(_sigs(run.hand), equals([
        'spicy_6|spicy|6|Red Chili|false',
        'sweet_2|sweet|2|Honey|false',
        'spicy_6_copy|spicy|6|Red Chili|false',
      ]));
    });

    test('mise draws 2 from the deck and needs no selection', () {
      final run = _run(
        hand: [_c('spicy', 1)],
        deck: [_c('sweet', 3), _c('sour', 4), _c('salty', 5)],
        blends: ['mise'],
      );
      final out = applyBlend(run, 0, const []);

      expect(out.error, isNull, reason: 'select is 0, so an empty selection is legal');
      expect(out.ok, isTrue);
      expect(run.blends, isEmpty);
      expect(_sigs(run.hand), equals([
        'spicy_1|spicy|1|Paprika|false',
        'sweet_3|sweet|3|Date|false',
        'sour_4|sour|4|Green Mango|false',
      ]));
      expect(run.deck.map((c) => c.id).toList(), equals(['salty_5']),
          reason: 'drawn off the top, in deck order');
    });

    test('mise draws only what is left and does not throw on a short deck', () {
      final one = _run(hand: [_c('spicy', 1)], deck: [_c('sweet', 3)], blends: ['mise']);
      expect(applyBlend(one, 0, const []).ok, isTrue);
      expect(one.hand.length, equals(2));
      expect(one.deck, isEmpty);

      final none = _run(hand: [_c('spicy', 1)], blends: ['mise']);
      expect(applyBlend(none, 0, const []).ok, isTrue);
      expect(none.hand.length, equals(1), reason: 'nothing to draw');
      expect(none.blends, isEmpty, reason: 'still consumed — the web build spends it either way');
    });

    test('selections past the blend\'s select count are ignored, not refused', () {
      final run = _run(
        hand: [_c('sweet', 5), _c('sour', 5), _c('salty', 5), _c('umami', 5)],
        blends: ['chili_oil'],
      );
      final out = applyBlend(run, 0, [0, 1, 2, 3]);

      expect(out.ok, isTrue);
      expect(run.hand.map((c) => c.family).toList(), equals(['spicy', 'spicy', 'salty', 'umami']),
          reason: 'chili_oil selects 2, so only the first two chosen are converted');
    });

    test('targets follow selection order, not hand order', () {
      final run = _run(
        hand: [_c('spicy', 1), _c('spicy', 2), _c('spicy', 3), _c('spicy', 4)],
        blends: ['sea_salt'],
      );
      expect(applyBlend(run, 0, [3, 0]).ok, isTrue);
      expect(run.hand.map((c) => c.family).toList(),
          equals(['salty', 'spicy', 'spicy', 'salty']));
    });

    test('playing one of several blends consumes only that one', () {
      final run = _run(
        hand: [_c('sweet', 2), _c('sour', 2)],
        blends: ['chili_oil', 'sharpen', 'mise'],
      );
      expect(applyBlend(run, 1, [0]).ok, isTrue);
      expect(run.blends.map((b) => b.id).toList(), equals(['chili_oil', 'mise']));
      expect(run.hand[0].rank, equals(10), reason: 'the Whetstone fired, not its neighbours');
    });
  });

  group('refusals leave the run untouched', () {
    test('a select > 0 blend with nothing chosen is refused and not consumed', () {
      final run = _run(
        hand: [_c('sweet', 5), _c('sour', 5)],
        blends: ['chili_oil', 'sharpen'],
      );
      final handBefore = _sigs(run.hand);

      final out = applyBlend(run, 0, const []);

      expect(out.error, equals('Select ingredient(s) first, then tap the blend'));
      expect(out.ok, isFalse);
      expect(run.blends.map((b) => b.id).toList(), equals(['chili_oil', 'sharpen']),
          reason: 'a refused tap must be free');
      expect(_sigs(run.hand), equals(handBefore));
    });

    test('an out-of-range blend index errors instead of throwing', () {
      for (final bad in [1, 5, -1, -99]) {
        final run = _run(hand: [_c('sweet', 5)], blends: ['sharpen']);
        final handBefore = _sigs(run.hand);

        final out = applyBlend(run, bad, [0]);

        expect(out.error, isNotNull, reason: 'blend index $bad');
        expect(out.ok, isFalse, reason: 'blend index $bad');
        expect(run.blends.map((b) => b.id).toList(), equals(['sharpen']), reason: 'blend index $bad');
        expect(_sigs(run.hand), equals(handBefore), reason: 'blend index $bad');
      }
    });

    test('an out-of-range hand index errors instead of throwing', () {
      for (final bad in [
        [3],
        [99],
        [-1],
        [0, 7],
      ]) {
        final run = _run(
          hand: [_c('sweet', 5), _c('sour', 5), _c('salty', 5)],
          blends: ['chili_oil'],
        );
        final handBefore = _sigs(run.hand);

        final out = applyBlend(run, 0, bad);

        expect(out.error, isNotNull, reason: 'hand indexes $bad');
        expect(out.ok, isFalse, reason: 'hand indexes $bad');
        expect(run.blends.map((b) => b.id).toList(), equals(['chili_oil']), reason: 'hand indexes $bad');
        expect(_sigs(run.hand), equals(handBefore),
            reason: 'hand indexes $bad — a bad index must not half-apply the blend');
      }
    });

    test('an empty hand refuses rather than throwing', () {
      final run = _run(hand: const [], blends: ['sun_dry']);
      final out = applyBlend(run, 0, [0]);
      expect(out.error, isNotNull);
      expect(run.blends.length, equals(1));
    });
  });

  // -------------------------------------------------------------------------
  // The payoff: the three secret recipes, each one blend away.
  // -------------------------------------------------------------------------
  group('secret recipes become reachable', () {
    test('sun_dry duplicates into five of a rank', () {
      final run = _run(
        hand: [_c('spicy', 10), _c('sweet', 10), _c('sour', 10), _c('salty', 10)],
        blends: ['sun_dry'],
      );
      expect(bestPattern(run.hand).pattern, equals('four_kind'),
          reason: 'four of a rank is the ceiling without a blend');

      expect(applyBlend(run, 0, [0]).ok, isTrue);

      const level = 2;
      final res = scoreDish(run.hand, const ScoreContext(kitchenLevel: level));
      final (baseF, baseH) = _leveledBase('five_kind', level);

      expect(res.pattern, equals('five_kind'));
      expect(res.scoring.length, equals(5), reason: 'all five cards score');
      expect(res.flavor, equals(baseF + 50), reason: 'leveled base + five rank-10 intensities');
      expect(res.heat, equals(baseH));
      expect(res.score, equals(((baseF + 50) * baseH).floor()));
      expect(res.score, equals(4000), reason: 'base 200 flavor x 16 heat, +50 intensity');
    });

    test('chili_oil completes a one-family full house', () {
      final run = _run(
        hand: [
          _c('spicy', 8),
          _c('spicy', 8, suffix: '_b'),
          _c('spicy', 8, suffix: '_c'),
          _c('sweet', 4),
          _c('sour', 4),
        ],
        blends: ['chili_oil'],
      );
      expect(bestPattern(run.hand).pattern, equals('full_house'),
          reason: 'the mixed families cap it at a Full House');

      expect(applyBlend(run, 0, [3, 4]).ok, isTrue);
      expect(run.hand.map((c) => c.family).toSet(), equals({'spicy'}));

      const level = 3;
      final res = scoreDish(run.hand, const ScoreContext(kitchenLevel: level));
      final (baseF, baseH) = _leveledBase('full_family', level);

      expect(res.pattern, equals('full_family'));
      expect(res.flavor, equals(baseF + 32), reason: 'leveled base + 8+8+8+4+4');
      expect(res.heat, equals(baseH));
      expect(res.score, equals(((baseF + 32) * baseH).floor()));
      expect(res.score, equals(8892), reason: 'base 310 flavor x 26 heat, +32 intensity');
    });

    test('chili_oil completes a one-family five of a rank', () {
      final run = _run(
        hand: [
          _c('spicy', 6),
          _c('spicy', 6, suffix: '_b'),
          _c('spicy', 6, suffix: '_c'),
          _c('sweet', 6),
          _c('sour', 6),
        ],
        blends: ['chili_oil'],
      );
      expect(bestPattern(run.hand).pattern, equals('five_kind'),
          reason: 'five of a rank already, but the families are mixed');

      expect(applyBlend(run, 0, [3, 4]).ok, isTrue);

      const level = 4;
      final res = scoreDish(run.hand, const ScoreContext(kitchenLevel: level));
      final (baseF, baseH) = _leveledBase('perfect_palate', level);

      expect(res.pattern, equals('perfect_palate'));
      expect(res.flavor, equals(baseF + 30), reason: 'leveled base + five rank-6 intensities');
      expect(res.heat, equals(baseH));
      expect(res.score, equals(((baseF + 30) * baseH).floor()));
      expect(res.score, equals(19760), reason: 'base 490 flavor x 38 heat, +30 intensity');
    });

    test('every secret recipe in the catalog has a blend route proven above', () {
      // Guards against a catalog gaining a fourth secret that nothing can reach.
      expect(kSecretPatterns, equals(['five_kind', 'full_family', 'perfect_palate']));
    });
  });

  // -------------------------------------------------------------------------
  // Differential: the web build's own useBlend, replayed.
  // -------------------------------------------------------------------------
  group('blend vectors (differential against the web build)', () {
    final file = File('test/vectors.json');
    if (!file.existsSync()) {
      throw StateError('test/vectors.json missing — regenerate with: node tools/gen-vectors.mjs');
    }
    final v = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final cases = (v['blends'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
    if (cases == null) {
      throw StateError('vectors.json has no `blends` section — regenerate with: node tools/gen-vectors.mjs');
    }

    for (final c in cases) {
      test(c['name'] as String, () {
        final before = c['before'] as Map<String, dynamic>;
        final run = _run(
          hand: _cardsFromJson(before['hand'] as List<dynamic>),
          deck: _cardsFromJson(before['deck'] as List<dynamic>),
          blends: (before['blends'] as List<dynamic>).cast<String>(),
        );

        for (final step in (c['steps'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          final out = applyBlend(
            run,
            step['use'] as int,
            (step['sel'] as List<dynamic>).cast<int>(),
          );

          // The web signals refusal by flashing the message instead of "<name> used", so the
          // fixture pins the error text as well as the fact that something was refused.
          final flash = step['flash'] as String;
          if (flash.startsWith('Select ingredient')) {
            expect(out.error, equals(flash), reason: 'refusal message');
            expect(out.ok, isFalse);
          } else {
            expect(out.error, isNull, reason: 'JS flashed "$flash", so it succeeded');
            expect(out.ok, isTrue);
          }

          expect(
            _sigs(run.hand),
            equals(_sigs(_cardsFromJson(step['hand'] as List<dynamic>))),
            reason: 'hand after blend ${step['use']} on ${step['sel']}',
          );
          expect(
            run.deck.map((x) => x.id).toList(),
            equals((step['deck'] as List<dynamic>).cast<String>()),
            reason: 'deck after blend ${step['use']}',
          );
          expect(
            run.blends.map((b) => b.id).toList(),
            equals((step['blends'] as List<dynamic>).cast<String>()),
            reason: 'inventory after blend ${step['use']}',
          );
        }

        // The rewrite has to land where the engine can see it, which is the only reason any
        // of this matters — so the fixture also carries what JS's bestPattern made of it.
        final finalHand = run.hand.take(5).toList();
        expect(
          finalHand.map((x) => x.id).toList(),
          equals((c['patternCards'] as List<dynamic>).cast<String>()),
        );
        expect(bestPattern(finalHand).pattern, equals(c['pattern']));
      });
    }

    test('the vectors cover all six blends and reach every secret recipe', () {
      final ids = <String>{};
      for (final c in cases) {
        for (final b in (c['before'] as Map<String, dynamic>)['blends'] as List<dynamic>) {
          ids.add(b as String);
        }
      }
      expect(ids, equals(kBlends.map((b) => b.id).toSet()),
          reason: 'a blend with no vector is a blend the port could get wrong silently');

      final patterns = cases.map((c) => c['pattern'] as String).toSet();
      for (final p in kSecretPatterns) {
        expect(patterns, contains(p), reason: '$p has no blend vector proving it is reachable');
      }
    });
  });
}

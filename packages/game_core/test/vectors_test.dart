/// Differential tests: the Dart engine must reproduce the JS reference exactly.
///
/// `web/game-core.mjs` is a tuned, playtested engine — it, not the spec, defines correct
/// behaviour for M1. Vectors are generated from it by `node tools/gen-vectors.mjs`; a
/// mismatch here means the port changed the game, which is the one failure mode that would
/// quietly ruin a balanced design.
///
/// Comparisons are exact, including doubles: both engines are IEEE-754 doing the same
/// operations in the same order, so any tolerance would just hide a real divergence.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

Card _card(Map<String, dynamic> j) => Card(
  id: j['id'] as String,
  family: j['family'] as String,
  rank: j['rank'] as int,
  display: j['display'] as String,
  prized: j['prized'] as bool,
);

List<Card> _cards(List<dynamic> j) => j.map((e) => _card(e as Map<String, dynamic>)).toList();

/// Builds a utensil from the fixture's own definition rather than the Dart catalog, so the
/// synthetic DSL probes work and a catalog edit surfaces as a scoring diff, not a crash.
Utensil _utensil(Map<String, dynamic> j) => Utensil(
  id: j['id'] as String,
  name: j['name'] as String,
  rarity: j['rarity'] as String,
  cost: j['cost'] as int,
  trigger: j['trigger'] as String,
  condition: (j['condition'] as Map<String, dynamic>?)?.cast<String, Object?>(),
  effect: (j['effect'] as Map<String, dynamic>).cast<String, Object?>(),
  text: j['text'] as String,
);

late final Map<String, Utensil> _utensilDefs;

ScoreContext _ctx(Map<String, dynamic> j) => ScoreContext(
  palate: j['palate'] == null ? null : kPalates[j['palate'] as String],
  utensils: (j['utensils'] as List<dynamic>).map((id) => _utensilDefs[id as String]!).toList(),
  critic: j['critic'] == null ? null : kCritics[j['critic'] as String],
  kitchenLevel: j['kitchenLevel'] as int,
  isFirstDish: j['isFirstDish'] as bool,
  isLastDish: j['isLastDish'] as bool,
);

void main() {
  final file = File('test/vectors.json');
  if (!file.existsSync()) {
    throw StateError(
      'test/vectors.json missing — regenerate with: node tools/gen-vectors.mjs',
    );
  }
  final v = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  _utensilDefs = (v['utensilDefs'] as Map<String, dynamic>).map(
    (id, def) => MapEntry(id, _utensil(def as Map<String, dynamic>)),
  );

  test('the shipping catalog matches the fixture definitions', () {
    for (final u in kUtensils) {
      final ref = _utensilDefs[u.id];
      expect(ref, isNotNull, reason: '${u.id} missing from vectors — regenerate them');
      expect(u.effect, equals(ref!.effect), reason: '${u.id} effect drifted from the JS catalog');
      expect(u.condition, equals(ref.condition), reason: '${u.id} condition drifted');
      expect(u.cost, equals(ref.cost), reason: '${u.id} cost drifted');
      expect(u.rarity, equals(ref.rarity), reason: '${u.id} rarity drifted');
    }
  });

  group('RNG (32-bit arithmetic must survive the port to 64-bit ints)', () {
    for (final c in (v['rng'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final seed = c['seed'] as String;
      test('seed "$seed"', () {
        final r = Rng(seed);
        for (final expected in (c['next'] as List<dynamic>).cast<num>()) {
          expect(r.next(), equals(expected.toDouble()), reason: 'next() drift');
        }
        for (final expected in (c['ints'] as List<dynamic>).cast<int>()) {
          expect(r.nextInt(52), equals(expected), reason: 'nextInt drift');
        }
        final pantry = buildPantry().take(12).toList();
        expect(
          r.shuffle(pantry).map((c) => c.id).toList(),
          equals((c['shuffled'] as List<dynamic>).cast<String>()),
          reason: 'shuffle order drift — every deal and shop roll depends on this',
        );
        for (final expected in (c['weighted'] as List<dynamic>).cast<String>()) {
          expect(r.weighted(kRarityWeights), equals(expected), reason: 'weighted drift');
        }
      });
    }
  });

  test('bestPattern matches on all ${(v['patterns'] as List).length} cases', () {
    final cases = (v['patterns'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final cards = _cards(c['cards'] as List<dynamic>);
      final got = bestPattern(cards);
      final hand = cards.map((x) => x.toString()).join(', ');
      expect(got.pattern, equals(c['pattern']), reason: 'case $i pattern · hand: $hand');
      expect(
        got.scoring.map((x) => x.id).toList(),
        equals((c['scoring'] as List<dynamic>).cast<String>()),
        reason: 'case $i scoring cards · hand: $hand',
      );
    }
  });

  test('scoreDish matches on all ${(v['scores'] as List).length} cases', () {
    final cases = (v['scores'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final cards = _cards(c['cards'] as List<dynamic>);
      final ctxJson = c['ctx'] as Map<String, dynamic>;
      final got = scoreDish(cards, _ctx(ctxJson));
      final where = 'case $i · ${c['pattern']} · utensils ${ctxJson['utensils']} · '
          'palate ${ctxJson['palate']} · critic ${ctxJson['critic']} · lvl ${ctxJson['kitchenLevel']}';
      expect(got.pattern, equals(c['pattern']), reason: '$where — pattern');
      expect(got.flavor, equals((c['flavor'] as num).toDouble()), reason: '$where — flavor');
      expect(got.heat, equals((c['heat'] as num).toDouble()), reason: '$where — heat');
      expect(got.coins, equals(c['coins']), reason: '$where — coins');
      expect(got.score, equals(c['score']), reason: '$where — SCORE');
      expect(
        got.scoring.map((x) => x.id).toList(),
        equals((c['scoring'] as List<dynamic>).cast<String>()),
        reason: '$where — scoring cards',
      );
    }
  });

  test('dishError matches on all ${(v['dishErrors'] as List).length} cases', () {
    final cases = (v['dishErrors'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final critic = c['critic'] == null ? null : kCritics[c['critic'] as String];
      expect(
        dishError(_cards(c['cards'] as List<dynamic>), critic),
        equals(c['error']),
        reason: 'case $i · ${(c['cards'] as List).length} cards · critic ${c['critic']}',
      );
    }
  });

  test('buildPantry matches for every deck', () {
    for (final c in (v['pantries'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final deckId = c['deckId'] as String;
      final got = buildPantry(kDeckById[deckId]);
      final expected = _cards(c['cards'] as List<dynamic>);
      expect(got.length, equals(expected.length), reason: 'deck $deckId — card count');
      for (var i = 0; i < expected.length; i++) {
        expect(got[i].id, equals(expected[i].id), reason: 'deck $deckId — card $i id');
        expect(got[i].family, equals(expected[i].family), reason: 'deck $deckId — card $i family');
        expect(got[i].rank, equals(expected[i].rank), reason: 'deck $deckId — card $i rank');
        expect(got[i].prized, equals(expected[i].prized), reason: 'deck $deckId — card $i prized');
      }
    }
  });

  group('pattern ladder coverage (guards against a fixture that stops exercising the top)', () {
    test('every recipe appears in the vectors', () {
      final seen = (v['patterns'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((c) => c['pattern'] as String)
          .toSet();
      for (final p in kPatternOrder) {
        expect(seen, contains(p), reason: '$p has no vector — regenerate with tools/gen-vectors.mjs');
      }
    });
  });
}

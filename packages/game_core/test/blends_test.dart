/// Tests for blend application — twenty card rewrites, and the payoff they unlock.
///
/// Four halves, in descending order of what they will save you:
///
/// 1. **The DSL allow-list**, mirroring `utensils_test.dart`'s. `applyBlend` silently ignores
///    an effect key it does not know, so `rank_added` instead of `rank_add` ships a blend that
///    reads correctly in the bazaar, costs four coins and does nothing. Nothing else in the
///    repo catches that. The table below is restated independently of `blends.dart`, so a typo
///    in the interpreter cannot bless itself, and it runs over the *whole* catalog.
/// 2. **The ported six are frozen.** They are pinned against `web/game-core.mjs` by
///    `test/vectors.json`, and `_ported` restates them literally — effect map included — so
///    the freeze still holds if the fixture is ever regenerated or deleted.
/// 3. **Each blend's exact rewrite**, hit case and refusal, one per entry in the catalog.
/// 4. **The secret recipes are reachable.** `five_kind`, `full_family` and `perfect_palate`
///    are scored by the engine but cannot be dealt, so until blends could be played they were
///    dead code in `bestPattern` and dead entries in the Recipe Book. Each test takes a hand
///    one blend short and shows the pattern climbing, so a regression that breaks a route
///    shows up as a named failure rather than as a recipe nobody notices is missing.
///
/// The `blend vectors` group is the differential half, replaying cases recorded from §UI's
/// own `useBlend` by `tools/gen-vectors.mjs`. Those own the question "does this match the web
/// build"; the hand-written tests above own "is this the behaviour we meant".
///
/// The vectors cover the ported six and nothing else, and they should not grow: the other
/// fourteen do not exist in the web build, so there is no JS `useBlend` to record them from.
/// Generating a fixture for them from the Dart side would prove only that Dart agrees with
/// Dart. They are covered by the hand-computed cases here instead.
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

// ---------------------------------------------------------------------------
// The DSL allow-list — must match the interpreter in blends.dart.
// ---------------------------------------------------------------------------

/// Keys that rewrite a card in place.
const Set<String> _rewriteKeys = {
  'set_family', 'copy_family', 'rank_set', 'rank_add', 'rank_invert', 'copy_rank',
  'set_prized', 'prefix',
};

/// Keys that add, remove or move cards between the hand and the deck.
const Set<String> _handDeckKeys = {'duplicate', 'merge', 'discard_draw', 'draw_matching', 'draw'};

/// Not a verb of its own — it redirects the rewrites.
const Set<String> _modifierKeys = {'scope'};

final Set<String> _effectKeys = {..._rewriteKeys, ..._handDeckKeys, ..._modifierKeys};

const Set<String> _familyValued = {'set_family'};
const Set<String> _intValued = {'rank_set', 'rank_add', 'draw'};
const Set<String> _textValued = {'prefix', 'scope'};
const Set<String> _flagValued = {
  'copy_family', 'copy_rank', 'rank_invert', 'set_prized', 'duplicate', 'merge',
  'discard_draw', 'draw_matching',
};

/// Keys that write a card's family / intensity. At most one of each per blend, so the
/// interpreter's fixed application order stays a documented detail rather than something
/// content has to reason about.
const Set<String> _familyVerbs = {'set_family', 'copy_family'};
const Set<String> _rankVerbs = {'rank_set', 'rank_add', 'rank_invert', 'copy_rank'};

/// Keys that take cards out of the hand. Two of them in one blend would fight over indices.
const Set<String> _removesCards = {'merge', 'discard_draw'};

/// Keys that read the first selected card as a source instead of editing it.
const Set<String> _sourceReading = {'copy_family', 'copy_rank', 'merge'};

/// Keys that need at least one selected card to do anything.
final Set<String> _needsTargets = {
  ..._rewriteKeys, 'duplicate', 'merge', 'discard_draw', 'draw_matching',
};

// ---------------------------------------------------------------------------
// The ported six — pinned against web/game-core.mjs by vectors.json.
// ---------------------------------------------------------------------------

const List<(String, String, int, int, Map<String, Object?>)> _ported = [
  ('chili_oil', 'Chili Oil', 3, 2, {'set_family': 'spicy', 'prefix': 'Chili '}),
  ('sea_salt', 'Sea Salt', 3, 2, {'set_family': 'salty', 'prefix': 'Salted '}),
  ('fermentation', 'Fermentation', 3, 1, {'rank_add': 3}),
  ('sun_dry', 'Sun-Dry', 3, 1, {'duplicate': true}),
  ('sharpen', 'Whetstone', 4, 1, {'rank_set': 10}),
  ('mise', 'Mise en Place', 3, 0, {'draw': 2}),
];

final Set<String> _portedIds = _ported.map((p) => p.$1).toSet();

/// Everything the expansion added — i.e. the catalog minus the frozen six.
List<Blend> get _expansion => kBlends.where((b) => !_portedIds.contains(b.id)).toList();

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

/// One blend's hit case: the board it is played on, and exactly what comes back.
class _Case {
  const _Case(
    this.id, {
    required this.hand,
    required this.sel,
    required this.wantHand,
    this.deck = const [],
    this.wantDeck = const [],
  });

  final String id;
  final List<Card> hand;
  final List<Card> deck;
  final List<int> sel;

  /// Full card signatures, so "unchanged" means unchanged and not merely same-length.
  final List<String> wantHand;

  /// Deck ids after the blend — only the deck-reaching blends move these.
  final List<String> wantDeck;
}

void main() {
  // -------------------------------------------------------------------------
  // 1. The DSL allow-list.
  // -------------------------------------------------------------------------
  group('DSL allow-list (a typo\'d key ships a blend that silently does nothing)', () {
    for (final b in kBlends) {
      test('${b.id} uses only keys the interpreter implements', () {
        expect(b.effect, isNotEmpty, reason: '${b.id} has no effect at all');

        for (final entry in b.effect.entries) {
          final k = entry.key;
          final v = entry.value;
          expect(_effectKeys, contains(k), reason: '${b.id}: unknown effect key "$k"');

          if (_familyValued.contains(k)) {
            expect(kFamilies, contains(v), reason: '${b.id}: "$k" names no flavour family');
          } else if (_intValued.contains(k)) {
            expect(v, isA<int>(), reason: '${b.id}: "$k" must carry a magnitude');
            expect(v, isNot(0), reason: '${b.id}: "$k" of 0 does nothing');
          } else if (_flagValued.contains(k)) {
            expect(v, isTrue, reason: '${b.id}: flag "$k" is only meaningful when true');
          } else if (_textValued.contains(k)) {
            expect(v, isA<String>(), reason: '${b.id}: "$k" must be text');
            expect((v! as String).trim(), isNotEmpty, reason: '${b.id}: "$k" is blank');
          }
        }

        // Value ranges, where a plausible-looking number would still break the game.
        final rankSet = b.effect['rank_set'];
        if (rankSet != null) {
          expect(rankSet, inInclusiveRange(1, 10), reason: '${b.id}: rank_set off the 1-10 scale');
        }
        final rankAdd = b.effect['rank_add'];
        if (rankAdd != null) {
          expect(rankAdd, inInclusiveRange(-9, 9), reason: '${b.id}: rank_add cannot move that far');
        }
        final draw = b.effect['draw'];
        if (draw != null) {
          expect(draw, inInclusiveRange(1, 5), reason: '${b.id}: draw is a hand, not a deck');
        }

        // A prefix with no trailing space renders "ChiliFig".
        final prefix = b.effect['prefix'] as String?;
        if (prefix != null) {
          expect(prefix.endsWith(' '), isTrue, reason: '${b.id}: prefix "$prefix" needs a trailing space');
          expect(b.effect.keys.any(_familyVerbs.contains), isTrue,
              reason: '${b.id}: a prefix without a family rewrite renames a card that did not change');
        }

        // `scope` is the one modifier, and it only means anything on a blend with no targets.
        final scope = b.effect['scope'];
        if (scope != null) {
          expect(scope, equals('hand'), reason: '${b.id}: the only scope is "hand"');
          expect(b.select, equals(0), reason: '${b.id}: a hand-scoped blend must take no targets');
          expect(b.effect.keys.any(_sourceReading.contains), isFalse,
              reason: '${b.id}: a hand-scoped blend has no source card to read');
        }
      });

      test('${b.id} writes each field once and matches its select count', () {
        final keys = b.effect.keys.toSet();
        expect(keys.intersection(_familyVerbs).length, lessThanOrEqualTo(1),
            reason: '${b.id}: two family verbs fight over the same field');
        expect(keys.intersection(_rankVerbs).length, lessThanOrEqualTo(1),
            reason: '${b.id}: two intensity verbs fight over the same field');
        expect(keys.intersection(_removesCards).length, lessThanOrEqualTo(1),
            reason: '${b.id}: two card-removing verbs fight over the same indices');
        if (keys.any(_removesCards.contains)) {
          // The rewrites land on the targets, and a card-removing verb then deletes them —
          // so the rewrite would be paid for and never seen.
          expect(keys.intersection(_rewriteKeys), isEmpty,
              reason: '${b.id}: rewrites a card it is about to discard');
        }

        if (keys.any(_sourceReading.contains)) {
          expect(b.select, greaterThanOrEqualTo(2),
              reason: '${b.id}: a source-reading verb needs a source and a target');
        }
        if (b.select == 0) {
          expect(keys.any(_needsTargets.contains) && b.effect['scope'] != 'hand', isFalse,
              reason: '${b.id}: targets nothing, but its effect only acts on targets');
        } else {
          expect(keys.any(_needsTargets.contains), isTrue,
              reason: '${b.id}: asks for a selection it never reads');
          expect(b.effect['scope'], isNull,
              reason: '${b.id}: hand-scoped, so the selection it asks for is ignored');
        }
      });
    }
  });

  group('catalog hygiene', () {
    test('there are 20 blends and the ids are unique', () {
      expect(kBlends.length, equals(20));
      final seen = <String>{};
      for (final b in kBlends) {
        expect(seen.add(b.id), isTrue, reason: 'duplicate blend id "${b.id}"');
      }
      expect(kBlendById.length, equals(kBlends.length), reason: 'the id index lost an entry');
    });

    test('every blend has a name and a description', () {
      for (final b in kBlends) {
        expect(b.name.trim(), isNotEmpty, reason: '${b.id} has no name');
        expect(b.desc.trim(), isNotEmpty, reason: '${b.id} has no bazaar copy');
      }
    });

    test('cost and select stay in range', () {
      for (final b in kBlends) {
        expect(b.cost, inInclusiveRange(3, 5), reason: '${b.id} is priced off the scale');
        // A dish is at most 5 cards, so a blend can never usefully target more.
        expect(b.select, inInclusiveRange(0, 5), reason: '${b.id} targets more than a dish holds');
      }
    });

    test('no two blends are the same blend', () {
      // Same select and same effect map means one of them is noise in the shop.
      final seen = <String, String>{};
      for (final b in kBlends) {
        final key = '${b.select}|${(b.effect.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join(',')}';
        expect(seen[key], isNull, reason: '${b.id} is a duplicate of ${seen[key]}');
        seen[key] = b.id;
      }
    });
  });

  // -------------------------------------------------------------------------
  // 2. The ported six, frozen.
  // -------------------------------------------------------------------------
  group('the ported six are frozen (vectors.json pins these against the JS engine)', () {
    test('all 6 are present, in order, at the head of the catalog', () {
      expect(kBlends.length, greaterThanOrEqualTo(_ported.length));
      for (var i = 0; i < _ported.length; i++) {
        expect(kBlends[i].id, equals(_ported[i].$1),
            reason: 'ported blend $i moved — bazaar rolls are indexed off this order');
      }
    });

    for (final p in _ported) {
      test('${p.$1} is unchanged', () {
        final b = kBlendById[p.$1];
        expect(b, isNotNull, reason: '${p.$1} was removed from the catalog');
        expect(b!.name, equals(p.$2), reason: '${p.$1} renamed');
        expect(b.cost, equals(p.$3), reason: '${p.$1} repriced');
        expect(b.select, equals(p.$4), reason: '${p.$1} changed how many cards it takes');
        expect(b.effect, equals(p.$5), reason: '${p.$1}: the DSL no longer expresses the port');
      });
    }
  });

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

  // -------------------------------------------------------------------------
  // 3. The fourteen new verbs, one hit case each.
  // -------------------------------------------------------------------------
  final cases = <_Case>[
    // --- the rest of the family rewrites ---------------------------------------------------
    _Case('brine',
        hand: [_c('spicy', 8), _c('sweet', 4), _c('umami', 6)], sel: [1, 2],
        wantHand: [
          'spicy_8|spicy|8|Scotch Bonnet|false', // untouched
          'sweet_4|sour|4|Pickled Fig|false', // family and display rewritten, rank and id kept
          'umami_6|sour|6|Pickled Soy Bean|false',
        ]),
    _Case('jaggery',
        hand: [_c('sour', 3), _c('salty', 7)], sel: [0, 1],
        wantHand: [
          'sour_3|sweet|3|Candied Tamarind|false',
          'salty_7|sweet|7|Candied Capers|false',
        ]),
    _Case('koji',
        // select 2 played on one card: legal, and it converts that one.
        hand: [_c('spicy', 2), _c('sour', 9)], sel: [0],
        wantHand: [
          'spicy_2|umami|2|Koji Black Pepper|false',
          'sour_9|sour|9|Amchur|false',
        ]),
    // --- intensity, downward and reflected -------------------------------------------------
    _Case('blanch',
        hand: [_c('salty', 10), _c('salty', 1)], sel: [0],
        wantHand: [
          'salty_10|salty|8|Bottarga|false', // display does not follow the rank
          'salty_1|salty|1|Sea Salt|false',
        ]),
    _Case('invert',
        hand: [_c('sweet', 2), _c('sweet', 10)], sel: [0],
        wantHand: [
          'sweet_2|sweet|9|Honey|false', // 11 - 2
          'sweet_10|sweet|10|Rose Syrup|false',
        ]),
    _Case('cold_smoke',
        // select 0: no targets, and the whole hand moves.
        hand: [_c('spicy', 1), _c('sweet', 9), _c('sour', 10)], sel: [],
        wantHand: [
          'spicy_1|spicy|2|Paprika|false',
          'sweet_9|sweet|10|Dark Chocolate|false',
          'sour_10|sour|10|Fermented Lime|false', // already at the cap
        ]),
    // --- the two-card verbs: first selected is the source, and is never touched -------------
    _Case('julienne',
        hand: [_c('spicy', 9), _c('sweet', 2)], sel: [0, 1],
        wantHand: [
          'spicy_9|spicy|9|Ghost Pepper|false',
          'sweet_2|sweet|9|Honey|false', // rank copied, family and display kept
        ]),
    _Case('infusion',
        hand: [_c('umami', 5), _c('spicy', 7)], sel: [0, 1],
        wantHand: [
          'umami_5|umami|5|Dashi|false',
          "spicy_7|umami|7|Infused Bird's Eye Chili|false", // family copied, rank kept
        ]),
    _Case('levain',
        hand: [_c('sour', 8), _c('salty', 3)], sel: [0, 1],
        wantHand: [
          'sour_8|sour|8|Sumac|false',
          'salty_3|sour|8|Cultured Soy Sauce|false', // both fields copied: a twin
        ]),
    _Case('reduction',
        hand: [_c('sweet', 4), _c('sour', 5), _c('umami', 2)], sel: [0, 1],
        wantHand: [
          'sweet_4|sweet|9|Fig|false', // 4 + 5, and the sour is consumed
          'umami_2|umami|2|Tomato|false',
        ]),
    // --- material --------------------------------------------------------------------------
    _Case('conserva',
        hand: [_c('spicy', 6), _c('sweet', 2)], sel: [0, 1],
        wantHand: [
          'spicy_6|spicy|6|Red Chili|false',
          'sweet_2|sweet|2|Honey|false',
          'spicy_6_copy|spicy|6|Red Chili|false', // appended in selection order
          'sweet_2_copy|sweet|2|Honey|false',
        ]),
    _Case('varak',
        hand: [_c('umami', 10), _c('sweet', 1)], sel: [0],
        wantHand: [
          'umami_10|umami|10|Bonito Flake|true', // the only blend that mints a prized card
          'sweet_1|sweet|1|Jaggery|false',
        ]),
    // --- the deck --------------------------------------------------------------------------
    _Case('winnow',
        hand: [_c('spicy', 1), _c('sweet', 2), _c('sour', 3)],
        deck: [_c('salty', 4), _c('umami', 5), _c('salty', 6)],
        sel: [0, 1],
        wantHand: [
          'sour_3|sour|3|Tamarind|false', // the two selected left
          'salty_4|salty|4|Fish Sauce|false', // and two came off the top, in deck order
          'umami_5|umami|5|Dashi|false',
        ],
        wantDeck: ['salty_6']),
    _Case('forage',
        hand: [_c('spicy', 3)],
        deck: [_c('sweet', 5), _c('spicy', 9), _c('sour', 2)],
        sel: [0],
        wantHand: [
          'spicy_3|spicy|3|Green Chili|false',
          'spicy_9|spicy|9|Ghost Pepper|false', // the first Spicy in the deck, not the top card
        ],
        wantDeck: ['sweet_5', 'sour_2']),
  ];

  group('each new blend rewrites the hand exactly', () {
    test('every new blend has a hit case', () {
      final tested = cases.map((c) => c.id).toSet();
      final shipped = _expansion.map((b) => b.id).toSet();
      expect(tested.difference(shipped), isEmpty, reason: 'a case for a blend that is gone');
      expect(shipped.difference(tested), isEmpty, reason: 'new blend with no case — add one');
      expect(cases.length, equals(_expansion.length), reason: 'duplicate case');
    });

    for (final k in cases) {
      final b = kBlendById[k.id];
      test('${k.id} — ${b?.desc ?? "MISSING"}', () {
        expect(b, isNotNull, reason: '${k.id} is not in the catalog');
        final run = _run(hand: k.hand, deck: k.deck, blends: [k.id]);

        final out = applyBlend(run, 0, k.sel);

        expect(out.error, isNull, reason: '${k.id} refused a legal play');
        expect(out.ok, isTrue);
        expect(run.blends, isEmpty, reason: 'the blend is consumed on success');
        expect(_sigs(run.hand), equals(k.wantHand));
        expect(run.hand.length, equals(k.wantHand.length));
        expect(run.deck.map((c) => c.id).toList(), equals(k.wantDeck));
      });
    }
  });

  group('the new verbs at their edges', () {
    test('blanch floors intensity at 1 rather than going negative', () {
      final run = _run(hand: [_c('sour', 1), _c('sour', 2)], blends: ['blanch', 'blanch']);
      expect(applyBlend(run, 0, [0]).ok, isTrue);
      expect(run.hand[0].rank, equals(1), reason: '1 - 2 clamps to 1, not -1');
      expect(applyBlend(run, 0, [1]).ok, isTrue);
      expect(run.hand[1].rank, equals(1), reason: '2 - 2 clamps to 1, not 0');
    });

    test('invert is its own inverse and spans the whole scale', () {
      for (final (before, after) in [(1, 10), (2, 9), (5, 6), (6, 5), (9, 2), (10, 1)]) {
        final run = _run(hand: [_c('umami', before)], blends: ['invert']);
        expect(applyBlend(run, 0, [0]).ok, isTrue);
        expect(run.hand[0].rank, equals(after), reason: 'invert of $before');
      }
    });

    test('cold_smoke ignores any selection and touches every card', () {
      final run = _run(hand: [_c('spicy', 3), _c('sweet', 4)], blends: ['cold_smoke']);
      expect(applyBlend(run, 0, [0]).ok, isTrue, reason: 'select is 0, so a selection is noise');
      expect(run.hand.map((c) => c.rank).toList(), equals([4, 5]));
    });

    test('cold_smoke on an empty hand is legal and changes nothing', () {
      final run = _run(hand: const [], blends: ['cold_smoke']);
      expect(applyBlend(run, 0, const []).ok, isTrue);
      expect(run.hand, isEmpty);
      expect(run.blends, isEmpty, reason: 'still consumed');
    });

    test('reduction caps the combined intensity at 10 and shrinks the hand', () {
      final run = _run(hand: [_c('salty', 8), _c('salty', 7)], blends: ['reduction']);
      expect(applyBlend(run, 0, [0, 1]).ok, isTrue);
      expect(_sigs(run.hand), equals(['salty_8|salty|10|Anchovy|false']),
          reason: '8 + 7 clamps to 10, and the absorbed card leaves the hand');
    });

    test('reduction keeps the first selected, not the first in hand', () {
      final run = _run(hand: [_c('sweet', 2), _c('sour', 3)], blends: ['reduction']);
      expect(applyBlend(run, 0, [1, 0]).ok, isTrue);
      expect(_sigs(run.hand), equals(['sour_3|sour|5|Tamarind|false']));
    });

    test('winnow draws only what the deck has left', () {
      final run = _run(
        hand: [_c('spicy', 1), _c('sweet', 2), _c('sour', 3)],
        deck: [_c('salty', 4)],
        blends: ['winnow'],
      );
      expect(applyBlend(run, 0, [0, 1]).ok, isTrue);
      expect(run.hand.map((c) => c.id).toList(), equals(['sour_3', 'salty_4']),
          reason: 'both discarded, only one to draw');
      expect(run.deck, isEmpty);
    });

    test('winnow on an empty deck is a pure discard', () {
      final run = _run(hand: [_c('spicy', 1), _c('sweet', 2)], blends: ['winnow']);
      expect(applyBlend(run, 0, [0]).ok, isTrue);
      expect(run.hand.map((c) => c.id).toList(), equals(['sweet_2']));
    });

    test('forage finds nothing when no deck card shares the family', () {
      final run = _run(
        hand: [_c('spicy', 3)],
        deck: [_c('sweet', 5), _c('sour', 2)],
        blends: ['forage'],
      );
      expect(applyBlend(run, 0, [0]).ok, isTrue);
      expect(run.hand.length, equals(1), reason: 'nothing to find');
      expect(run.deck.length, equals(2), reason: 'and the pantry is untouched');
      expect(run.blends, isEmpty, reason: 'still consumed — a miss is not a refusal');
    });

    test('conserva on one target makes one copy', () {
      final run = _run(hand: [_c('umami', 4)], blends: ['conserva']);
      expect(applyBlend(run, 0, [0]).ok, isTrue);
      expect(_sigs(run.hand), equals([
        'umami_4|umami|4|Parmesan|false',
        'umami_4_copy|umami|4|Parmesan|false',
      ]));
    });

    test('varak stacks harmlessly — a prized card gilded again stays prized', () {
      final run = _run(hand: [_c('sweet', 5)], blends: ['varak', 'varak']);
      expect(applyBlend(run, 0, [0]).ok, isTrue);
      expect(applyBlend(run, 0, [0]).ok, isTrue);
      expect(run.hand.single.prized, isTrue);
    });

    test('a two-card verb pointed at one card is refused, not silently wasted', () {
      // The web build has no source-reading blend, so this guard cannot move the differential
      // — and burning 4 coins for no effect is the worst failure mode this system has.
      for (final id in ['julienne', 'infusion', 'levain', 'reduction']) {
        final run = _run(hand: [_c('spicy', 5), _c('sweet', 5)], blends: [id]);
        final before = _sigs(run.hand);

        final out = applyBlend(run, 0, [0]);

        expect(out.error, equals('Select 2 ingredients — the first one is the source'), reason: id);
        expect(out.ok, isFalse, reason: id);
        expect(run.blends.map((b) => b.id).toList(), equals([id]), reason: '$id must not be consumed');
        expect(_sigs(run.hand), equals(before), reason: id);
      }
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

    // The three loops below run over the WHOLE catalog rather than a sample: these are the
    // branches every future blend inherits for free, and the only way that stays true is if
    // adding a catalog entry adds its own bounds coverage automatically.
    test('every blend that needs targets is a free no-op on an empty selection', () {
      for (final b in kBlends) {
        final run = _run(
          hand: [_c('spicy', 5), _c('sweet', 5), _c('sour', 5)],
          deck: [_c('salty', 5)],
          blends: [b.id],
        );
        final before = _sigs(run.hand);

        final out = applyBlend(run, 0, const []);

        if (b.select > 0) {
          expect(out.error, equals('Select ingredient(s) first, then tap the blend'), reason: b.id);
          expect(out.ok, isFalse, reason: b.id);
          expect(run.blends.map((x) => x.id).toList(), equals([b.id]),
              reason: '${b.id}: a refused tap must be free');
          expect(_sigs(run.hand), equals(before), reason: b.id);
        } else {
          expect(out.error, isNull, reason: '${b.id} takes no targets, so this is legal');
          expect(out.ok, isTrue, reason: b.id);
        }
      }
    });

    test('every blend errors on an out-of-range hand index and mutates nothing', () {
      for (final b in kBlends) {
        for (final bad in [
          [3],
          [99],
          [-1],
          [0, 7],
        ]) {
          final run = _run(
            hand: [_c('spicy', 5), _c('sweet', 5), _c('sour', 5)],
            deck: [_c('salty', 5), _c('umami', 5)],
            blends: [b.id],
          );
          final before = _sigs(run.hand);

          final out = applyBlend(run, 0, bad);

          expect(out.error, isNotNull, reason: '${b.id} on $bad');
          expect(out.ok, isFalse, reason: '${b.id} on $bad');
          expect(run.blends.map((x) => x.id).toList(), equals([b.id]), reason: '${b.id} on $bad');
          expect(_sigs(run.hand), equals(before),
              reason: '${b.id} on $bad — a bad index must not half-apply the blend');
          expect(run.deck.length, equals(2), reason: '${b.id} on $bad — and must not touch the deck');
        }
      }
    });

    test('every blend errors on an out-of-range blend index and mutates nothing', () {
      for (var i = 0; i < kBlends.length; i++) {
        for (final bad in [1, 5, -1, -99]) {
          final run = _run(hand: [_c('sweet', 5), _c('sour', 5)], blends: [kBlends[i].id]);
          final before = _sigs(run.hand);

          final out = applyBlend(run, bad, [0, 1]);

          expect(out.error, isNotNull, reason: '${kBlends[i].id} at blend index $bad');
          expect(out.ok, isFalse, reason: '${kBlends[i].id} at blend index $bad');
          expect(run.blends.length, equals(1), reason: '${kBlends[i].id} at blend index $bad');
          expect(_sigs(run.hand), equals(before), reason: '${kBlends[i].id} at blend index $bad');
        }
      }
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

    // --- the routes the expansion opened ---------------------------------------------------
    // Six blends could reach the secrets; the count is now nine, by three different verbs.
    // Each of these is a hand that CANNOT reach the recipe without the blend, so the test
    // fails if the route ever closes rather than merely if the number changes.

    test('conserva duplicates twice into five of a rank', () {
      final run = _run(
        hand: [_c('spicy', 7), _c('sweet', 7), _c('sour', 7)],
        blends: ['conserva'],
      );
      expect(bestPattern(run.hand).pattern, equals('three_kind'),
          reason: 'three cards is the ceiling before the copies exist');

      expect(applyBlend(run, 0, [0, 1]).ok, isTrue);

      expect(run.hand.length, equals(5));
      expect(bestPattern(run.hand).pattern, equals('five_kind'),
          reason: 'two copies of rank 7 make five of a rank in one blend');
    });

    test('julienne matches the odd card into five of a rank', () {
      final run = _run(
        hand: [_c('spicy', 10), _c('sweet', 10), _c('sour', 10), _c('salty', 10), _c('umami', 3)],
        blends: ['julienne'],
      );
      expect(bestPattern(run.hand).pattern, equals('four_kind'),
          reason: 'the stray 3 caps it at four of a rank');

      expect(applyBlend(run, 0, [0, 4]).ok, isTrue);

      expect(run.hand.map((c) => c.rank).toList(), equals([10, 10, 10, 10, 10]));
      expect(bestPattern(run.hand).pattern, equals('five_kind'));
    });

    test('koji completes a one-family full house', () {
      final run = _run(
        hand: [
          _c('umami', 8),
          _c('umami', 8, suffix: '_b'),
          _c('umami', 8, suffix: '_c'),
          _c('sweet', 4),
          _c('sour', 4),
        ],
        blends: ['koji'],
      );
      expect(bestPattern(run.hand).pattern, equals('full_house'),
          reason: 'the mixed families cap it at a Full House');

      expect(applyBlend(run, 0, [3, 4]).ok, isTrue);
      expect(run.hand.map((c) => c.family).toSet(), equals({'umami'}));
      expect(bestPattern(run.hand).pattern, equals('full_family'));
    });

    test('levain twins the odd card into a perfect palate', () {
      final run = _run(
        hand: [
          _c('spicy', 9),
          _c('spicy', 9, suffix: '_b'),
          _c('spicy', 9, suffix: '_c'),
          _c('spicy', 9, suffix: '_d'),
          _c('sweet', 2),
        ],
        blends: ['levain'],
      );
      expect(bestPattern(run.hand).pattern, equals('four_kind'),
          reason: 'wrong family AND wrong rank — the stray blocks both halves');

      // One blend fixes both, which is what the 5-coin price is for.
      expect(applyBlend(run, 0, [0, 4]).ok, isTrue);
      expect(_sig(run.hand[4]), equals('sweet_2|spicy|9|Cultured Honey|false'));

      const level = 4;
      final res = scoreDish(run.hand, const ScoreContext(kitchenLevel: level));
      final (baseF, baseH) = _leveledBase('perfect_palate', level);

      expect(res.pattern, equals('perfect_palate'));
      expect(res.flavor, equals(baseF + 45), reason: 'leveled base + five rank-9 intensities');
      expect(res.score, equals(((baseF + 45) * baseH).floor()));
    });

    test('every secret recipe in the catalog has a blend route proven above', () {
      // Guards against a catalog gaining a fourth secret that nothing can reach.
      expect(kSecretPatterns, equals(['five_kind', 'full_family', 'perfect_palate']));
    });

    test('every blend that can reach a secret recipe has a route test above', () {
      // The routes proven in this group, by blend. This is the list a reviewer should check
      // against the catalog when a blend is added: a blend that can create a fifth body, copy
      // a rank or unify a family opens a route, and an untested route is one that can close
      // in a refactor without anything failing.
      const proven = {
        'sun_dry': 'five_kind', 'chili_oil': 'full_family + perfect_palate',
        'conserva': 'five_kind', 'julienne': 'five_kind',
        'koji': 'full_family', 'levain': 'perfect_palate',
      };
      for (final id in proven.keys) {
        expect(kBlendById[id], isNotNull, reason: '$id was removed but its route test remains');
      }

      // The remaining family rewrites are Chili Oil's verb with a different constant, and
      // `infusion` is that verb sourced from a card instead of a literal. They reach the same
      // recipes by the same route, so they are covered by the hit cases rather than repeated
      // here — but they must keep the shape that makes the route work.
      for (final id in ['sea_salt', 'brine', 'jaggery', 'infusion']) {
        final b = kBlendById[id]!;
        expect(b.effect.keys.any(_familyVerbs.contains), isTrue,
            reason: '$id no longer unifies a family — a secret-recipe route closed silently');
        expect(b.select, greaterThanOrEqualTo(2), reason: '$id can no longer convert a pair');
      }
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

    test('the vectors cover all six ported blends and reach every secret recipe', () {
      final ids = <String>{};
      for (final c in cases) {
        for (final b in (c['before'] as Map<String, dynamic>)['blends'] as List<dynamic>) {
          ids.add(b as String);
        }
      }
      // The ported six, not the whole catalog: the other fourteen have no counterpart in
      // `web/game-core.mjs`, so no JS run can record a vector for them. See the library doc.
      expect(ids, equals(_ported.map((p) => p.$1).toSet()),
          reason: 'a ported blend with no vector is a blend the port could get wrong silently');

      final patterns = cases.map((c) => c['pattern'] as String).toSet();
      for (final p in kSecretPatterns) {
        expect(patterns, contains(p), reason: '$p has no blend vector proving it is reachable');
      }
    });
  });
}

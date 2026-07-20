/// Content tests for the utensil catalog — the guard rail that lets it reach 100+ entries.
///
/// Three jobs, in order of how much they will save you:
///
/// 1. **The DSL allow-list.** `scoreDish` silently ignores a condition or effect key it does
///    not know, so `heat_mul` instead of `heat_mult` ships a utensil that reads correctly in
///    the shop and does nothing in play. Nothing else in the repo catches that: the sim would
///    just report a slightly worse ladder. The table-driven check below fails loudly on any
///    key, family or recipe name outside the allow-list, and it runs over the *whole*
///    catalog, so it covers content nobody has written a focused test for yet.
///
/// 2. **The ported 20 are frozen.** They are pinned against `web/game-core.mjs` by
///    `vectors.json`, so retuning one silently voids the differential guarantee rather than
///    changing a number. [_ported] restates them literally — independent of the fixture file,
///    so it still fires if the vectors are ever regenerated or deleted.
///
/// 3. **Every expansion utensil fires exactly when it should.** One case per utensil: a dish
///    that opens the gate and at least one that does not. The expected numbers come from
///    [_expected], which applies the effect map additively-then-multiplicatively — the order
///    of operations the build spec calls normative — rather than from `scoreDish` itself, so
///    the assertion is a real cross-check and not a restatement of the engine.
library;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// The DSL allow-list — must match `_condMet` and the effect loop in engine.dart.
// ---------------------------------------------------------------------------

const Set<String> _conditionKeys = {
  'all_cards_family', 'contains_family', 'all_cards_same_family', 'min_cards',
  'num_cards', 'pattern_is', 'pattern_at_least', 'is_first_dish', 'is_last_dish',
};

const Set<String> _effectKeys = {
  'flavor_add', 'heat_add', 'heat_mult', 'flavor_per_card', 'heat_per_card',
  'coin_add', 'retrigger_highest', 'copy_right', 'flavor_mult',
};

/// Condition keys whose value names a flavour family.
const Set<String> _familyValued = {'all_cards_family', 'contains_family'};

/// Condition keys whose value names a recipe.
const Set<String> _patternValued = {'pattern_is', 'pattern_at_least'};

/// Condition keys whose value is a card count.
const Set<String> _intValued = {'min_cards', 'num_cards'};

/// Condition keys that are pure flags.
const Set<String> _flagValued = {'all_cards_same_family', 'is_first_dish', 'is_last_dish'};

/// Effect keys carrying a magnitude, as opposed to the two flag effects.
const Set<String> _numericEffects = {
  'flavor_add', 'heat_add', 'heat_mult', 'flavor_per_card', 'heat_per_card', 'coin_add', 'flavor_mult'};

const Map<String, int> _costByRarity = {'common': 4, 'uncommon': 6, 'rare': 9};

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Card _c(String family, int rank) =>
    Card(id: '${family}_$rank', family: family, rank: rank, display: kNames[family]![rank - 1]);

Card _sp(int r) => _c('spicy', r);
Card _sw(int r) => _c('sweet', r);
Card _so(int r) => _c('sour', r);
Card _sa(int r) => _c('salty', r);
Card _um(int r) => _c('umami', r);

/// Three distinct ranks across three families: a High Card holding one of each of
/// Spicy / Sweet / Sour, which is what most `contains_family` gates key off.
final List<Card> _high3 = [_sp(2), _sw(5), _so(9)];
final List<Card> _noSpicy = [_sw(2), _so(5), _um(9)];
final List<Card> _noSweet = [_sp(2), _so(5), _um(9)];
final List<Card> _noSour = [_sp(2), _sw(5), _um(9)];
final List<Card> _withSalty = [_sa(2), _sw(5), _um(9)];
final List<Card> _withUmami = [_um(2), _sw(5), _so(9)];

final List<Card> _allSpicy = [_sp(2), _sp(5), _sp(9)];
final List<Card> _allSweet = [_sw(2), _sw(5), _sw(9)];
final List<Card> _allSour = [_so(2), _so(5), _so(9)];
final List<Card> _allSalty = [_sa(2), _sa(5), _sa(9)];
final List<Card> _allUmami = [_um(2), _um(5), _um(9)];

final List<Card> _one = [_sp(7)];
final List<Card> _pair = [_sp(3), _sw(3)];
final List<Card> _twoPair = [_sp(3), _sw(3), _so(5), _sa(5)];
final List<Card> _threeKind = [_sp(4), _sw(4), _so(4)];
final List<Card> _threeKindNoSweet = [_sp(4), _so(4), _sa(4)];
final List<Card> _straight = [_sp(1), _sw(2), _so(3), _sa(4), _um(5)];
final List<Card> _flush = [_sp(1), _sp(2), _sp(3), _sp(4), _sp(6)];
final List<Card> _fullHouse = [_sp(4), _sw(4), _so(4), _sa(7), _um(7)];
final List<Card> _fourKind = [_sp(5), _sw(5), _so(5), _sa(5)];
final List<Card> _straightFlush = [_sp(1), _sp(2), _sp(3), _sp(4), _sp(5)];

/// Four cards including a Salty one; four distinct ranks, but a Straight needs five cards,
/// so this stays a High Card and only the card-count gates react to it.
final List<Card> _four3Salty = [_sa(1), _sw(2), _so(3), _um(4)];
final List<Card> _four3NoSalty = [_sp(1), _sw(2), _so(3), _um(4)];
final List<Card> _three3Salty = [_sa(1), _sw(2), _so(3)];
final List<Card> _pairSour = [_so(3), _sw(5)];

/// Three of a Kind with no Sour card — the counter-example for `sumac_mill`'s family clause,
/// mirroring how [_threeKindNoSweet] serves `maple_evaporator`.
final List<Card> _threeKindNoSour = [_sp(4), _sw(4), _sa(4)];

/// Five cards of one rank across five families: the lowest secret recipe, and the only dish
/// that opens `jubako`'s gate. Reachable in play only through blend duplication.
final List<Card> _fiveKind = [_sp(5), _sw(5), _so(5), _sa(5), _um(5)];

/// One dish, plus the service position it is played from.
class _Dish {
  const _Dish(this.cards, {this.first = false, this.last = false});

  final List<Card> cards;
  final bool first;
  final bool last;
}

ScoreResult _score(_Dish d, List<String> utensils) => scoreDish(
  d.cards,
  ScoreContext(
    utensils: utensils.map((id) => kUtensilById[id]!).toList(),
    isFirstDish: d.first,
    isLastDish: d.last,
  ),
);

/// Applies [effect] to a baseline the way the build spec's §4 says it must: every additive
/// term first, then the heat multiplier. Written independently of `scoreDish` on purpose —
/// if the engine ever multiplies before adding, this disagrees.
({double flavor, double heat, int coins}) _expected(
  Map<String, Object?> effect,
  ScoreResult base,
  int cardCount,
) {
  var flavor = base.flavor;
  var heat = base.heat;
  // Retriggers run their own pass ahead of the per-dish utensils (§4 step 5 before step 6),
  // and re-score the highest-intensity *scoring* card — extras played beyond the pattern are
  // never the target. Computed from `cardContribution` rather than from `scoreDish`, so this
  // stays a cross-check of the retrigger pass and not a restatement of it.
  if (effect['retrigger_highest'] == true && base.scoring.isNotEmpty) {
    var hi = base.scoring.first;
    for (final c in base.scoring) {
      if (c.rank > hi.rank) hi = c;
    }
    final c = cardContribution(hi, const ScoreContext());
    flavor += c.dF;
    heat += c.dH;
  }
  final flavorAdd = effect['flavor_add'] as num?;
  if (flavorAdd != null) flavor += flavorAdd;
  final heatAdd = effect['heat_add'] as num?;
  if (heatAdd != null) heat += heatAdd;
  final flavorPer = effect['flavor_per_card'] as num?;
  if (flavorPer != null) flavor += flavorPer * cardCount;
  final heatPer = effect['heat_per_card'] as num?;
  if (heatPer != null) heat += heatPer * cardCount;
  // Multiplicative terms land after every additive one, matching scoreDish.
  final flavorMult = effect['flavor_mult'] as num?;
  if (flavorMult != null) flavor *= flavorMult;
  final heatMult = effect['heat_mult'] as num?;
  if (heatMult != null) heat *= heatMult;
  return (flavor: flavor, heat: heat, coins: ((effect['coin_add'] as num?) ?? 0).toInt());
}

/// One utensil's gate: the dish that must fire it, and the dishes that must not.
///
/// [misses] is a list because a compound condition has one miss per clause — `idli_steamer`
/// gates on Sour *and* 3+ ingredients, and a single counter-example would leave half of it
/// untested.
class _Gate {
  const _Gate(this.id, {required this.hit, required this.misses});

  final String id;
  final _Dish hit;
  final List<_Dish> misses;
}

// ---------------------------------------------------------------------------
// The frozen M0 set — ported from web/game-core.mjs, pinned by vectors.json.
// ---------------------------------------------------------------------------

const List<(String, String, int, Map<String, Object?>?, Map<String, Object?>)> _ported = [
  ('iron_tawa', 'common', 4, {'min_cards': 3}, {'flavor_add': 30}),
  ('mint_garnish', 'common', 4, {'contains_family': 'sour'}, {'heat_add': 4}),
  ('salt_cellar', 'common', 4, {'contains_family': 'salty'}, {'heat_add': 3}),
  ('honey_jar', 'common', 4, {'contains_family': 'sweet'}, {'flavor_add': 25}),
  ('stock_pot', 'common', 4, {'contains_family': 'umami'}, {'heat_add': 2}),
  ('street_cart', 'common', 4, null, {'coin_add': 1}),
  ('big_spoon', 'common', 4, {'pattern_is': 'pair'}, {'flavor_add': 20}),
  ('rice_cooker', 'common', 4, {'pattern_is': 'three_kind'}, {'flavor_add': 30}),
  ('tandoor', 'uncommon', 6, {'all_cards_family': 'spicy'}, {'heat_mult': 1.5}),
  ('pressure_cooker', 'uncommon', 6, null, {'retrigger_highest': true}),
  ('wok', 'uncommon', 6, {'all_cards_same_family': true}, {'heat_mult': 1.5}),
  ('chai_stall', 'uncommon', 6, {'pattern_is': 'pair'}, {'coin_add': 2}),
  ('bamboo_steamer', 'uncommon', 6, {'num_cards': 3}, {'heat_add': 5}),
  ('butchers_block', 'uncommon', 6, {'pattern_at_least': 'full_house'}, {'flavor_add': 40}),
  ('ice_box', 'uncommon', 6, {'is_first_dish': true}, {'heat_mult': 2}),
  ('griddle', 'uncommon', 6, null, {'heat_per_card': 1}),
  ('clay_handi', 'rare', 9, {'is_last_dish': true}, {'heat_mult': 3}),
  ('grandmother_ladle', 'rare', 9, null, {'copy_right': true}),
  ('golden_sieve', 'rare', 9, {'pattern_is': 'flush'}, {'flavor_add': 50, 'heat_add': 3}),
  ('emperors_wok', 'rare', 9, {'num_cards': 5}, {'heat_mult': 2}),
];

final Set<String> _portedIds = _ported.map((p) => p.$1).toSet();

/// Everything the expansion added — i.e. the catalog minus the frozen set.
List<Utensil> get _expansion => kUtensils.where((u) => !_portedIds.contains(u.id)).toList();

// ---------------------------------------------------------------------------

void main() {
  group('DSL allow-list (a typo\'d key ships a utensil that silently does nothing)', () {
    for (final u in kUtensils) {
      test('${u.id} uses only keys the engine implements', () {
        for (final entry in (u.condition ?? const <String, Object?>{}).entries) {
          final k = entry.key;
          final v = entry.value;
          expect(_conditionKeys, contains(k), reason: '${u.id}: unknown condition key "$k"');
          if (_familyValued.contains(k)) {
            expect(kFamilies, contains(v), reason: '${u.id}: "$k" names no flavour family');
          } else if (_patternValued.contains(k)) {
            expect(kPatternOrder, contains(v), reason: '${u.id}: "$k" names no recipe');
          } else if (_intValued.contains(k)) {
            expect(v, isA<int>(), reason: '${u.id}: "$k" must be a card count');
            expect(v! as int, inInclusiveRange(1, 5), reason: '${u.id}: "$k" out of dish range');
          } else if (_flagValued.contains(k)) {
            expect(v, isTrue, reason: '${u.id}: flag "$k" is only meaningful when true');
          }
        }
        for (final entry in u.effect.entries) {
          final k = entry.key;
          final v = entry.value;
          expect(_effectKeys, contains(k), reason: '${u.id}: unknown effect key "$k"');
          if (_numericEffects.contains(k)) {
            expect(v, isA<num>(), reason: '${u.id}: "$k" must carry a magnitude');
            expect(v! as num, greaterThan(0), reason: '${u.id}: "$k" must be positive');
          } else {
            expect(v, isTrue, reason: '${u.id}: flag effect "$k" is only meaningful when true');
          }
        }
        expect(u.effect, isNotEmpty, reason: '${u.id} has no effect at all');
        expect(const ['on_dish', 'on_card'], contains(u.trigger), reason: '${u.id}: bad trigger');
      });
    }
  });

  group('catalog hygiene', () {
    test('ids are unique', () {
      final seen = <String>{};
      for (final u in kUtensils) {
        expect(seen.add(u.id), isTrue, reason: 'duplicate utensil id "${u.id}"');
      }
      expect(kUtensilById.length, equals(kUtensils.length), reason: 'the id index lost an entry');
    });

    test('every utensil has a name and shop text', () {
      for (final u in kUtensils) {
        expect(u.name.trim(), isNotEmpty, reason: '${u.id} has no name');
        expect(u.text.trim(), isNotEmpty, reason: '${u.id} has no shop text');
      }
    });

    test('cost follows rarity', () {
      for (final u in kUtensils) {
        expect(_costByRarity.keys, contains(u.rarity), reason: '${u.id}: unknown rarity');
        expect(u.cost, equals(_costByRarity[u.rarity]),
            reason: '${u.id} is ${u.rarity} but costs ${u.cost}');
      }
    });

    test('the rarity mix still roughly tracks the shop weights', () {
      final counts = <String, int>{};
      for (final u in kUtensils) {
        counts[u.rarity] = (counts[u.rarity] ?? 0) + 1;
      }
      // Deliberately loose: this is a smell test for a pool that has drifted all-rare or
      // all-common, not a spec. kRarityWeights is 60/30/10.
      final total = kUtensils.length;
      expect((counts['common'] ?? 0) / total, greaterThan(0.45), reason: 'too few commons');
      expect((counts['rare'] ?? 0) / total, lessThan(0.25), reason: 'too many rares');
    });

    test('no utensil is unreachable from the shop rarity roll', () {
      final rarities = kRarityWeights.map((w) => w.$1).toSet();
      for (final u in kUtensils) {
        expect(rarities, contains(u.rarity), reason: '${u.id} can never be rolled');
      }
    });
  });

  group('the ported M0 set is frozen (vectors.json pins these against the JS engine)', () {
    test('all 20 are present, in order, at the head of the catalog', () {
      expect(kUtensils.length, greaterThanOrEqualTo(_ported.length));
      for (var i = 0; i < _ported.length; i++) {
        expect(kUtensils[i].id, equals(_ported[i].$1),
            reason: 'ported utensil $i moved — shop rolls are indexed off this order');
      }
    });

    for (final p in _ported) {
      test('${p.$1} is unchanged', () {
        final u = kUtensilById[p.$1];
        expect(u, isNotNull, reason: '${p.$1} was removed from the catalog');
        expect(u!.rarity, equals(p.$2), reason: '${p.$1} rarity retuned');
        expect(u.cost, equals(p.$3), reason: '${p.$1} cost retuned');
        expect(u.condition, equals(p.$4), reason: '${p.$1} condition retuned');
        expect(u.effect, equals(p.$5), reason: '${p.$1} effect retuned');
      });
    }
  });

  // -------------------------------------------------------------------------
  // Expansion gates
  // -------------------------------------------------------------------------

  final gates = <_Gate>[
    // --- flavour families: contains one ---
    _Gate('masala_dabba', hit: _Dish(_high3), misses: [_Dish(_noSpicy)]),
    _Gate('molcajete', hit: _Dish(_high3), misses: [_Dish(_noSpicy)]),
    _Gate('piloncillo_cone', hit: _Dish(_high3), misses: [_Dish(_noSweet)]),
    _Gate('achaar_jar', hit: _Dish(_high3), misses: [_Dish(_noSour)]),
    _Gate('anchovy_tin', hit: _Dish(_withSalty), misses: [_Dish(_high3)]),
    _Gate('katsuobushi_box', hit: _Dish(_withUmami), misses: [_Dish(_high3)]),
    // --- flavour families: all of one ---
    _Gate('tadka_pan', hit: _Dish(_allSpicy), misses: [_Dish(_high3)]),
    _Gate('baklava_tray', hit: _Dish(_allSweet), misses: [_Dish(_high3)]),
    _Gate('onggi_crock', hit: _Dish(_allSour), misses: [_Dish(_high3)]),
    _Gate('salt_block', hit: _Dish(_allSalty), misses: [_Dish(_high3)]),
    _Gate('kombu_basket', hit: _Dish(_allUmami), misses: [_Dish(_high3)]),
    // --- recipes ---
    _Gate('tapas_plate', hit: _Dish(_high3), misses: [_Dish(_pair)]),
    _Gate('dim_sum_basket', hit: _Dish(_pair), misses: [_Dish(_high3)]),
    _Gate('meze_tray', hit: _Dish(_twoPair), misses: [_Dish(_pair)]),
    _Gate('mercado_stall', hit: _Dish(_twoPair), misses: [_Dish(_pair)]),
    _Gate('donabe', hit: _Dish(_threeKind), misses: [_Dish(_pair)]),
    _Gate('thali_plate', hit: _Dish(_straight), misses: [_Dish(_flush)]),
    _Gate('bento_box', hit: _Dish(_straight), misses: [_Dish(_flush)]),
    _Gate('chitarra', hit: _Dish(_straight), misses: [_Dish(_threeKind)]),
    _Gate('paella_pan', hit: _Dish(_flush), misses: [_Dish(_straight)]),
    _Gate('cazuela', hit: _Dish(_fullHouse), misses: [_Dish(_threeKind)]),
    _Gate('karahi', hit: _Dish(_fourKind), misses: [_Dish(_threeKind)]),
    // --- dish shape ---
    _Gate('pilon', hit: _Dish(_one), misses: [_Dish(_pair)]),
    _Gate('tortilla_press', hit: _Dish(_pair), misses: [_Dish(_threeKind)]),
    _Gate('banana_leaf', hit: _Dish(_straight), misses: [_Dish(_fourKind)]),
    // --- compound conditions: one miss per clause ---
    _Gate('idli_steamer', hit: _Dish(_high3), misses: [_Dish(_pairSour), _Dish(_noSour)]),
    _Gate('garum_amphora',
        hit: _Dish(_four3Salty), misses: [_Dish(_three3Salty), _Dish(_four3NoSalty)]),
    // --- service position ---
    _Gate('wire_spider', hit: _Dish(_high3, first: true), misses: [_Dish(_high3)]),
    _Gate('sac_lid', hit: _Dish(_high3, last: true), misses: [_Dish(_high3)]),
    // --- uncommons ---
    _Gate('chile_roaster', hit: _Dish(_allSpicy), misses: [_Dish(_high3)]),
    _Gate('parmesan_wheel', hit: _Dish(_allUmami), misses: [_Dish(_high3)]),
    _Gate('cataplana', hit: _Dish(_twoPair), misses: [_Dish(_pair)]),
    _Gate('sushi_geta', hit: _Dish(_straight), misses: [_Dish(_flush)]),
    _Gate('comal', hit: _Dish(_flush), misses: [_Dish(_straight)]),
    _Gate('metate', hit: _Dish(_pair), misses: [_Dish(_threeKind)]),
    _Gate('saj_griddle', hit: _Dish(_straight), misses: [_Dish(_threeKind)]),
    _Gate('braai_grid', hit: _Dish(_fullHouse), misses: [_Dish(_flush)]),
    _Gate('mangal_grill', hit: _Dish(_fourKind), misses: [_Dish(_fullHouse)]),
    _Gate('billig', hit: _Dish(_high3, first: true), misses: [_Dish(_high3)]),
    _Gate('tagine', hit: _Dish(_high3, last: true), misses: [_Dish(_high3)]),
    _Gate('hawker_stall', hit: _Dish(_high3), misses: [_Dish(_pair)]),
    // --- rares ---
    _Gate('yanagiba', hit: _Dish(_one), misses: [_Dish(_pair)]),
    _Gate('kazan', hit: _Dish(_fourKind), misses: [_Dish(_threeKind)]),
    _Gate('maple_evaporator',
        hit: _Dish(_threeKind), misses: [_Dish(_threeKindNoSweet), _Dish(_pair)]),
    _Gate('asado_cross', hit: _Dish(_straightFlush), misses: [_Dish(_flush)]),
    // flavour multipliers
    _Gate('copper_degchi', hit: _Dish(_four3Salty), misses: [_Dish(_pair)]),
    _Gate('clay_tandir', hit: _Dish(_flush), misses: [_Dish(_pair)]),
    _Gate('stone_mortar', hit: _Dish(_one), misses: [_Dish(_pair)]),
    _Gate('harvest_basket', hit: _Dish(_fullHouse), misses: [_Dish(_flush)]),

    // === v1.0 pass ========================================================
    // --- commons: the dish-shape and timing rungs the first pass left open ---
    _Gate('ttukbaegi', hit: _Dish(_four3Salty), misses: [_Dish(_high3)]),
    _Gate('mezzaluna', hit: _Dish(_pair), misses: [_Dish(_high3)]),
    _Gate('jebena', hit: _Dish(_high3, first: true), misses: [_Dish(_high3)]),
    _Gate('cezve', hit: _Dish(_high3, last: true), misses: [_Dish(_high3)]),
    _Gate('miso_keg', hit: _Dish(_allSalty), misses: [_Dish(_high3)]),
    _Gate('berbere_mill',
        hit: _Dish(_four3NoSalty), misses: [_Dish(_high3), _Dish(_four3Salty)]),
    // The conditional retrigger. `_expected` re-scores the highest scoring card for this one,
    // so the hit case checks the retrigger pass actually ran, not just that nothing crashed.
    _Gate('otoshibuta', hit: _Dish(_threeKind), misses: [_Dish(_pair)]),
    // --- uncommons: recipe rungs, the last two family multipliers, flavour below Rare ---
    _Gate('gamasot', hit: _Dish(_threeKind), misses: [_Dish(_pair)]),
    _Gate('tiella', hit: _Dish(_fullHouse), misses: [_Dish(_flush)]),
    _Gate('zeer', hit: _Dish(_allSalty), misses: [_Dish(_high3)]),
    _Gate('tamarind_press', hit: _Dish(_allSour), misses: [_Dish(_high3)]),
    _Gate('sugarcane_press', hit: _Dish(_allSweet), misses: [_Dish(_high3)]),
    _Gate('suribachi', hit: _Dish(_high3), misses: [_Dish(_pair)]),
    _Gate('dashi_kettle', hit: _Dish(_withUmami), misses: [_Dish(_high3)]),
    _Gate('mesob', hit: _Dish(_high3, last: true), misses: [_Dish(_high3)]),
    _Gate('kanoun', hit: _Dish(_twoPair), misses: [_Dish(_pair)]),
    _Gate('chatti', hit: _Dish(_allSpicy), misses: [_Dish(_high3)]),
    _Gate('souk_stall', hit: _Dish(_allSpicy), misses: [_Dish(_high3)]),
    // --- rares: five of the eight multiply flavour ---
    _Gate('mole_olla', hit: _Dish(_flush), misses: [_Dish(_straight)]),
    _Gate('pachamanca_stones', hit: _Dish(_straight), misses: [_Dish(_threeKind)]),
    _Gate('sumac_mill',
        hit: _Dish(_threeKind), misses: [_Dish(_threeKindNoSour), _Dish(_pairSour)]),
    _Gate('couscoussier', hit: _Dish(_straight), misses: [_Dish(_fourKind)]),
    _Gate('uruli', hit: _Dish(_fourKind), misses: [_Dish(_fullHouse)]),
    _Gate('konro_grill', hit: _Dish(_allSpicy), misses: [_Dish(_high3)]),
    _Gate('tiffin_carrier', hit: _Dish(_threeKind), misses: [_Dish(_pair)]),
    _Gate('jubako', hit: _Dish(_fiveKind), misses: [_Dish(_fourKind)]),
  ];

  group('expansion utensils fire on their gate and only on their gate', () {
    test('every expansion utensil has a gate case', () {
      final tested = gates.map((g) => g.id).toSet();
      final shipped = _expansion.map((u) => u.id).toSet();
      expect(tested.difference(shipped), isEmpty, reason: 'gate case for a utensil that is gone');
      expect(shipped.difference(tested), isEmpty,
          reason: 'new utensil with no gate case — add one to `gates`');
      expect(gates.length, equals(_expansion.length), reason: 'duplicate gate case');
    });

    for (final g in gates) {
      final u = kUtensilById[g.id];
      test('${g.id} — ${u?.text ?? "MISSING"}', () {
        expect(u, isNotNull, reason: '${g.id} is not in the catalog');

        final base = _score(g.hit, const []);
        final withIt = _score(g.hit, [g.id]);
        final want = _expected(u!.effect, base, g.hit.cards.length);

        expect(withIt.flavor, equals(want.flavor), reason: '${g.id} did not fire (flavor)');
        expect(withIt.heat, equals(want.heat), reason: '${g.id} did not fire (heat)');
        expect(withIt.coins, equals(want.coins), reason: '${g.id} did not fire (coins)');
        expect(withIt.score, equals((want.flavor * want.heat).floor()),
            reason: '${g.id}: score is not floor(flavor x heat)');
        // A gate nobody can tell fired is a content bug even if the maths is right.
        expect(
          withIt.flavor != base.flavor || withIt.heat != base.heat || withIt.coins != base.coins,
          isTrue,
          reason: '${g.id} changed nothing on a dish that meets its condition',
        );

        for (var i = 0; i < g.misses.length; i++) {
          final miss = g.misses[i];
          final off = _score(miss, const []);
          final on = _score(miss, [g.id]);
          expect(on.flavor, equals(off.flavor), reason: '${g.id} leaked flavor on miss $i');
          expect(on.heat, equals(off.heat), reason: '${g.id} leaked heat on miss $i');
          expect(on.coins, equals(off.coins), reason: '${g.id} leaked coins on miss $i');
        }
      });
    }
  });

  group('coverage the expansion was written to provide', () {
    test('every recipe is rewarded by at least one utensil', () {
      final direct = <String>{};
      for (final u in kUtensils) {
        final isPattern = u.condition?['pattern_is'];
        if (isPattern is String) direct.add(isPattern);
        // `pattern_at_least` rewards its own rung and everything above it.
        final atLeast = u.condition?['pattern_at_least'];
        if (atLeast is String) {
          direct.addAll(kPatternOrder.skip(kPatternOrder.indexOf(atLeast)));
        }
      }
      for (final p in kPatternOrder) {
        expect(direct, contains(p), reason: 'no utensil rewards $p');
      }
    });

    test('every flavour family is rewarded by at least one utensil', () {
      final families = <String>{};
      for (final u in kUtensils) {
        for (final k in _familyValued) {
          final v = u.condition?[k];
          if (v is String) families.add(v);
        }
      }
      expect(families, containsAll(kFamilies), reason: 'a family has no utensil of its own');
    });

    test('no common carries a heat multiplier', () {
      // Multipliers compound across the five slots, so cheap ones stack out of control.
      // Commons add; uncommons and rares multiply.
      for (final u in kUtensils) {
        if (u.rarity != 'common') continue;
        expect(u.effect.containsKey('heat_mult'), isFalse,
            reason: '${u.id} is a common with a heat multiplier');
      }
    });

    test('no common carries a flavour multiplier either', () {
      // Same argument as the heat rule above, and it needs stating separately because
      // `flavor_mult` arrived after that test did: multipliers compound across the five
      // slots, so a 4-coin ×1.5 is a trap. Commons add; uncommons and rares multiply.
      for (final u in kUtensils) {
        if (u.rarity != 'common') continue;
        expect(u.effect.containsKey('flavor_mult'), isFalse,
            reason: '${u.id} is a common with a flavour multiplier');
      }
    });

    test('flavour is a real second scaling axis, not a rare-only curiosity', () {
      // The v1.0 pass exists partly because heat was the only multiplicative track, which
      // made additive-flavour commons go dead as Kitchen level inflated the base. If a future
      // retune strips flavor_mult back to a handful of Rares, that regression is silent —
      // every other test still passes and the sim ladder barely twitches.
      final flavourMults = kUtensils.where((u) => u.effect.containsKey('flavor_mult')).toList();
      final heatMults = kUtensils.where((u) => u.effect.containsKey('heat_mult')).toList();
      expect(flavourMults.length, greaterThanOrEqualTo(10),
          reason: 'flavour multipliers have thinned out to a curiosity again');
      expect(flavourMults.length, greaterThanOrEqualTo((heatMults.length * 0.6).ceil()),
          reason: 'flavour is falling behind heat as a multiplicative track');
      expect(flavourMults.any((u) => u.rarity == 'uncommon'), isTrue,
          reason: 'no flavour multiplier below Rare — the axis is unreachable mid-run');
    });

    test('a retrigger obeys its condition', () {
      // The retrigger pass used to skip _condMet, so a conditional retrigger fired on every
      // dish and its shop text was a lie. It never surfaced because Pressure Cooker is
      // unconditional — which is exactly why this is asserted behaviourally now rather than
      // left as a rule about what content may not do.
      const gated = Utensil(
        id: '_test_gated_retrigger', name: 'Gated', rarity: 'rare', cost: 9,
        trigger: 'on_card', condition: {'pattern_is': 'flush'},
        effect: {'retrigger_highest': true}, text: 'test',
      );
      final flush = [
        for (final r in [2, 4, 6, 8, 10])
          Card(id: 'spicy_$r', family: 'spicy', rank: r, display: 'x'),
      ];
      final pair = [
        const Card(id: 'spicy_3', family: 'spicy', rank: 3, display: 'x'),
        const Card(id: 'sweet_3', family: 'sweet', rank: 3, display: 'x'),
      ];

      double flavorWith(List<Card> cards, List<Utensil> rack) =>
          scoreDish(cards, ScoreContext(utensils: rack)).flavor;

      expect(flavorWith(flush, const [gated]) - flavorWith(flush, const []), 10,
          reason: 'condition met: the highest card (rank 10) scores twice');
      expect(flavorWith(pair, const [gated]) - flavorWith(pair, const []), 0,
          reason: 'condition unmet: it must not fire at all');
    });

    test('extra effects alongside a retrigger are still skipped by the engine', () {
      for (final u in kUtensils) {
        if (u.effect['retrigger_highest'] != true) continue;
        expect(u.effect.keys.toList(), equals(['retrigger_highest']),
            reason: '${u.id}: the engine ignores other effects on a retrigger utensil');
      }
    });

    test('copy_right is the only effect its utensil carries', () {
      for (final u in kUtensils) {
        if (u.effect['copy_right'] != true) continue;
        expect(u.effect.keys.toList(), equals(['copy_right']),
            reason: '${u.id}: the engine skips other effects on a copier');
      }
    });
  });

  group('what a fresh profile can be offered', () {
    // The expansion commons and uncommons ship unlocked: gating 45 utensils behind
    // achievements that don't exist yet would make them unreachable, which is strictly
    // worse than unbalanced. The build-defining rares stay locked so the unlock ladder
    // still has a payoff to hand out.
    test('expansion rares are NOT starters — the ladder needs something to give', () {
      for (final u in _expansion.where((u) => u.rarity == 'rare')) {
        expect(kStartUtensils, isNot(contains(u.id)),
            reason: '${u.id} is build-defining and should be earned');
      }
    });

    test('expansion commons and uncommons ARE reachable from run one', () {
      for (final u in _expansion.where((u) => u.rarity != 'rare')) {
        expect(kStartUtensils, contains(u.id),
            reason: '${u.id} would otherwise be unreachable — nothing grants it yet');
      }
    });

    test('every starter id names a real utensil', () {
      for (final id in kStartUtensils) {
        expect(kUtensilById[id], isNotNull, reason: '$id is a typo — it can never be offered');
      }
    });

    test('a fresh profile sees exactly the starter set, in catalog order', () {
      profile = defaultProfile();
      final pool = unlockedUtensilPool().map((u) => u.id).toList();
      expect(pool.toSet(), equals(kStartUtensils.toSet()),
          reason: 'the starting pool moved — every recorded run trace depends on it');
      // The pool is ordered by [kUtensils], not by unlock order: `rollOffers` indexes into it
      // with the seeded RNG, so a reshuffle here silently re-rolls every existing seed.
      expect(pool, equals(kUtensils.map((u) => u.id).where(pool.contains).toList()),
          reason: 'the starting pool is no longer in catalog order');
    });

    test('the Royal deck draws its free Rare from a pool that content cannot widen', () {
      // `newRun` picks with the seeded RNG, so if this list grew with the catalog every
      // existing Royal seed would open differently after each content drop.
      for (final id in kStarterRareUtensils) {
        final u = kUtensilById[id];
        expect(u, isNotNull, reason: '$id is not in the catalog');
        expect(u!.rarity, equals('rare'), reason: '$id is not a Rare');
        expect(_portedIds, contains(id), reason: '$id is not part of the frozen M0 set');
      }
    });
  });
}

/// §CONTENT ported to Dart — the M0 catalogs as compile-time data.
///
/// These are a direct port of the tuned web build, which is the behavioural source of
/// truth (see CLAUDE.md). `packages/content` will later load and validate the same shapes
/// from JSON so designers can retune without a rebuild; until then these constants are it.
///
/// Tuning lives here, not in the engine: change a number, rerun the sim. Two values are
/// load-bearing and must not be casually reverted — [kLevelBonus] (Festival scaling, without
/// which a maxed build caps ~15k and Naples is unreachable) and Kochi's 1200 boss target
/// (2000 was mathematically unwinnable under the Minimalist's 3-card cap).
library;

import 'dart:math' as math;

import 'models.dart';

/// Ingredient display names, indexed by rank-1 within each family.
const Map<String, List<String>> kNames = {
  'spicy': ['Paprika', 'Black Pepper', 'Green Chili', 'Mustard Seed', 'Cayenne', 'Red Chili', "Bird's Eye Chili", 'Scotch Bonnet', 'Ghost Pepper', 'Carolina Reaper'],
  'sweet': ['Jaggery', 'Honey', 'Date', 'Fig', 'Palm Sugar', 'Maple', 'Condensed Milk', 'Caramel', 'Dark Chocolate', 'Rose Syrup'],
  'sour': ['Lime', 'Lemon', 'Tamarind', 'Green Mango', 'Yogurt', 'Vinegar', 'Kokum', 'Sumac', 'Amchur', 'Fermented Lime'],
  'salty': ['Sea Salt', 'Rock Salt', 'Soy Sauce', 'Fish Sauce', 'Miso', 'Olives', 'Capers', 'Anchovy', 'Preserved Lemon', 'Bottarga'],
  'umami': ['Mushroom', 'Tomato', 'Seaweed', 'Parmesan', 'Dashi', 'Soy Bean', 'Cured Ham', 'Dried Shiitake', 'Aged Cheese', 'Bonito Flake'],
};

/// A starting-deck variant.
class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.identity,
    this.familyDelta = const {},
    this.trim = 0,
    this.startBlends = const [],
    this.startRareUtensil = false,
    this.cooks,
    this.utensilSlots,
    this.reserved = false,
  });

  final String id;
  final String name;
  final String identity;

  /// Add (positive) or remove (negative) cards of a family. Insertion order is significant.
  final Map<String, int> familyDelta;

  /// Remove this many low-rank cards.
  final int trim;
  final List<String> startBlends;
  final bool startRareUtensil;
  final int? cooks;
  final int? utensilSlots;
  final bool reserved;
}

const List<Deck> kDecks = [
  Deck(id: 'home', name: 'Home Kitchen', identity: 'Balanced 52-card pantry'),
  Deck(
    id: 'coastal',
    name: 'Coastal Pantry',
    identity: '+4 Sour, -4 Salty; start with 1 Sun-Dry',
    familyDelta: {'sour': 4, 'salty': -4},
    startBlends: ['sun_dry'],
  ),
  Deck(
    id: 'royal',
    name: 'Royal Kitchen',
    identity: '44 cards; start with a random Rare utensil',
    trim: 8,
    startRareUtensil: true,
  ),
  Deck(id: 'hawker', name: 'Street Hawker', identity: 'Cooks 5, utensil slots 4', cooks: 5, utensilSlots: 4),
  Deck(id: 'monsoon', name: 'Monsoon Larder', identity: 'Ships with v1.1 Monsoon Mode', reserved: true),
];

final Map<String, Deck> kDeckById = {for (final d in kDecks) d.id: d};

/// The full pantry: 5 families x ranks 1-10, plus 2 prized cards, then deck modifiers.
List<Card> buildPantry([Deck? deck]) {
  var cards = <Card>[];
  for (final fam in kFamilies) {
    for (var r = 1; r <= 10; r++) {
      cards.add(Card(id: '${fam}_$r', family: fam, rank: r, display: kNames[fam]![r - 1]));
    }
  }
  cards.add(const Card(id: 'prized_saffron', family: 'umami', rank: 10, display: 'Saffron', prized: true));
  cards.add(const Card(id: 'prized_ghee', family: 'sweet', rank: 10, display: 'Ghee', prized: true));
  if (deck == null) return cards;

  for (final entry in deck.familyDelta.entries) {
    final fam = entry.key;
    final d = entry.value;
    if (d > 0) {
      const rk = [3, 5, 7, 9];
      for (var i = 0; i < d; i++) {
        final r = rk[i % 4];
        cards.add(Card(id: '${fam}_x$i', family: fam, rank: r, display: kNames[fam]![r - 1]));
      }
    } else if (d < 0) {
      var rm = -d;
      cards = cards.where((c) {
        if (rm > 0 && c.family == fam && !c.prized && c.rank <= 4) {
          rm--;
          return false;
        }
        return true;
      }).toList();
    }
  }
  if (deck.trim > 0) {
    var t = deck.trim;
    cards = cards.where((c) {
      if (t > 0 && !c.prized && c.rank <= 2) {
        t--;
        return false;
      }
      return true;
    }).toList();
  }
  return cards;
}

/// Recipe strength order, weakest to strongest. Index position backs `pattern_at_least`.
const List<String> kPatternOrder = [
  'high_card', 'pair', 'two_pair', 'three_kind', 'straight', 'flush',
  'full_house', 'four_kind', 'straight_flush', 'five_kind', 'full_family', 'perfect_palate',
];

/// Only reachable by blend manipulation; shown as ??? in the Recipe Book until discovered.
const List<String> kSecretPatterns = ['five_kind', 'full_family', 'perfect_palate'];

/// Base flavour and heat per recipe (concept doc §3.2 / build spec §4).
const Map<String, (int flavor, int heat)> kRecipe = {
  'high_card': (5, 1), 'pair': (10, 2), 'two_pair': (20, 2),
  'three_kind': (30, 3), 'straight': (30, 4), 'flush': (35, 4),
  'full_house': (40, 4), 'four_kind': (60, 7), 'straight_flush': (100, 8),
  'five_kind': (120, 10), 'full_family': (130, 12), 'perfect_palate': (160, 14),
};

/// Per-Kitchen-level growth. THE scaling engine — see the library doc above.
const Map<String, (int flavor, int heat)> kLevelBonus = {
  'high_card': (4, 1), 'pair': (8, 1), 'two_pair': (12, 1),
  'three_kind': (16, 2), 'straight': (20, 2), 'flush': (22, 2),
  'full_house': (28, 3), 'four_kind': (40, 4), 'straight_flush': (70, 5),
  'five_kind': (80, 6), 'full_family': (90, 7), 'perfect_palate': (110, 8),
};

const Map<String, String> kGenericNames = {
  'high_card': 'High Card', 'pair': 'Pair', 'two_pair': 'Two Pair', 'three_kind': 'Three of a Kind',
  'straight': 'Straight', 'flush': 'Flush', 'full_house': 'Full House', 'four_kind': 'Four of a Kind',
  'straight_flush': 'Straight Flush', 'five_kind': 'Five of a Kind', 'full_family': 'Family Feast',
  'perfect_palate': 'Perfect Palate',
};

/// The signature global mechanic: the same pattern is named after a local dish per city.
/// Pure data, zero mechanical cost, maximum cultural connection (concept doc §2.1).
///
/// Every city in [kCityPool] must have all 12 [kPatternOrder] entries — `catalog_test.dart`
/// asserts it, and [dishName] throws rather than falling back, because a silent fallback to
/// "three_kind" on a city someone forgot to fill in is exactly the bug that ships.
///
/// The names are researched, not improvised: real dishes, correctly spelled, in the escalating
/// order the recipe ladder implies (a street bite, a shared plate, the iconic main, the
/// city's signature, the banquet). The last three rows are the secret recipes and follow the
/// established construction — an English modifier on a local noun ("Royal Sadya", "Pure
/// Omakase"), and a genuine regal or emblematic title for the apex.
const Map<String, Map<String, String>> kDishNames = {
  'kochi': {'high_card': 'Street Snack', 'pair': 'Chaat', 'two_pair': 'Meals Combo', 'three_kind': 'Curry', 'straight': 'Sadya', 'flush': 'Signature Thali', 'full_house': 'Feast', 'four_kind': 'Royal Curry', 'straight_flush': 'Royal Biryani', 'five_kind': 'Royal Sadya', 'full_family': 'Purist Thali', 'perfect_palate': 'The Maharaja'},
  'tokyo': {'high_card': 'Bento Bite', 'pair': 'Onigiri', 'two_pair': 'Teishoku', 'three_kind': 'Ramen', 'straight': 'Sushi Set', 'flush': 'Omakase', 'full_house': 'Donburi Feast', 'four_kind': 'Wagyu Course', 'straight_flush': 'Kaiseki', 'five_kind': "Emperor's Kaiseki", 'full_family': 'Pure Omakase', 'perfect_palate': 'The Shogun'},
  'naples': {'high_card': 'Cicchetti', 'pair': 'Bruschetta', 'two_pair': 'Antipasti', 'three_kind': 'Risotto', 'straight': 'Primi e Secondi', 'flush': 'Margherita', 'full_house': 'Festa', 'four_kind': 'Quattro Formaggi', 'straight_flush': "Nonna's Feast", 'five_kind': 'Grand Festa', 'full_family': 'Monovarietale', 'perfect_palate': 'Il Capolavoro'},
  'bangkok': {'high_card': 'Khanom Krok', 'pair': 'Som Tam', 'two_pair': 'Khao Gaeng', 'three_kind': 'Pad Thai', 'straight': 'Samrap', 'flush': 'Tom Yum Goong', 'full_house': 'Ngan Liang', 'four_kind': 'Massaman', 'straight_flush': 'Khao Chae', 'five_kind': 'Royal Samrap', 'full_family': 'Purist Samrap', 'perfect_palate': 'The Garuda'},
  'seoul': {'high_card': 'Hotteok', 'pair': 'Gimbap', 'two_pair': 'Banchan Set', 'three_kind': 'Bibimbap', 'straight': 'Hanjeongsik', 'flush': 'Kimchi Jjigae', 'full_house': 'Jeongol', 'four_kind': 'Galbijjim', 'straight_flush': 'Surasang', 'five_kind': 'Royal Hanjeongsik', 'full_family': 'Purist Jeongol', 'perfect_palate': 'The Daewang'},
  // `flush` is NOT the concept doc's Testi Kebabı: that dish carries a geographical
  // indication tied to Avanos pottery in Cappadocia, 700km from Istanbul. Hünkâr Beğendi
  // ("the sultan's delight") comes out of the Ottoman palace kitchens and is the honest
  // Istanbul answer. Same reason `straight_flush` keeps the doc's Sultan's Table: it is
  // descriptive English, not mangled Turkish.
  'istanbul': {'high_card': 'Simit', 'pair': 'Meze', 'two_pair': 'Kahvaltı', 'three_kind': 'Pilav', 'straight': 'Ocakbaşı', 'flush': 'Hünkâr Beğendi', 'full_house': 'Ziyafet', 'four_kind': 'İskender Kebap', 'straight_flush': "Sultan's Table", 'five_kind': 'Grand Ziyafet', 'full_family': 'Purist Meze', 'perfect_palate': 'The Padishah'},
  'beirut': {'high_card': "Ka'ak", 'pair': "Man'oushe", 'two_pair': 'Mezze', 'three_kind': 'Kibbeh', 'straight': 'Sofra', 'flush': 'Tabbouleh', 'full_house': 'Walimah', 'four_kind': 'Mashawi', 'straight_flush': 'Zaffe Feast', 'five_kind': 'Grand Walimah', 'full_family': 'Purist Mezze', 'perfect_palate': 'The Emir'},
  // `straight` is the seven-vegetable couscous by its Moroccan name, not the French
  // brasserie framing "Couscous Royal".
  'marrakech': {'high_card': 'Msemen', 'pair': 'Briouat', 'two_pair': 'Kemia', 'three_kind': 'Tagine', 'straight': 'Couscous Sebaa Khodra', 'flush': 'Pastilla', 'full_house': 'Diffa', 'four_kind': 'Mechoui', 'straight_flush': 'Moussem Feast', 'five_kind': 'Grand Diffa', 'full_family': 'Purist Tagine', 'perfect_palate': 'The Sultan'},
  'addis_ababa': {'high_card': 'Dabo Kolo', 'pair': 'Sambusa', 'two_pair': 'Firfir', 'three_kind': 'Doro Wat', 'straight': 'Beyaynetu', 'flush': 'Kitfo', 'full_house': 'Mesob Feast', 'four_kind': 'Zilzil Tibs', 'straight_flush': 'Enkutatash Feast', 'five_kind': 'Grand Mesob', 'full_family': 'Purist Beyaynetu', 'perfect_palate': 'The Negus'},
  // `straight_flush` is NOT the concept doc's Fiesta Grande — that is Chiapa de Corzo, in
  // Chiapas. La Mayordomía is the Oaxacan patron-saint feast, which is exactly a
  // village-scale banquet. `perfect_palate` is La Donají, the Zapotec princess on Oaxaca
  // City's coat of arms, so the apex is a real emblem like every other city's rather than
  // the generic Spanish for "the masterpiece".
  'oaxaca': {'high_card': 'Chapulines', 'pair': 'Elote', 'two_pair': 'Botana Oaxaqueña', 'three_kind': 'Tlayuda', 'straight': 'Comida Corrida', 'flush': 'Mole Negro', 'full_house': 'Guelaguetza', 'four_kind': 'Barbacoa Oaxaqueña', 'straight_flush': 'La Mayordomía', 'five_kind': 'Gran Guelaguetza', 'full_family': 'Mole Puro', 'perfect_palate': 'La Donají'},
  // `four_kind` is Arroz con Mariscos, not Chupe de Camarones — the chupe is Arequipa's.
  // Pachamanca is highland rather than Limeño but is pan-Peruvian and is genuinely a
  // layered, sequenced earth-oven meal, which no coastal dish matches for `straight`.
  'lima': {'high_card': 'Anticucho', 'pair': 'Causa', 'two_pair': 'Piqueo', 'three_kind': 'Lomo Saltado', 'straight': 'Pachamanca', 'flush': 'Ceviche', 'full_house': 'Banquete Criollo', 'four_kind': 'Arroz con Mariscos', 'straight_flush': 'Menú Novoandino', 'five_kind': 'Gran Pachamanca', 'full_family': 'Ceviche Puro', 'perfect_palate': 'El Sapa Inca'},
  // `perfect_palate` is the Krewe of Rex's own title. "The Rex" would be redundant — Rex
  // *is* the King of Carnival.
  'new_orleans': {'high_card': 'Beignet', 'pair': 'Po-Boy', 'two_pair': 'Muffuletta', 'three_kind': 'Gumbo', 'straight': "Table d'Hôte", 'flush': 'Jambalaya', 'full_house': 'Crawfish Boil', 'four_kind': 'Oysters Rockefeller', 'straight_flush': 'Mardi Gras Feast', 'five_kind': 'Krewe Banquet', 'full_family': 'Purist Gumbo', 'perfect_palate': 'The King of Carnival'},
};

/// The local name for [pattern] in [cityId].
///
/// Throws rather than falling back. A missing entry is a content bug — a city added to
/// [kCityPool] without its dish table — and the failure mode of a silent fallback is that
/// the game quietly shows "straight_flush" to a player at the best moment of their run.
String dishName(String cityId, String pattern) {
  final name = kDishNames[cityId]?[pattern];
  if (name == null) {
    throw StateError('kDishNames is missing "$pattern" for city "$cityId"');
  }
  return name;
}

/// The utensil catalog, expressed purely in the effect DSL.
///
/// A few keys extend the spec's starter list — `num_cards`, `all_cards_same_family`,
/// `pattern_at_least`, `heat_per_card`, `copy_right` — to express Wok / Bamboo Steamer /
/// Emperor's Wok / Butcher's Block / Griddle / Grandmother's Ladle as data rather than code.
/// Keep them in the content validator's allow-list.
///
/// **The first 20 entries are the ported M0 set and are frozen.** They are pinned against
/// `web/game-core.mjs` by `test/vectors.json`, so editing an id, cost, condition or effect
/// there breaks the differential guarantee rather than retuning a number.
/// `test/utensils_test.dart` asserts them field by field. Everything after the expansion
/// banner is Dart-native content and is free to tune.
const List<Utensil> kUtensils = [
  // commons (cost 4)
  Utensil(id: 'iron_tawa', name: 'Iron Tawa', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'min_cards': 3}, effect: {'flavor_add': 30}, text: '+30 flavor if the dish has 3+ ingredients'),
  Utensil(id: 'mint_garnish', name: 'Mint Garnish', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'sour'}, effect: {'heat_add': 4}, text: '+4 heat if the dish contains a Sour ingredient'),
  Utensil(id: 'salt_cellar', name: 'Salt Cellar', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'salty'}, effect: {'heat_add': 3}, text: '+3 heat if the dish contains a Salty ingredient'),
  Utensil(id: 'honey_jar', name: 'Honey Jar', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'sweet'}, effect: {'flavor_add': 25}, text: '+25 flavor if the dish contains a Sweet ingredient'),
  Utensil(id: 'stock_pot', name: 'Stock Pot', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'umami'}, effect: {'heat_add': 2}, text: '+2 heat if the dish contains an Umami ingredient'),
  Utensil(id: 'street_cart', name: 'Street Cart', rarity: 'common', cost: 4, trigger: 'on_dish', condition: null, effect: {'coin_add': 1}, text: '+1 coin per dish played'),
  Utensil(id: 'big_spoon', name: 'Big Spoon', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'pair'}, effect: {'flavor_add': 20}, text: '+20 flavor if the recipe is a Pair'),
  Utensil(id: 'rice_cooker', name: 'Rice Cooker', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'three_kind'}, effect: {'flavor_add': 30}, text: '+30 flavor if the recipe is Three of a Kind'),
  // uncommons (cost 6)
  Utensil(id: 'tandoor', name: 'Tandoor', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'all_cards_family': 'spicy'}, effect: {'heat_mult': 1.5}, text: '×1.5 heat if every ingredient is Spicy'),
  Utensil(id: 'pressure_cooker', name: 'Pressure Cooker', rarity: 'uncommon', cost: 6, trigger: 'on_card', condition: null, effect: {'retrigger_highest': true}, text: 'Retrigger the highest-intensity ingredient'),
  Utensil(id: 'wok', name: 'Wok', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'all_cards_same_family': true}, effect: {'heat_mult': 1.5}, text: '×1.5 heat if all ingredients share a flavor family'),
  Utensil(id: 'chai_stall', name: 'Chai Stall', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'pattern_is': 'pair'}, effect: {'coin_add': 2}, text: '+2 coins when you cook a Pair'),
  Utensil(id: 'bamboo_steamer', name: 'Bamboo Steamer', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'num_cards': 3}, effect: {'heat_add': 5}, text: '+5 heat if exactly 3 ingredients'),
  Utensil(id: 'butchers_block', name: "Butcher's Block", rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'pattern_at_least': 'full_house'}, effect: {'flavor_add': 40}, text: '+40 flavor if the recipe is Full House or better'),
  Utensil(id: 'ice_box', name: 'Ice Box', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'is_first_dish': true}, effect: {'heat_mult': 2}, text: 'First dish of each service gets ×2 heat'),
  Utensil(id: 'griddle', name: 'Griddle', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: null, effect: {'heat_per_card': 1}, text: '+1 heat per ingredient played'),
  // rares (cost 9)
  Utensil(id: 'clay_handi', name: 'Clay Handi', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'is_last_dish': true}, effect: {'heat_mult': 3}, text: 'Last dish of each service gets ×3 heat'),
  Utensil(id: 'grandmother_ladle', name: "Grandmother's Ladle", rarity: 'rare', cost: 9, trigger: 'on_dish', condition: null, effect: {'copy_right': true}, text: 'Copies the effect of the utensil to its right'),
  Utensil(id: 'golden_sieve', name: 'Golden Sieve', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'pattern_is': 'flush'}, effect: {'flavor_add': 50, 'heat_add': 3}, text: 'Flushes get +50 flavor and +3 heat'),
  Utensil(id: 'emperors_wok', name: "Emperor's Wok", rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'num_cards': 5}, effect: {'heat_mult': 2}, text: '×2 heat if the dish uses 5 ingredients'),

  // -------------------------------------------------------------------------
  // M1 expansion — Dart-native content. Everything below this line was authored
  // here, not ported, so it has no counterpart in `web/game-core.mjs` and does
  // not appear in `test/vectors.json`.
  //
  // Three rules held while writing it, and they are what make the next 100 safe:
  //
  // 1. **No new DSL keys.** Every entry uses the nine conditions and eight effects
  //    `_condMet`/`scoreDish` already understand, so the engine did not move.
  //    `test/utensils_test.dart` asserts the allow-list over the whole catalog.
  // 2. **Additive at common, multiplicative from uncommon up.** `heat_mult`
  //    compounds across the five slots, so a cheap ×1.5 is a trap: four of them in
  //    one rack is ×5 for 16 coins. Commons therefore only ever add.
  // 3. **Family multipliers stay mutually exclusive.** `parmesan_wheel` (all Umami)
  //    cannot fire alongside `tandoor` (all Spicy), so adding one per family widens
  //    the choice without raising the stacking ceiling, which is still
  //    Wok × family × Ice Box × Clay Handi.
  //
  // Locked by default: none of these are in [kStartUtensils], so `rollOffers` will
  // not show them to a fresh profile. See the note there — nothing grants them yet.

  // commons (cost 4) — one `contains_family` and one `all_cards_family` per family,
  // then a rung for every recipe, then the dish-shape and timing hooks.
  Utensil(id: 'masala_dabba', name: 'Masala Dabba', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'spicy'}, effect: {'flavor_add': 25}, text: '+25 flavor if the dish contains a Spicy ingredient'),
  Utensil(id: 'molcajete', name: 'Molcajete', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'spicy'}, effect: {'heat_add': 3}, text: '+3 heat if the dish contains a Spicy ingredient'),
  Utensil(id: 'piloncillo_cone', name: 'Piloncillo Cone', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'sweet'}, effect: {'heat_add': 2}, text: '+2 heat if the dish contains a Sweet ingredient'),
  Utensil(id: 'achaar_jar', name: 'Achaar Jar', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'sour'}, effect: {'flavor_add': 25}, text: '+25 flavor if the dish contains a Sour ingredient'),
  Utensil(id: 'anchovy_tin', name: 'Anchovy Tin', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'salty'}, effect: {'flavor_add': 20}, text: '+20 flavor if the dish contains a Salty ingredient'),
  Utensil(id: 'katsuobushi_box', name: 'Katsuobushi Box', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'umami'}, effect: {'flavor_add': 25}, text: '+25 flavor if the dish contains an Umami ingredient'),
  Utensil(id: 'tadka_pan', name: 'Tadka Pan', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'all_cards_family': 'spicy'}, effect: {'flavor_add': 30}, text: '+30 flavor if every ingredient is Spicy'),
  Utensil(id: 'baklava_tray', name: 'Baklava Tray', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'all_cards_family': 'sweet'}, effect: {'flavor_add': 30}, text: '+30 flavor if every ingredient is Sweet'),
  Utensil(id: 'onggi_crock', name: 'Onggi Crock', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'all_cards_family': 'sour'}, effect: {'flavor_add': 30}, text: '+30 flavor if every ingredient is Sour'),
  Utensil(id: 'salt_block', name: 'Salt Block', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'all_cards_family': 'salty'}, effect: {'heat_add': 4}, text: '+4 heat if every ingredient is Salty'),
  Utensil(id: 'kombu_basket', name: 'Kombu Basket', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'all_cards_family': 'umami'}, effect: {'heat_add': 4}, text: '+4 heat if every ingredient is Umami'),
  Utensil(id: 'tapas_plate', name: 'Tapas Plate', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'high_card'}, effect: {'flavor_add': 25}, text: '+25 flavor if the recipe is a High Card'),
  Utensil(id: 'dim_sum_basket', name: 'Dim Sum Basket', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'pair'}, effect: {'heat_add': 3}, text: '+3 heat if the recipe is a Pair'),
  Utensil(id: 'meze_tray', name: 'Meze Tray', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'two_pair'}, effect: {'flavor_add': 30}, text: '+30 flavor if the recipe is Two Pair'),
  Utensil(id: 'mercado_stall', name: 'Mercado Stall', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'two_pair'}, effect: {'coin_add': 2}, text: '+2 coins when you cook Two Pair'),
  Utensil(id: 'donabe', name: 'Donabe', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'three_kind'}, effect: {'heat_add': 3}, text: '+3 heat if the recipe is Three of a Kind'),
  Utensil(id: 'thali_plate', name: 'Thali Plate', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'straight'}, effect: {'flavor_add': 35}, text: '+35 flavor if the recipe is a Straight'),
  Utensil(id: 'bento_box', name: 'Bento Box', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'straight'}, effect: {'heat_add': 3}, text: '+3 heat if the recipe is a Straight'),
  Utensil(id: 'chitarra', name: 'Chitarra', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_at_least': 'straight'}, effect: {'flavor_add': 25}, text: '+25 flavor if the recipe is a Straight or better'),
  Utensil(id: 'paella_pan', name: 'Paella Pan', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'flush'}, effect: {'flavor_add': 30}, text: '+30 flavor if the recipe is a Flush'),
  Utensil(id: 'cazuela', name: 'Cazuela', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'full_house'}, effect: {'flavor_add': 35}, text: '+35 flavor if the recipe is a Full House'),
  Utensil(id: 'karahi', name: 'Karahi', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'pattern_is': 'four_kind'}, effect: {'heat_add': 4}, text: '+4 heat if the recipe is Four of a Kind'),
  Utensil(id: 'pilon', name: 'Pilón', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'num_cards': 1}, effect: {'heat_add': 4}, text: '+4 heat if the dish uses exactly 1 ingredient'),
  Utensil(id: 'tortilla_press', name: 'Tortilla Press', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'num_cards': 2}, effect: {'flavor_add': 25}, text: '+25 flavor if the dish uses exactly 2 ingredients'),
  Utensil(id: 'banana_leaf', name: 'Banana Leaf', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'min_cards': 5}, effect: {'flavor_add': 35}, text: '+35 flavor if the dish has 5 ingredients'),
  Utensil(id: 'idli_steamer', name: 'Idli Steamer', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'sour', 'min_cards': 3}, effect: {'heat_add': 3}, text: '+3 heat if the dish has 3+ ingredients and contains a Sour one'),
  Utensil(id: 'garum_amphora', name: 'Garum Amphora', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'contains_family': 'salty', 'min_cards': 4}, effect: {'heat_add': 4}, text: '+4 heat if the dish has 4+ ingredients and contains a Salty one'),
  Utensil(id: 'wire_spider', name: 'Wire Spider', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'is_first_dish': true}, effect: {'flavor_add': 30}, text: 'First dish of each service gets +30 flavor'),
  Utensil(id: 'sac_lid', name: 'Sač Lid', rarity: 'common', cost: 4, trigger: 'on_dish', condition: {'is_last_dish': true}, effect: {'flavor_add': 35}, text: 'Last dish of each service gets +35 flavor'),

  // uncommons (cost 6) — where the multipliers start. Each is gated on a single
  // recipe or dish shape, so at most one fires per dish and they cannot chain.
  Utensil(id: 'chile_roaster', name: 'Chile Roaster', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'all_cards_family': 'spicy'}, effect: {'flavor_per_card': 10}, text: '+10 flavor per ingredient if every ingredient is Spicy'),
  Utensil(id: 'parmesan_wheel', name: 'Parmesan Wheel', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'all_cards_family': 'umami'}, effect: {'heat_mult': 1.5}, text: '×1.5 heat if every ingredient is Umami'),
  Utensil(id: 'cataplana', name: 'Cataplana', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'pattern_is': 'two_pair'}, effect: {'heat_mult': 1.5}, text: '×1.5 heat if the recipe is Two Pair'),
  Utensil(id: 'sushi_geta', name: 'Sushi Geta', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'pattern_is': 'straight'}, effect: {'heat_mult': 1.5}, text: '×1.5 heat if the recipe is a Straight'),
  Utensil(id: 'comal', name: 'Comal', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'pattern_is': 'flush'}, effect: {'heat_mult': 1.5}, text: '×1.5 heat if the recipe is a Flush'),
  Utensil(id: 'metate', name: 'Metate', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'num_cards': 2}, effect: {'heat_mult': 1.5}, text: '×1.5 heat if the dish uses exactly 2 ingredients'),
  Utensil(id: 'saj_griddle', name: 'Saj Griddle', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'pattern_at_least': 'straight'}, effect: {'heat_add': 5}, text: '+5 heat if the recipe is a Straight or better'),
  Utensil(id: 'braai_grid', name: 'Braai Grid', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'pattern_at_least': 'full_house'}, effect: {'heat_add': 5}, text: '+5 heat if the recipe is a Full House or better'),
  Utensil(id: 'mangal_grill', name: 'Mangal Grill', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'pattern_at_least': 'four_kind'}, effect: {'flavor_add': 60}, text: '+60 flavor if the recipe is Four of a Kind or better'),
  Utensil(id: 'billig', name: 'Billig', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'is_first_dish': true}, effect: {'heat_add': 5}, text: 'First dish of each service gets +5 heat'),
  Utensil(id: 'tagine', name: 'Tagine', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'is_last_dish': true}, effect: {'flavor_add': 60}, text: 'Last dish of each service gets +60 flavor'),
  Utensil(id: 'hawker_stall', name: 'Hawker Stall', rarity: 'uncommon', cost: 6, trigger: 'on_dish', condition: {'min_cards': 3}, effect: {'coin_add': 2}, text: '+2 coins if the dish has 3+ ingredients'),

  // rares (cost 9) — four different answers to "what is my run about?". None is a
  // bigger version of a common: each one is only worth a slot if the rest of the
  // rack is built around it.
  Utensil(id: 'yanagiba', name: 'Yanagiba', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'num_cards': 1}, effect: {'heat_mult': 4}, text: '×4 heat if the dish uses exactly 1 ingredient'),
  Utensil(id: 'kazan', name: 'Kazan', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'min_cards': 4}, effect: {'heat_per_card': 2}, text: '+2 heat per ingredient if the dish has 4+ ingredients'),
  Utensil(id: 'maple_evaporator', name: 'Maple Evaporator', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'contains_family': 'sweet', 'pattern_at_least': 'three_kind'}, effect: {'heat_mult': 2}, text: '×2 heat on Three of a Kind or better containing a Sweet ingredient'),
  Utensil(id: 'asado_cross', name: 'Asado Cross', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'pattern_at_least': 'straight_flush'}, effect: {'flavor_add': 150, 'heat_add': 12}, text: 'Straight Flush or better gets +150 flavor and +12 heat'),
  // --- flavour multipliers -------------------------------------------------------------
  // Heat was the only multiplicative axis in the game, which is why additive-flavour commons
  // go dead once Kitchen level inflates the base. These give flavour builds a way to scale
  // too, so "stack flavour" becomes a real strategy rather than an early-run stopgap.
  // Rare-only and gated: a flavour multiplier compounds with the heat ones.
  Utensil(id: 'copper_degchi', name: 'Copper Degchi', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'min_cards': 4}, effect: {'flavor_mult': 1.5}, text: '×1.5 flavor if the dish has 4+ ingredients'),
  Utensil(id: 'clay_tandir', name: 'Clay Tandır', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'all_cards_same_family': true}, effect: {'flavor_mult': 2}, text: '×2 flavor if every ingredient shares a family'),
  Utensil(id: 'stone_mortar', name: 'Stone Mortar', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'num_cards': 1}, effect: {'flavor_mult': 3}, text: '×3 flavor on a single-ingredient dish'),
  Utensil(id: 'harvest_basket', name: 'Harvest Basket', rarity: 'rare', cost: 9, trigger: 'on_dish', condition: {'pattern_at_least': 'full_house'}, effect: {'flavor_mult': 1.75}, text: '×1.75 flavor if the recipe is Full House or better'),
];

final Map<String, Utensil> kUtensilById = {for (final u in kUtensils) u.id: u};

const List<(String, num)> kRarityWeights = [('common', 60), ('uncommon', 30), ('rare', 10)];

/// The 20 spice blends (consumables). A run holds at most 3.
///
/// Every entry is pure data: `applyBlend` interprets [Blend.effect] rather than switching on
/// the id, so a blend is content the same way a utensil is. The key set and its exact
/// semantics live in `blends.dart`; `test/blends_test.dart` owns the allow-list.
///
/// **The first six are the ported M0 set and are frozen.** `test/vectors.json` replays 29
/// cases recorded from the web build's `useBlend` against them — the display prefixes, the
/// `_copy` id scheme and the clamp at 10 included — so editing one is a differential break
/// rather than a retune. They are also the head of the list because `rollOffers` picks by
/// index off the seeded RNG; append, never insert.
///
/// Blends stay inside one boundary, and it is what keeps twenty of them comprehensible:
/// **a blend edits cards in the hand and the deck, and nothing else.** No scoring, no coins,
/// no utensil interaction — those are the utensil DSL's job. The verbs are what vary.
const List<Blend> kBlends = [
  // --- the ported six ---------------------------------------------------------------------
  Blend(id: 'chili_oil', name: 'Chili Oil', cost: 3, select: 2, desc: 'Turn up to 2 selected ingredients Spicy 🌶️', effect: {'set_family': 'spicy', 'prefix': 'Chili '}),
  Blend(id: 'sea_salt', name: 'Sea Salt', cost: 3, select: 2, desc: 'Turn up to 2 selected ingredients Salty 🧂', effect: {'set_family': 'salty', 'prefix': 'Salted '}),
  Blend(id: 'fermentation', name: 'Fermentation', cost: 3, select: 1, desc: '+3 intensity to 1 selected ingredient', effect: {'rank_add': 3}),
  Blend(id: 'sun_dry', name: 'Sun-Dry', cost: 3, select: 1, desc: 'Duplicate 1 selected ingredient into your hand', effect: {'duplicate': true}),
  Blend(id: 'sharpen', name: 'Whetstone', cost: 4, select: 1, desc: 'Set 1 selected ingredient to intensity 10', effect: {'rank_set': 10}),
  Blend(id: 'mise', name: 'Mise en Place', cost: 3, select: 0, desc: 'Draw 2 extra ingredients this turn', effect: {'draw': 2}),

  // -------------------------------------------------------------------------
  // M1 expansion — Dart-native content, no counterpart in `web/game-core.mjs`
  // and no entry in `test/vectors.json`. Covered by Dart-native tests instead.
  //
  // Written to add verbs, not numbers. A blend that is another blend with a
  // bigger constant is a worse blend than none: it doubles the shop's noise
  // without adding a decision. So every entry below either introduces a DSL key
  // (a verb the game could not previously express) or applies an existing one in
  // a direction the ported six never go — down instead of up, onto the whole
  // hand instead of a card, out of the deck instead of into it.
  //
  // Costs sit at 3-5 alongside the ported six. The scale is roughly "how much
  // does this move the hand": a family rewrite is 3, a two-card verb is 4, and
  // the three that create material — a second body, a prized card — are 5.

  // --- the rest of the family rewrites, one per family ------------------------------------
  // Chili Oil and Sea Salt covered Spicy and Salty; a Flush build in the other
  // three families had no bridge card at all. Same verb, same shape, same cost.
  Blend(id: 'brine', name: 'Pickling Brine', cost: 3, select: 2, desc: 'Turn up to 2 selected ingredients Sour 🥒', effect: {'set_family': 'sour', 'prefix': 'Pickled '}),
  Blend(id: 'jaggery', name: 'Jaggery Glaze', cost: 3, select: 2, desc: 'Turn up to 2 selected ingredients Sweet 🍯', effect: {'set_family': 'sweet', 'prefix': 'Candied '}),
  Blend(id: 'koji', name: 'Koji', cost: 3, select: 2, desc: 'Turn up to 2 selected ingredients Umami 🍄', effect: {'set_family': 'umami', 'prefix': 'Koji '}),

  // --- intensity, in the directions Fermentation and Whetstone do not go -------------------
  // Every rank verb the ported six have pushes intensity UP, which quietly means a
  // Straight can only ever be completed from below. Blanching is the missing half:
  // a stray 10 becomes the 8 the run needs. Invert Sugar is the same idea as a
  // reflection rather than a step, and is the only way a hand full of 1s and 2s
  // turns into one worth cooking.
  Blend(id: 'blanch', name: 'Blanching', cost: 3, select: 1, desc: '-2 intensity to 1 selected ingredient', effect: {'rank_add': -2}),
  Blend(id: 'invert', name: 'Invert Sugar', cost: 4, select: 1, desc: "Flip 1 selected ingredient's intensity — a 2 becomes a 9", effect: {'rank_invert': true}),
  Blend(id: 'cold_smoke', name: 'Cold Smoke', cost: 4, select: 0, desc: '+1 intensity to every ingredient in your hand', effect: {'rank_add': 1, 'scope': 'hand'}),

  // --- the two-card verbs: make this one like that one -------------------------------------
  // The first selected card is the source and is never touched. These are the
  // blends that turn a dead card into the card you are missing, which is a
  // different fantasy from "improve what you hold" and the reason they cost 4-5.
  Blend(id: 'julienne', name: 'Julienne', cost: 4, select: 2, desc: "Match the 2nd selected ingredient's intensity to the 1st", effect: {'copy_rank': true}),
  Blend(id: 'infusion', name: 'Infusion', cost: 4, select: 2, desc: "Give the 2nd selected ingredient the 1st's flavor family", effect: {'copy_family': true, 'prefix': 'Infused '}),
  Blend(id: 'levain', name: 'Lievito Madre', cost: 5, select: 2, desc: 'Make the 2nd selected ingredient a twin of the 1st', effect: {'copy_family': true, 'copy_rank': true, 'prefix': 'Cultured '}),
  Blend(id: 'reduction', name: 'Reduction', cost: 4, select: 2, desc: 'Boil 2 selected ingredients down into 1 — combined intensity, max 10', effect: {'merge': true}),

  // --- material: more cards, or better ones ------------------------------------------------
  // Sun-Dry's verb at two targets, and the only blend that makes a card prized.
  // Both cost 5: creating a body is how Four and Five of a Kind actually happen,
  // and it is the single most reliable thing a blend can do.
  Blend(id: 'conserva', name: 'Conserva', cost: 5, select: 2, desc: 'Duplicate up to 2 selected ingredients into your hand', effect: {'duplicate': true}),
  Blend(id: 'varak', name: 'Varak', cost: 5, select: 1, desc: 'Gild 1 selected ingredient — it becomes prized (+25 flavor)', effect: {'set_prized': true}),

  // --- the deck, which only Mise en Place could reach --------------------------------------
  // Mise draws blind off the top. Winnowing trades what you hold for what you do
  // not, and Foraging is the only targeted dig in the game: name a family, get
  // the next one. Both stay deterministic — deck order decides, never a fresh
  // roll — so a seed still replays exactly.
  Blend(id: 'winnow', name: 'Winnowing', cost: 3, select: 2, desc: 'Discard up to 2 selected ingredients and draw that many', effect: {'discard_draw': true}),
  Blend(id: 'forage', name: 'Foraging', cost: 4, select: 1, desc: "Draw the next ingredient in your pantry sharing the selected one's family", effect: {'draw_matching': true}),
];

final Map<String, Blend> kBlendById = {for (final b in kBlends) b.id: b};

/// Festival Cards — each purchase is a permanent Kitchen level for the run.
const List<Festival> kFestivals = [
  Festival(id: 'fest_pair', pattern: 'pair', name: 'Sankranti', cost: 3),
  Festival(id: 'fest_three', pattern: 'three_kind', name: 'Onam', cost: 3),
  Festival(id: 'fest_straight', pattern: 'straight', name: 'Baisakhi', cost: 3),
  Festival(id: 'fest_flush', pattern: 'flush', name: 'Holi', cost: 3),
  Festival(id: 'fest_full', pattern: 'full_house', name: 'Diwali', cost: 3),
  Festival(id: 'fest_four', pattern: 'four_kind', name: 'Pongal', cost: 4),
  Festival(id: 'fest_sflush', pattern: 'straight_flush', name: 'Kumbh Mela', cost: 4),
];

final Map<String, Festival> kFestivalById = {for (final f in kFestivals) f.id: f};

/// City palates (build spec §7), one per city in [kCityPool].
///
/// Only three *shapes* exist, and they are the three [Palate] understands — per-card
/// flavour percentage, per-card heat, and a whole-dish bonus for one recipe. Every city
/// below is one of those three with different numbers. A fourth shape would mean an engine
/// change in `cardContribution` / `scoreDish`, so a new city is content, not code.
///
/// The Kochi, Tokyo and Naples entries are frozen: `test/vectors.json` scores dishes
/// against them, so a retune there is a differential-test break rather than a balance edit.
const Map<String, Palate> kPalates = {
  // --- shape A: a family's intensity pays a flavour percentage on top -------------------
  'kochi': Palate(
    city: 'kochi',
    label: 'Sour ingredients give +50% intensity as flavor',
    perCardFlavorPctFamily: 'sour',
    perCardFlavorPct: 50,
  ),
  'seoul': Palate(
    city: 'seoul',
    label: 'Salty ingredients give +45% intensity as flavor',
    perCardFlavorPctFamily: 'salty',
    perCardFlavorPct: 45,
  ),
  'oaxaca': Palate(
    city: 'oaxaca',
    label: 'Spicy ingredients give +45% intensity as flavor',
    perCardFlavorPctFamily: 'spicy',
    perCardFlavorPct: 45,
  ),
  'lima': Palate(
    city: 'lima',
    label: 'Sour ingredients give +40% intensity as flavor',
    perCardFlavorPctFamily: 'sour',
    perCardFlavorPct: 40,
  ),
  // --- shape B: a family adds flat heat per card ----------------------------------------
  'tokyo': Palate(
    city: 'tokyo',
    label: 'Umami ingredients give +2 heat each',
    perCardHeatFamily: 'umami',
    perCardHeatAdd: 2,
  ),
  'bangkok': Palate(
    city: 'bangkok',
    label: 'Spicy ingredients give +2 heat each',
    perCardHeatFamily: 'spicy',
    perCardHeatAdd: 2,
  ),
  'marrakech': Palate(
    city: 'marrakech',
    label: 'Sweet ingredients give +2 heat each',
    perCardHeatFamily: 'sweet',
    perCardHeatAdd: 2,
  ),
  'beirut': Palate(
    city: 'beirut',
    label: 'Sour ingredients give +2 heat each',
    perCardHeatFamily: 'sour',
    perCardHeatAdd: 2,
  ),
  // --- shape C: one recipe gets a whole-dish flavour bonus -------------------------------
  'naples': Palate(
    city: 'naples',
    label: 'Flush dishes get +40 flavor',
    dishFlavorPattern: 'flush',
    dishFlavorAdd: 40,
  ),
  'istanbul': Palate(
    city: 'istanbul',
    label: 'Straight dishes get +40 flavor',
    dishFlavorPattern: 'straight',
    dishFlavorAdd: 40,
  ),
  'addis_ababa': Palate(
    city: 'addis_ababa',
    label: 'Three of a Kind dishes get +35 flavor',
    dishFlavorPattern: 'three_kind',
    dishFlavorAdd: 35,
  ),
  'new_orleans': Palate(
    city: 'new_orleans',
    label: 'Full House dishes get +50 flavor',
    dishFlavorPattern: 'full_house',
    dishFlavorAdd: 50,
  ),
};

/// The major critics — the Food Critic service that closes every city.
///
/// Every entry uses only the four [Critic] demand fields the engine already reads
/// (`maxCards`, `minCards`, `debuff`, `requireFamily`), so the pool grows without
/// `dishError` or `cardContribution` moving. The concept doc's Rival Chef ("beat the target
/// within 3 dishes") is deliberately absent — it would need a fifth field and an engine
/// change; see the report in the commit message.
///
/// `minimalist` and `traditionalist` are the ported pair and are frozen — `test/vectors.json`
/// scores debuffed dishes against them.
const Map<String, Critic> kCritics = {
  'minimalist': Critic(
    id: 'minimalist',
    name: 'The Minimalist',
    rule: 'Dishes may use at most 3 ingredients',
    maxCards: 3,
  ),
  'traditionalist': Critic(
    id: 'traditionalist',
    name: 'The Traditionalist',
    rule: 'Sweet ingredients contribute 0 intensity (and no palate bonus)',
    debuff: 'sweet',
  ),
  'gourmand': Critic(
    id: 'gourmand',
    name: 'The Gourmand',
    rule: 'Dishes must use at least 4 ingredients',
    minCards: 4,
  ),
  'austere': Critic(
    id: 'austere',
    name: 'The Austere Critic',
    rule: 'Umami ingredients contribute 0 intensity (and no palate bonus)',
    debuff: 'umami',
  ),
  'ascetic': Critic(
    id: 'ascetic',
    name: 'The Ascetic',
    rule: 'Spicy ingredients contribute 0 intensity (and no palate bonus)',
    debuff: 'spicy',
  ),
  'firebrand': Critic(
    id: 'firebrand',
    name: 'The Firebrand',
    rule: 'Every dish must contain a Spicy ingredient',
    requireFamily: 'spicy',
  ),
  'brine_baron': Critic(
    id: 'brine_baron',
    name: 'The Brine Baron',
    rule: 'Every dish must contain a Salty ingredient',
    requireFamily: 'salty',
  ),
};

/// May [c] be the demand on the service that ends a run?
///
/// This generalizes a hard-won balance fix. Naples' finale critic was pinned to the
/// Traditionalist because rolling the Minimalist onto a 50k target was unwinnable at any
/// Kitchen level — and the reason is structural rather than about those two critics:
///
///  * `maxCards` below 5 caps the recipe ladder at Three of a Kind. Kitchen level grows the
///    base linearly, so a capped ladder cannot catch a target that grows geometrically.
///  * `requireFamily` forces a card of one family into every dish, which makes a Flush or a
///    Straight Flush impossible unless the build happens to be in that family — the same
///    ceiling by a different route.
///
/// Debuffs and minimums only make the finale expensive, never impossible, so they are safe.
/// [drawRoute] draws the last city of a route from the cities whose critic passes this.
bool criticCanCloseARun(Critic c) => c.maxCards == null && c.requireFamily == null;

/// A city on the route.
///
/// Long Route (endless) cities are built at runtime by `startEndlessCity` rather than
/// declared here: they carry a rolled — sometimes merged — [criticObj] instead of naming
/// one from [kCritics], which is why [critic] is optional.
class City {
  const City({
    required this.id,
    required this.name,
    required this.targets,
    this.critic = '',
    this.criticObj,
  });

  final String id;
  final String name;

  /// Lunch / Dinner / Critic score targets.
  final List<int> targets;

  /// Key into [kCritics] for the finale service. `'random'` resolves against the run's
  /// pre-rolled `naplesCritic`. Empty on Long Route cities.
  final String critic;

  /// Long Route only: the critic instance for this city's finale service.
  final Critic? criticObj;
}

/// **The frozen 3-city route of the JS build.** This is no longer what a run walks — see
/// [kCityPool] and `drawRoute` — but it is still the exact route `web/game-core.mjs` knows,
/// and `test/runs_test.dart` pins its traces to it by passing `route: kCities` to `newRun`.
/// Treat it as a fixture, not as content: retuning a number here is a differential-test
/// break, not a balance edit.
///
/// Naples' finale critic is fixed to the Traditionalist on purpose: rolling the Minimalist
/// on a 50k target is unwinnable at any Kitchen level. [criticCanCloseARun] is that rule
/// generalized to the 12-city pool.
const List<City> kCities = [
  City(id: 'kochi', name: 'Kochi 🇮🇳', targets: [300, 800, 1200], critic: 'minimalist'),
  City(id: 'tokyo', name: 'Tokyo 🇯🇵', targets: [3500, 6000, 11000], critic: 'traditionalist'),
  City(id: 'naples', name: 'Naples 🇮🇹', targets: [18000, 30000, 50000], critic: 'traditionalist'),
];

const List<String> kServiceNames = ['Lunch Rush', 'Dinner Rush', 'The Food Critic'];

// ---------------------------------------------------------------------------
// The route: 8 cities drawn from a pool of 12 (concept doc §3.1)
// ---------------------------------------------------------------------------

/// A city as it sits in the pool, before a route places it.
///
/// It deliberately carries no targets. A city's *difficulty* is a property of where it falls
/// on the route — Naples is brutal because it is last, not because it is Naples — so targets
/// come from [routeTargets] and the identity here is only culture: name, palate, critic.
class CityDef {
  const CityDef({required this.id, required this.name, required this.critic});

  /// Key into [kPalates] and [kDishNames]; both must have an entry for it.
  final String id;
  final String name;

  /// Key into [kCritics] for this city's Food Critic service.
  final String critic;
}

/// The 12 world food capitals a run draws from (concept doc §4: 12 in pool, 8 per run).
///
/// **Order is a seed contract.** [drawRoute] shuffles this list, so inserting or reordering
/// an entry silently re-rolls the route of every existing seed. Append; do not insert.
///
/// The critic is fixed per city rather than rolled, which is what makes a city a legible
/// unit the player can plan against: the concept doc's §3.5 promise is that palates are
/// visible one city ahead, and a known palate paired with a known demand is what turns that
/// into a real decision. It also costs zero RNG draws.
///
/// The Minimalist appears only on Kochi. Its 3-card cap holds you to Three of a Kind, which
/// is why Kochi's boss is 1200 rather than the spec'd 2000 — and why that critic must never
/// land on a later city, whose targets assume the whole recipe ladder is available.
const List<CityDef> kCityPool = [
  CityDef(id: 'kochi', name: 'Kochi 🇮🇳', critic: 'minimalist'),
  CityDef(id: 'bangkok', name: 'Bangkok 🇹🇭', critic: 'firebrand'),
  CityDef(id: 'seoul', name: 'Seoul 🇰🇷', critic: 'gourmand'),
  CityDef(id: 'tokyo', name: 'Tokyo 🇯🇵', critic: 'traditionalist'),
  CityDef(id: 'istanbul', name: 'Istanbul 🇹🇷', critic: 'brine_baron'),
  CityDef(id: 'beirut', name: 'Beirut 🇱🇧', critic: 'austere'),
  CityDef(id: 'marrakech', name: 'Marrakech 🇲🇦', critic: 'ascetic'),
  CityDef(id: 'addis_ababa', name: 'Addis Ababa 🇪🇹', critic: 'firebrand'),
  CityDef(id: 'naples', name: 'Naples 🇮🇹', critic: 'traditionalist'),
  CityDef(id: 'oaxaca', name: 'Oaxaca 🇲🇽', critic: 'gourmand'),
  CityDef(id: 'lima', name: 'Lima 🇵🇪', critic: 'austere'),
  CityDef(id: 'new_orleans', name: 'New Orleans 🇺🇸', critic: 'ascetic'),
];

final Map<String, CityDef> kCityDefById = {for (final c in kCityPool) c.id: c};

/// How many cities one run visits.
const int kRouteLength = 8;

/// The city every run opens on: the home culture, and the tutorial.
const String kStartCityId = 'kochi';

// --- the target curve ------------------------------------------------------
//
// TUNING KNOBS. Everything below is data: change a number, rerun
// `cd tools/sim && dart run bin/sim.dart -n 300`. No logic moves.
//
// The curve is quadratic in *service* number, and that is derived rather than fitted.
// Festival recipe-leveling is the run's scaling engine, and it is linear twice over:
// [kLevelBonus] grows a recipe's base flavour AND its base heat by a fixed amount per
// Kitchen level, and Kitchen level grows about linearly in bazaars, so a dish worth
// (F0 + aL) x (H0 + bL) is quadratic in level and therefore quadratic in how far along the
// route you are. Targets that track the scaling engine are targets that stay the same
// difficulty at every slot.
//
// This is where an 8-city route parts company with the tuned 3-city one, and it is worth
// being explicit about why, because the 3-city numbers look like they should just extend.
// They are geometric — roughly x1.9 per service, 300 to 50000 across nine — and that rate
// is an artefact of having only nine services to cover the distance in. Player power is
// only that steep during the opening ramp, when the rack goes from empty to three utensils
// and Kitchen level 1 to 3. After that it is quadratic. Extending the geometric rate to
// twenty-four services asks for ~1.3M on the last boss against a measured ceiling near
// 250k: simulated at 300 runs it wins 0% at every stake, including Paprika.
//
// So the curve keeps Kochi verbatim, lands city 2 close to the tuned Tokyo (4800/6800/9300
// against 3500/6000/11000), and from there climbs at the rate the engine actually scales
// at. Naples' old 18000/30000/50000 is deliberately NOT reproduced at slot 2: those were
// the numbers for the end of a three-city sprint, and here slot 2 is a third of the way in.
//
// Two properties fall out of the shape for free, rather than needing their own knobs:
//   * The whole 24-service sequence is monotone increasing, because it is a power of an
//     increasing argument. There is no city boundary to police.
//   * The Lunch/Dinner/Critic spread inside a city narrows as the route goes on — x4.0 at
//     Kochi, x1.2 by the last city. That is correct: early on a bazaar can double your
//     build, so the boss can afford to be four times the Lunch; by slot 7 a bazaar moves
//     you a few percent, so a boss four times the Lunch would be unclearable.

/// Kochi's hand-tuned opening triple, kept verbatim as slot 0.
///
/// The 1200 boss is load-bearing: the Minimalist's 3-card cap makes an all-flavour build
/// mathematically capped around 1572, so the spec's 2000 was unwinnable. The general curve
/// would put slot 0 at 760/1100/1500 — the tutorial city is the one place where the ramp
/// from an empty rack is too violent for a smooth curve to describe, which is exactly why
/// it was hand-tuned in the first place.
const List<int> kTutorialTargets = [300, 800, 1200];

/// `target(s) = kRouteScale * (s + kRouteOffset) ^ kRouteExponent`, for service number `s`.
///
/// [kRouteExponent] is 2 because the scaling engine is quadratic (see above) — treat it as
/// structure, not as a knob, and reach for [kRouteScale] first. [kRouteScale] sets the
/// absolute difficulty of the whole route and is the one number to move after a sim run.
/// [kRouteOffset] shifts where on the curve the route starts, which trades the harshness of
/// the early cities against the late ones.
const double kRouteScale = 210;
const double kRouteOffset = 2;
const double kRouteExponent = 2;

/// JS `Math.round` — `floor(x + 0.5)`, kept identical so a retune cannot drift by one.
int _jsRound(double n) => (n + 0.5).floor();

/// Rounds a raw curve value to two significant figures, which is what makes the targets
/// read like designed numbers (23000, not 22990) instead of like the output of a formula.
int niceTarget(double v) {
  if (v <= 0) return 0;
  var mag = 1;
  while (v / mag >= 100) {
    mag *= 10;
  }
  return _jsRound(v / mag) * mag;
}

/// The target for service [s], counted from 0 across the whole route (city * 3 + service).
int serviceTarget(int s) =>
    niceTarget(kRouteScale * math.pow(s + kRouteOffset, kRouteExponent));

/// Lunch / Dinner / Food Critic targets for route slot [slot] (0-based).
///
/// Position, not identity: the same city is a different fight at slot 1 and slot 7.
List<int> routeTargets(int slot) {
  if (slot == 0) return kTutorialTargets;
  final s = slot * 3;
  return [serviceTarget(s), serviceTarget(s + 1), serviceTarget(s + 2)];
}

/// Places [def] at route slot [slot], giving it that slot's targets.
City cityAt(CityDef def, int slot) =>
    City(id: def.id, name: def.name, targets: routeTargets(slot), critic: def.critic);

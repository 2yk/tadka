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
const Map<String, Map<String, String>> kDishNames = {
  'kochi': {'high_card': 'Street Snack', 'pair': 'Chaat', 'two_pair': 'Meals Combo', 'three_kind': 'Curry', 'straight': 'Sadya', 'flush': 'Signature Thali', 'full_house': 'Feast', 'four_kind': 'Royal Curry', 'straight_flush': 'Royal Biryani', 'five_kind': 'Royal Sadya', 'full_family': 'Purist Thali', 'perfect_palate': 'The Maharaja'},
  'tokyo': {'high_card': 'Bento Bite', 'pair': 'Onigiri', 'two_pair': 'Teishoku', 'three_kind': 'Ramen', 'straight': 'Sushi Set', 'flush': 'Omakase', 'full_house': 'Donburi Feast', 'four_kind': 'Wagyu Course', 'straight_flush': 'Kaiseki', 'five_kind': "Emperor's Kaiseki", 'full_family': 'Pure Omakase', 'perfect_palate': 'The Shogun'},
  'naples': {'high_card': 'Cicchetti', 'pair': 'Bruschetta', 'two_pair': 'Antipasti', 'three_kind': 'Risotto', 'straight': 'Primi e Secondi', 'flush': 'Margherita', 'full_house': 'Festa', 'four_kind': 'Quattro Formaggi', 'straight_flush': "Nonna's Feast", 'five_kind': 'Grand Festa', 'full_family': 'Monovarietale', 'perfect_palate': 'Il Capolavoro'},
};

/// The 20 M0 utensils (build spec §6), expressed purely in the effect DSL.
///
/// A few keys extend the spec's starter list — `num_cards`, `all_cards_same_family`,
/// `pattern_at_least`, `heat_per_card`, `copy_right` — to express Wok / Bamboo Steamer /
/// Emperor's Wok / Butcher's Block / Griddle / Grandmother's Ladle as data rather than code.
/// Keep them in the content validator's allow-list.
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
];

final Map<String, Utensil> kUtensilById = {for (final u in kUtensils) u.id: u};

const List<(String, num)> kRarityWeights = [('common', 60), ('uncommon', 30), ('rare', 10)];

/// The 6 spice blends (consumables). A run holds at most 3.
const List<Blend> kBlends = [
  Blend(id: 'chili_oil', name: 'Chili Oil', cost: 3, select: 2, desc: 'Turn up to 2 selected ingredients Spicy 🌶️'),
  Blend(id: 'sea_salt', name: 'Sea Salt', cost: 3, select: 2, desc: 'Turn up to 2 selected ingredients Salty 🧂'),
  Blend(id: 'fermentation', name: 'Fermentation', cost: 3, select: 1, desc: '+3 intensity to 1 selected ingredient'),
  Blend(id: 'sun_dry', name: 'Sun-Dry', cost: 3, select: 1, desc: 'Duplicate 1 selected ingredient into your hand'),
  Blend(id: 'sharpen', name: 'Whetstone', cost: 4, select: 1, desc: 'Set 1 selected ingredient to intensity 10'),
  Blend(id: 'mise', name: 'Mise en Place', cost: 3, select: 0, desc: 'Draw 2 extra ingredients this turn'),
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

/// City palates (build spec §7).
const Map<String, Palate> kPalates = {
  'kochi': Palate(
    city: 'kochi',
    label: 'Sour ingredients give +50% intensity as flavor',
    perCardFlavorPctFamily: 'sour',
    perCardFlavorPct: 50,
  ),
  'tokyo': Palate(
    city: 'tokyo',
    label: 'Umami ingredients give +2 heat each',
    perCardHeatFamily: 'umami',
    perCardHeatAdd: 2,
  ),
  'naples': Palate(
    city: 'naples',
    label: 'Flush dishes get +40 flavor',
    dishFlavorPattern: 'flush',
    dishFlavorAdd: 40,
  ),
};

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
};

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

/// The 3-city M0 mini-run. Naples' finale critic is fixed to the Traditionalist on purpose:
/// rolling the Minimalist on a 50k target is unwinnable at any Kitchen level.
const List<City> kCities = [
  City(id: 'kochi', name: 'Kochi 🇮🇳', targets: [300, 800, 1200], critic: 'minimalist'),
  City(id: 'tokyo', name: 'Tokyo 🇯🇵', targets: [3500, 6000, 11000], critic: 'traditionalist'),
  City(id: 'naples', name: 'Naples 🇮🇹', targets: [18000, 30000, 50000], critic: 'traditionalist'),
];

const List<String> kServiceNames = ['Lunch Rush', 'Dinner Rush', 'The Food Critic'];

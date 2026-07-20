/// Core value types. Pure Dart — no Flutter, no serialization framework.
///
/// Utensil `condition` and `effect` stay as maps rather than sealed classes on purpose:
/// they are the content DSL, authored as JSON so 100+ utensils can ship without engine
/// changes. `packages/content` validates the keys; unknown keys must be rejected there.
library;

/// The five flavour families (card "suits").
const List<String> kFamilies = ['spicy', 'sweet', 'sour', 'salty', 'umami'];

/// Bonus flavour a prized ingredient contributes on top of its intensity.
const int kPrizedBonus = 25;

/// An ingredient card. Immutable; blends produce new instances rather than mutating.
class Card {
  const Card({
    required this.id,
    required this.family,
    required this.rank,
    required this.display,
    this.prized = false,
  });

  final String id;
  final String family;

  /// Intensity, 1..10.
  final int rank;
  final String display;
  final bool prized;

  Card copyWith({String? id, String? family, int? rank, String? display, bool? prized}) => Card(
    id: id ?? this.id,
    family: family ?? this.family,
    rank: rank ?? this.rank,
    display: display ?? this.display,
    prized: prized ?? this.prized,
  );

  @override
  String toString() => '$display($family $rank${prized ? ' prized' : ''})';
}

/// A utensil / vendor — a permanent passive modifier occupying one of five slots.
class Utensil {
  const Utensil({
    required this.id,
    required this.name,
    required this.rarity,
    required this.cost,
    required this.trigger,
    required this.condition,
    required this.effect,
    required this.text,
  });

  final String id;
  final String name;

  /// `common` | `uncommon` | `rare`.
  final String rarity;
  final int cost;

  /// `on_dish` | `on_card`.
  final String trigger;

  /// DSL condition map, or null for "always fires".
  final Map<String, Object?>? condition;

  /// DSL effect map.
  final Map<String, Object?> effect;
  final String text;
}

/// A city's palate — the scoring bias that makes each city play differently.
///
/// The three shapes are deliberately different (per-card flavour %, per-card heat,
/// whole-dish bonus) so the system proves it can express more than one idea.
class Palate {
  const Palate({
    required this.city,
    required this.label,
    this.perCardFlavorPctFamily,
    this.perCardFlavorPct,
    this.perCardHeatFamily,
    this.perCardHeatAdd,
    this.dishFlavorPattern,
    this.dishFlavorAdd,
  });

  final String city;
  final String label;

  /// Kochi: Sour ingredients give +pct% of intensity as bonus flavour.
  final String? perCardFlavorPctFamily;
  final int? perCardFlavorPct;

  /// Tokyo: Umami ingredients give +add heat each.
  final String? perCardHeatFamily;
  final int? perCardHeatAdd;

  /// Naples: dishes of this pattern get +add flavour.
  final String? dishFlavorPattern;
  final int? dishFlavorAdd;
}

/// A food critic (boss demand). Fields are nullable because each critic uses a subset.
class Critic {
  const Critic({
    required this.id,
    required this.name,
    required this.rule,
    this.maxCards,
    this.minCards,
    this.debuff,
    this.requireFamily,
    this.minor = false,
    this.legend = false,
  });

  final String id;
  final String name;
  final String rule;

  /// The Minimalist: dishes may use at most this many ingredients.
  final int? maxCards;
  final int? minCards;

  /// The Traditionalist: this family contributes 0 intensity and no palate bonus.
  final String? debuff;
  final String? requireFamily;

  /// Drawn from the milder Dinner Rush pool that Habanero (stake 6) switches on.
  final bool minor;

  /// Produced by `mergeCritics` on the Long Route: two demands at once.
  final bool legend;
}

/// A spice blend — a one-shot consumable bought at the bazaar and played from the hand.
///
/// The blends themselves are applied by the UI layer (they mutate held cards); `game_core`
/// only owns the inventory, which is why this type carries no behaviour.
class Blend {
  const Blend({
    required this.id,
    required this.name,
    required this.cost,
    required this.select,
    required this.desc,
  });

  final String id;
  final String name;
  final int cost;

  /// How many held cards the blend targets. 0 = no selection (Mise en Place).
  final int select;
  final String desc;
}

/// A Festival Card — the planet-analog. Buying one raises the run's Kitchen level, which
/// levels every recipe's base flavour and heat. See [kLevelBonus]: this is the scaling engine.
class Festival {
  const Festival({
    required this.id,
    required this.pattern,
    required this.name,
    required this.cost,
  });

  final String id;

  /// The recipe this festival is themed on. M0 levels the whole Kitchen rather than the
  /// single pattern, so this is presentational — kept because v1.0 splits them apart.
  final String pattern;
  final String name;
  final int cost;
}

/// One line of the scoring breakdown, for the count-up UI and the Coach.
class ScoreStep {
  const ScoreStep(this.text, this.cls);

  final String text;

  /// `''` | `'plus'` | `'mult'` — drives colour and the shake trigger.
  final String cls;

  @override
  String toString() => text;
}

/// The result of scoring one dish.
///
/// [flavor] and [heat] are doubles because heat multipliers and percentage palates make
/// them fractional mid-calculation; only the final [score] is floored. Using ints here
/// would silently diverge from the JS engine on any `heat_mult: 1.5`.
class ScoreResult {
  const ScoreResult({
    required this.pattern,
    required this.scoring,
    required this.flavor,
    required this.heat,
    required this.coins,
    required this.score,
    required this.steps,
  });

  final String pattern;

  /// Only the cards forming the pattern. Extras played still trigger "any card" effects
  /// but contribute no intensity.
  final List<Card> scoring;
  final double flavor;
  final double heat;
  final int coins;
  final int score;
  final List<ScoreStep> steps;
}

/// Everything scoring needs to know beyond the cards themselves.
class ScoreContext {
  const ScoreContext({
    this.palate,
    this.utensils = const [],
    this.critic,
    this.kitchenLevel = 1,
    this.isFirstDish = false,
    this.isLastDish = false,
  });

  final Palate? palate;

  /// Slot order matters — utensils fire left to right, and additive before multiplicative.
  final List<Utensil> utensils;
  final Critic? critic;

  /// Festival recipe-leveling. Level 1 = no bonus. This is the run's scaling engine.
  final int kitchenLevel;
  final bool isFirstDish;
  final bool isLastDish;
}

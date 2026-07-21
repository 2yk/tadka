/// §PROGRESSION — stakes, the meta-save, and the achievement/unlock event bus.
///
/// A faithful port of the web build, which is the behavioural reference (CLAUDE.md).
/// `test/runs_test.dart` replays scripted runs generated from it and compares the profile
/// after every action, so a divergence here surfaces as a trace mismatch rather than as a
/// player quietly losing an unlock.
///
/// Two design notes worth knowing before you edit anything:
///
/// **Persistence is a seam, not a dependency.** `game_core` must never import Flutter, so
/// the meta-save goes through [ProfileStore]. The app injects a `shared_preferences`-backed
/// implementation at startup; `tools/sim` and the tests keep [MemoryProfileStore]. The JSON
/// written is byte-compatible with the web build's `tadka_profile_v1` key, so a player can
/// carry a save across.
///
/// **Unlocks are never lost on death.** [loadProfile] merges the stored save over
/// [defaultProfile], per field, so fields added in a later version survive an old save
/// instead of reading as null.
library;

import 'dart:convert';

import 'catalog.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// The internal-testing switch
// ---------------------------------------------------------------------------

/// **Show everything the game contains, from run one.** Internal-testing setting.
///
/// The build is content-complete but discovery-gated, and during an internal test that gating
/// works against the person paying for the content: 95 utensils exist and a fresh profile is
/// offered 74 of them, three recipes read as `? ? ?`, four of five decks and seven of eight
/// stakes are padlocked. None of that is measurable in a few days of play, so for an internal
/// build this defaults to **true** and every catalog is visible and reachable immediately.
///
/// **For a discovery-gated public build, set this to `false`.** That is the only edit needed:
/// nothing below has been deleted, and this flag is read in exactly two places —
/// [isUnlocked] and [maxStake]. The whole ladder is intact underneath it:
///
///  * [kStartUtensils] still names the starting pool, and [unlockedUtensilPool] still filters
///    on it once the flag is off;
///  * [kAchievements] still fires, still grants, and still queues its toast — [unlockThing]
///    writes to the save either way, so a tester still *sees* the unlock happen;
///  * [setStakeProgress] still records the stake ladder per deck;
///  * `recipes_discovered` is still recorded, so the Recipe Book's discovery state survives.
///
/// It is deliberately a mutable variable rather than a `const`: the differential run traces in
/// `test/runs_test.dart` replay a recorded shop pool and pin it to `false` in `setUpAll`, and
/// `test/content_visibility_test.dart` asserts both modes. Same seam as
/// [activeUtensilCatalog] — scope the fixture, don't freeze the game.
///
/// Two knock-on effects worth knowing when it is on:
///  * `rollOffers` draws utensils from the whole catalog, so a fresh profile meets Rares.
///  * `newRun`'s Royal-deck free Rare is picked from every unlocked Rare, so a Royal seed
///    opens differently than it would on a gated profile. Both are the point of the switch.
bool kShowAllContent = true;

/// One stake's difficulty knob. Kept as loose data — the same shape as `stakes.json` —
/// so a new modifier is a content edit plus one branch in [stakeConfig].
class StakeModifier {
  const StakeModifier({required this.type, this.value, this.fromCity, this.pct});

  final String type;
  final Object? value;
  final int? fromCity;
  final int? pct;

  /// Player-facing label for the stake picker.
  ///
  /// Wording is a port of §UI's `modLabel`, so both builds describe the same difficulty in
  /// the same words. An unknown type falls back to its raw [type] rather than throwing —
  /// a content pack that adds a modifier should degrade, not crash the start screen.
  String describe() {
    switch (type) {
      case 'service_reward_zero':
        return 'Lunch Rush pays 0 coins';
      case 'target_scale':
        return '+$pct% targets from city $fromCity';
      case 'swaps_delta':
        return '$value swap (${3 + (value! as int)} total)';
      case 'cooks_delta':
        return '$value cook';
      case 'shop_inflation_per_city':
        return 'shop prices +$value per city';
      case 'minor_critic_on_dinner':
        return 'Dinner Rush also carries a minor critic';
      case 'utensil_slots':
        return 'utensil slots → $value';
      default:
        return type;
    }
  }
}

/// A difficulty tier. Stakes are cumulative: stake 5 includes every modifier from 1-4.
class Stake {
  const Stake({required this.id, required this.name, required this.chiliIcon, required this.modifiers});

  final int id;
  final String name;
  final String chiliIcon;
  final List<StakeModifier> modifiers;
}

const List<Stake> kStakes = [
  Stake(id: 1, name: 'Paprika', chiliIcon: '🌶️', modifiers: []),
  Stake(id: 2, name: 'Jalapeño', chiliIcon: '🌶️', modifiers: [
    StakeModifier(type: 'service_reward_zero', value: 'lunch'),
  ]),
  Stake(id: 3, name: 'Serrano', chiliIcon: '🌶️🌶️', modifiers: [
    StakeModifier(type: 'target_scale', fromCity: 3, pct: 25),
  ]),
  Stake(id: 4, name: 'Cayenne', chiliIcon: '🌶️🌶️', modifiers: [
    StakeModifier(type: 'swaps_delta', value: -1),
  ]),
  Stake(id: 5, name: "Bird's Eye", chiliIcon: '🌶️🌶️🌶️', modifiers: [
    StakeModifier(type: 'shop_inflation_per_city', value: 1),
  ]),
  Stake(id: 6, name: 'Habanero', chiliIcon: '🌶️🌶️🌶️', modifiers: [
    StakeModifier(type: 'minor_critic_on_dinner', value: true),
  ]),
  Stake(id: 7, name: 'Ghost Pepper', chiliIcon: '🌶️🌶️🌶️🌶️', modifiers: [
    StakeModifier(type: 'cooks_delta', value: -1),
  ]),
  Stake(id: 8, name: 'Carolina Reaper', chiliIcon: '🔥', modifiers: [
    StakeModifier(type: 'utensil_slots', value: 4),
  ]),
];

final Map<int, Stake> kStakeById = {for (final s in kStakes) s.id: s};

/// Late-city target inflation: from [fromCity] onward, targets grow by [pct]%.
class TargetScale {
  const TargetScale({required this.fromCity, required this.pct});

  /// 1-based city number, so city index 2 (Naples) is `cityIndex + 1 == 3`.
  final int fromCity;
  final int pct;
}

/// The resolved, cumulative effect of a stake — computed once per run by [stakeConfig].
class StakeConfig {
  StakeConfig({
    this.cooksDelta = 0,
    this.swapsDelta = 0,
    this.utensilSlots = 5,
    this.lunchRewardZero = false,
    this.targetScale,
    this.shopInflationPerCity = 0,
    this.minorCriticOnDinner = false,
  });

  int cooksDelta;
  int swapsDelta;
  int utensilSlots;
  bool lunchRewardZero;
  TargetScale? targetScale;
  int shopInflationPerCity;
  bool minorCriticOnDinner;
}

/// Folds every stake up to and including [stakeId] into one config.
StakeConfig stakeConfig(int stakeId) {
  final cfg = StakeConfig();
  for (final st in kStakes) {
    if (st.id > stakeId) break;
    for (final m in st.modifiers) {
      switch (m.type) {
        case 'service_reward_zero':
          cfg.lunchRewardZero = true;
        case 'target_scale':
          cfg.targetScale = TargetScale(fromCity: m.fromCity!, pct: m.pct!);
        case 'swaps_delta':
          cfg.swapsDelta += m.value! as int;
        case 'cooks_delta':
          cfg.cooksDelta += m.value! as int;
        case 'shop_inflation_per_city':
          cfg.shopInflationPerCity += m.value! as int;
        case 'minor_critic_on_dinner':
          cfg.minorCriticOnDinner = true;
        case 'utensil_slots':
          cfg.utensilSlots = m.value! as int;
      }
    }
  }
  return cfg;
}

/// The four minor critics the JS build knows.
///
/// **Frozen.** `Rng.pick` indexes by list length, so appending to the pool the run machine
/// draws from changes *which* critic an existing seed rolls. `test/runs_test.dart` therefore
/// passes this list to `newRun`, and the Habanero+ Dinner roll and the Long Route's merged
/// critics land on exactly what the recorded trace saw. Live play uses [kMinorCritics].
const List<Critic> kPortedMinorCritics = [
  Critic(id: 'sweet_tooth', name: 'The Sweet Tooth', rule: 'Every dish must contain a Sweet ingredient', requireFamily: 'sweet', minor: true),
  Critic(id: 'sour_skeptic', name: 'The Sour Skeptic', rule: 'Sour ingredients are debuffed (0 intensity)', debuff: 'sour', minor: true),
  Critic(id: 'small_plates', name: 'Small Plates', rule: 'Dishes may use at most 4 ingredients', maxCards: 4, minor: true),
  Critic(id: 'salt_hater', name: 'The Salt Hater', rule: 'Salty ingredients are debuffed', debuff: 'salty', minor: true),
];

/// The milder Dinner Rush pool, switched on by Habanero (stake 6) and up.
///
/// Minor critics inconvenience a build; they must never cap it, because they land on a
/// Dinner Rush the run cannot skip. Append here, not to [kPortedMinorCritics].
const List<Critic> kMinorCritics = [
  ...kPortedMinorCritics,
  Critic(id: 'hearty_portions', name: 'Hearty Portions', rule: 'Dishes must use at least 2 ingredients', minCards: 2, minor: true),
];

/// Utensils available from the very first run. Note there are no Rares here — a fresh
/// profile therefore has an empty Rare pool, and `rollOffers` falls back to the whole pool.
/// Utensils the shop may offer from the very first run.
///
/// The ported 12 starters, plus the Dart-native expansion. The concept doc wants ~60% of
/// the pool locked at launch to give the unlock ladder something to hand out — but that is a
/// launch-tuning decision, and gating 45 new utensils behind achievements that don't exist
/// yet would make them unreachable, which is strictly worse than unbalanced. The four
/// build-defining rares stay locked so the ladder still has a payoff to give.
const List<String> kStartUtensils = [
  // ported starters
  'iron_tawa', 'salt_cellar', 'honey_jar', 'stock_pot', 'street_cart', 'big_spoon',
  'mint_garnish', 'rice_cooker', 'wok', 'griddle', 'pressure_cooker', 'ice_box',
  // expansion — commons
  'masala_dabba', 'molcajete', 'piloncillo_cone', 'achaar_jar', 'anchovy_tin',
  'katsuobushi_box', 'tadka_pan', 'baklava_tray', 'onggi_crock', 'salt_block',
  'kombu_basket', 'tapas_plate', 'dim_sum_basket', 'meze_tray', 'mercado_stall',
  'donabe', 'thali_plate', 'bento_box', 'chitarra', 'paella_pan', 'cazuela',
  'karahi', 'pilon', 'tortilla_press', 'banana_leaf', 'idli_steamer',
  'garum_amphora', 'wire_spider', 'sac_lid',
  // expansion — uncommons
  'chile_roaster', 'parmesan_wheel', 'cataplana', 'sushi_geta', 'comal', 'metate',
  'saj_griddle', 'braai_grid', 'mangal_grill', 'billig', 'tagine', 'hawker_stall',
  // v1.0 pass — commons
  'ttukbaegi', 'mezzaluna', 'jebena', 'cezve', 'miso_keg', 'berbere_mill', 'otoshibuta',
  // v1.0 pass — uncommons
  'gamasot', 'tiella', 'zeer', 'tamarind_press', 'sugarcane_press', 'suribachi',
  'dashi_kettle', 'mesob', 'kanoun', 'chatti', 'souk_stall',
];

/// The Rares the Royal deck may hand a player who has not unlocked any yet.
///
/// Deliberately a frozen list rather than `kUtensils.where(rarity == 'rare')`. That draw is
/// made from the run seed, so widening it with every content update would silently re-roll
/// the opening of every existing Royal seed — and seed stability is the whole point of
/// [Rng] (CLAUDE.md). It also keeps a brand-new player's free Rare inside the set the deck
/// was tuned against instead of one of the dozens they have never seen.
const List<String> kStarterRareUtensils = [
  'clay_handi', 'grandmother_ladle', 'golden_sieve', 'emperors_wok',
];

/// Utensil id -> the stake you must clear (on any deck) to unlock it.
///
/// NOTE: nothing here (or in [kAchievements]) grants any of the Dart-native expansion
/// utensils yet, so they are catalogued but unreachable in a real profile. Wiring them up
/// is a deliberate follow-up: every hook that could grant them — this map, the achievement
/// rewards, and [kStartUtensils] — is replayed field for field by `test/runs_test.dart`
/// against traces recorded from the JS build, so adding one now would fail those rather
/// than change the game. `tools/sim` force-unlocks the whole catalog, so balance is still
/// measurable in the meantime.
const Map<String, int> kStakeGatedUtensils = {'grandmother_ladle': 3};

/// Coin-generating utensils. Owning 2 at a win unlocks the Street Hawker deck.
const List<String> kVendorIds = ['street_cart', 'chai_stall'];

/// What an achievement hands you. `type` is `utensil` | `deck` | `blend` | `cardback`.
class Reward {
  const Reward({required this.type, required this.id});

  final String type;
  final String id;
}

/// An achievement. [cond] is the generalized `threshold` from `achievements.json`; its keys
/// are interpreted by [condMetAch], and an unknown key is a no-op (it passes), matching JS.
class Achievement {
  const Achievement({
    required this.id,
    required this.name,
    required this.event,
    required this.cond,
    required this.reward,
    required this.teaches,
    this.hidden = false,
  });

  final String id;
  final String name;

  /// The event name passed to [emit].
  final String event;
  final Map<String, Object?> cond;
  final Reward reward;
  final String teaches;

  /// Hidden achievements are not listed until earned.
  final bool hidden;
}

const List<Achievement> kAchievements = [
  Achievement(id: 'first_dish', name: 'Service Started', event: 'dish_played', cond: {}, reward: Reward(type: 'cardback', id: 'parchment'), teaches: 'You cooked your first dish'),
  Achievement(id: 'first_flush', name: 'First Flush', event: 'dish_played', cond: {'pattern': 'flush'}, reward: Reward(type: 'utensil', id: 'golden_sieve'), teaches: 'Flushes are a build, not luck'),
  Achievement(id: 'feast_mode', name: 'Feast Mode', event: 'dish_played', cond: {'pattern': 'full_house'}, reward: Reward(type: 'utensil', id: 'butchers_block'), teaches: 'Pattern hierarchy'),
  Achievement(id: 'big_batch', name: 'Big Batch', event: 'dish_played', cond: {'cards': 5}, reward: Reward(type: 'utensil', id: 'emperors_wok'), teaches: 'Wide dishes'),
  Achievement(id: 'ten_grand', name: 'Ten Grand', event: 'dish_played', cond: {'min_score': 10000}, reward: Reward(type: 'utensil', id: 'clay_handi'), teaches: 'Multiplier stacking'),
  Achievement(id: 'pure_heat', name: 'Pure Heat', event: 'dish_played', cond: {'all_family': 'spicy', 'min_cards': 3}, reward: Reward(type: 'utensil', id: 'tandoor'), teaches: 'All-Spicy synergy'),
  Achievement(id: 'three_peat', name: "Three's Company", event: 'dish_played', cond: {'pattern': 'three_kind'}, reward: Reward(type: 'cardback', id: 'curry'), teaches: 'Three of a kind'),
  Achievement(id: 'two_pair_pro', name: 'Double Up', event: 'dish_played', cond: {'pattern': 'two_pair'}, reward: Reward(type: 'cardback', id: 'combo'), teaches: 'Two pair'),
  Achievement(id: 'straight_up', name: 'Straight Up', event: 'dish_played', cond: {'pattern': 'straight'}, reward: Reward(type: 'cardback', id: 'sadya'), teaches: 'Straights'),
  Achievement(id: 'four_star', name: 'Four-Star Dish', event: 'dish_played', cond: {'pattern': 'four_kind'}, reward: Reward(type: 'cardback', id: 'royal_cb'), teaches: 'Four of a kind'),
  Achievement(id: 'masterpiece', name: 'Masterpiece', event: 'dish_played', cond: {'pattern': 'straight_flush'}, reward: Reward(type: 'cardback', id: 'masterpiece'), teaches: 'Straight flush', hidden: true),
  Achievement(id: 'high_roller', name: 'High Roller', event: 'dish_played', cond: {'min_score': 1000}, reward: Reward(type: 'cardback', id: 'saffron'), teaches: 'Scaling a single dish'),
  Achievement(id: 'heat_wave', name: 'Heat Wave', event: 'dish_played', cond: {'min_heat': 20}, reward: Reward(type: 'cardback', id: 'ember'), teaches: 'Heat is the multiplier track'),
  Achievement(id: 'money_lender', name: 'Money Lender', event: 'coins_held', cond: {'min': 20}, reward: Reward(type: 'utensil', id: 'chai_stall'), teaches: 'Interest economy'),
  Achievement(id: 'window_shopper', name: 'Window Shopper', event: 'reroll_count', cond: {'min': 10}, reward: Reward(type: 'cardback', id: 'ledger'), teaches: 'Reroll value'),
  Achievement(id: 'kitchen_master', name: 'Kitchen Master', event: 'kitchen_level', cond: {'min': 8}, reward: Reward(type: 'cardback', id: 'festival_cb'), teaches: 'Festival leveling compounds'),
  Achievement(id: 'minimal_effort', name: 'Minimal Effort', event: 'service_cleared', cond: {'critic': true, 'max_cards_all': 3}, reward: Reward(type: 'utensil', id: 'bamboo_steamer'), teaches: 'Playing around rules'),
  Achievement(id: 'steady_hands', name: 'Steady Hands', event: 'service_cleared', cond: {'no_swaps': true}, reward: Reward(type: 'cardback', id: 'steady'), teaches: 'Discipline with swaps'),
  Achievement(id: 'globetrotter', name: 'Globetrotter', event: 'reached_city', cond: {'city': 2}, reward: Reward(type: 'cardback', id: 'route'), teaches: 'The full journey'),
  Achievement(id: 'first_route', name: 'The Route is Yours', event: 'run_won', cond: {}, reward: Reward(type: 'deck', id: 'coastal'), teaches: 'Beat a full run'),
  Achievement(id: 'feeling_heat', name: 'Feeling the Heat', event: 'run_won', cond: {'min_stake': 2}, reward: Reward(type: 'deck', id: 'royal'), teaches: 'Winning at a higher stake'),
  Achievement(id: 'street_smart', name: 'Street Smart', event: 'run_won', cond: {'vendors': 2}, reward: Reward(type: 'deck', id: 'hawker'), teaches: 'Vendor (coin) builds'),
  Achievement(id: 'street_legend', name: 'Street Legend', event: 'dish_played', cond: {'pattern': 'five_kind'}, reward: Reward(type: 'cardback', id: 'legend'), teaches: 'Duplicate ranks with blends', hidden: true),
  Achievement(id: 'family_feast', name: 'Family Feast', event: 'dish_played', cond: {'pattern': 'full_family'}, reward: Reward(type: 'cardback', id: 'family'), teaches: 'Convert a family with Chili Oil', hidden: true),
  Achievement(id: 'perfect_palate', name: 'Perfect Palate', event: 'dish_played', cond: {'pattern': 'perfect_palate'}, reward: Reward(type: 'cardback', id: 'perfect'), teaches: 'The apex dish', hidden: true),
];

final Map<String, Achievement> kAchievementById = {for (final a in kAchievements) a.id: a};

// ---------------------------------------------------------------------------
// Meta-save
// ---------------------------------------------------------------------------

/// The storage key the web build uses. Kept identical so saves are portable.
const String kProfileKey = 'tadka_profile_v1';

/// The persistence seam. Implement this over `shared_preferences` (or a file, or a test
/// double) and assign it to [profileStore] before the profile is first read.
///
/// Both methods must be synchronous and must not throw for a missing key — return null.
/// [loadProfile] and [saveProfile] still guard with try/catch, matching the web build's
/// CSP-safety wrapper around `localStorage`.
abstract class ProfileStore {
  /// The stored JSON document, or null when nothing has been saved yet.
  String? read();

  /// Persists [json] under [kProfileKey].
  void write(String json);
}

/// The default store: keeps the save in memory only. Correct for `tools/sim` and tests,
/// and a safe no-op fallback for the app before a real store is injected.
class MemoryProfileStore implements ProfileStore {
  String? _data;

  @override
  String? read() => _data;

  @override
  void write(String json) => _data = json;
}

/// Swap this out at app startup, before the first [profile] access.
ProfileStore profileStore = MemoryProfileStore();

/// The daily-challenge slice of the save. Untouched by M0; present so the JSON shape
/// matches the web build's and a v1.0 save round-trips.
class DailyProgress {
  DailyProgress({this.lastPlayed = '', this.streak = 0, this.bestDailyScore = 0});

  factory DailyProgress.fromJson(Map<String, Object?> j) => DailyProgress(
    lastPlayed: (j['last_played'] as String?) ?? '',
    streak: (j['streak'] as num?)?.toInt() ?? 0,
    bestDailyScore: (j['best_daily_score'] as num?)?.toInt() ?? 0,
  );

  String lastPlayed;
  int streak;
  int bestDailyScore;

  Map<String, Object?> toJson() => {
    'last_played': lastPlayed,
    'streak': streak,
    'best_daily_score': bestDailyScore,
  };
}

/// One Long Route leaderboard row.
class EndlessEntry {
  const EndlessEntry({
    required this.seed,
    required this.distance,
    required this.score,
    required this.deck,
    required this.stake,
  });

  factory EndlessEntry.fromJson(Map<String, Object?> j) => EndlessEntry(
    seed: (j['seed'] as String?) ?? '',
    distance: (j['distance'] as num?)?.toInt() ?? 0,
    score: (j['score'] as num?)?.toInt() ?? 0,
    deck: (j['deck'] as String?) ?? '',
    stake: (j['stake'] as num?)?.toInt() ?? 1,
  );

  final String seed;
  final int distance;
  final int score;
  final String deck;
  final int stake;

  Map<String, Object?> toJson() => {
    'seed': seed,
    'distance': distance,
    'score': score,
    'deck': deck,
    'stake': stake,
  };
}

/// The meta-save: everything that outlives a run.
///
/// [unlocks], [stakeProgress] and [stats] stay as maps rather than typed fields because the
/// web build writes them with computed keys (`unlocks[type + 's']`, `stats[k]`). Keeping the
/// same shape is what makes the JSON byte-compatible and the merge in [loadProfile] exact.
class Profile {
  Profile({
    required this.profileVersion,
    required this.unlocks,
    required this.achievementsDone,
    required this.recipesDiscovered,
    required this.stakeProgress,
    required this.stats,
    required this.daily,
    required this.endlessTop10,
  });

  int profileVersion;

  /// `utensils` | `blends` | `decks` | `cardbacks` -> unlocked ids.
  Map<String, List<String>> unlocks;
  List<String> achievementsDone;
  List<String> recipesDiscovered;

  /// Deck id -> highest stake unlocked for it.
  Map<String, int> stakeProgress;

  /// `runs` | `wins` | `best_dish` | `best_distance` | `total_dishes`.
  Map<String, int> stats;
  DailyProgress daily;
  List<EndlessEntry> endlessTop10;

  /// Key order matches the web build's `defaultProfile()`, so a fresh save is byte-identical.
  Map<String, Object?> toJson() => {
    'profile_version': profileVersion,
    'unlocks': unlocks,
    'achievements_done': achievementsDone,
    'recipes_discovered': recipesDiscovered,
    'stake_progress': stakeProgress,
    'stats': stats,
    'daily': daily.toJson(),
    'endless_top10': endlessTop10.map((e) => e.toJson()).toList(),
  };
}

/// A brand-new save. Everything else merges over this.
Profile defaultProfile() => Profile(
  profileVersion: 1,
  unlocks: {'utensils': [], 'blends': [], 'decks': ['home'], 'cardbacks': []},
  achievementsDone: [],
  recipesDiscovered: [],
  stakeProgress: {'home': 1},
  stats: {'runs': 0, 'wins': 0, 'best_dish': 0, 'best_distance': 0, 'total_dishes': 0},
  daily: DailyProgress(),
  endlessTop10: [],
);

List<String> _strings(Object? v) =>
    v is List ? v.whereType<String>().toList() : <String>[];

Map<String, int> _ints(Object? v) => v is Map
    ? {for (final e in v.entries) '${e.key}': (e.value as num?)?.toInt() ?? 0}
    : <String, int>{};

/// Reads the save, merging it over [defaultProfile].
///
/// The merge is per field, exactly as the web build's
/// `Object.assign(d, p, {unlocks: Object.assign(d.unlocks, p.unlocks)})`: a field the save
/// does not carry keeps its default, which is how fields added in a later version survive an
/// old save. Anything unreadable — missing key, corrupt JSON, a store that throws — falls
/// back to a fresh profile rather than propagating the failure.
Profile loadProfile() {
  try {
    final raw = profileStore.read();
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        final version = decoded['profile_version'];
        // JS guards with `if (p && p.profile_version)` — a 0 version is falsy there too.
        if (version is num && version != 0) {
          final d = defaultProfile();
          final u = decoded['unlocks'];
          if (u is Map) {
            for (final e in u.entries) {
              d.unlocks['${e.key}'] = _strings(e.value);
            }
          }
          if (decoded.containsKey('profile_version')) d.profileVersion = version.toInt();
          if (decoded.containsKey('achievements_done')) d.achievementsDone = _strings(decoded['achievements_done']);
          if (decoded.containsKey('recipes_discovered')) d.recipesDiscovered = _strings(decoded['recipes_discovered']);
          if (decoded.containsKey('stake_progress')) d.stakeProgress = _ints(decoded['stake_progress']);
          if (decoded.containsKey('stats')) d.stats = _ints(decoded['stats']);
          final daily = decoded['daily'];
          if (daily is Map) d.daily = DailyProgress.fromJson(daily.cast<String, Object?>());
          final top = decoded['endless_top10'];
          if (top is List) {
            d.endlessTop10 = top
                .whereType<Map<dynamic, dynamic>>()
                .map((e) => EndlessEntry.fromJson(e.cast<String, Object?>()))
                .toList();
          }
          return d;
        }
      }
    }
  } catch (_) {
    // Corrupt or unreadable save: start fresh rather than crash the app.
  }
  return defaultProfile();
}

/// The live meta-save. Write-through: every mutator below calls [saveProfile].
///
/// Assign directly to reset it (tests do `profile = defaultProfile()`); assign
/// [profileStore] first if you want the initial read to come from real storage.
Profile profile = loadProfile();

/// Re-reads the save from [profileStore]. Call after injecting a real store late.
void reloadProfile() => profile = loadProfile();

void saveProfile() {
  try {
    profileStore.write(jsonEncode(profile.toJson()));
  } catch (_) {
    // Storage denied (CSP, full disk, no permission): the run continues unsaved.
  }
}

/// Is [id] of [type] (`deck` | `utensil` | `blend` | `cardback`) available?
///
/// `home` and the 12 [kStartUtensils] are always available; they are not written into the
/// save, so a fresh profile still has a playable pool.
///
/// [kShowAllContent] short-circuits the whole question for internal builds. It is a *read*
/// override only — [unlockThing] still records the real unlock, so the ladder underneath is
/// untouched and flipping the flag off restores gated behaviour exactly.
bool isUnlocked(String type, String id) {
  if (kShowAllContent) return true;
  if (type == 'deck') return id == 'home' || (profile.unlocks['decks'] ?? const []).contains(id);
  if (type == 'utensil') {
    return kStartUtensils.contains(id) || (profile.unlocks['utensils'] ?? const []).contains(id);
  }
  return (profile.unlocks['${type}s'] ?? const []).contains(id);
}

/// Records an unlock. Returns true only the first time, which is what drives the toast.
bool unlockThing(String type, String id) {
  final k = '${type}s';
  final list = profile.unlocks.putIfAbsent(k, () => <String>[]);
  if (!list.contains(id)) {
    list.add(id);
    saveProfile();
    return true;
  }
  return false;
}

/// Bazaar pool. Order follows [kUtensils], not unlock order, so shop rolls stay deterministic.
/// The utensil catalog the shop draws from.
///
/// Defaults to everything. The differential trace tests narrow it to the ported set,
/// because those tests exist to pin the PORT — that the Dart run machine reproduces the JS
/// one step for step — not to freeze the game's content forever. The web build has no
/// knowledge of Dart-native utensils and never will, so scoping the fixture's world is the
/// honest fix; the alternative was leaving 45 utensils unreachable to keep a fixture happy.
List<Utensil> activeUtensilCatalog = kUtensils;

List<Utensil> unlockedUtensilPool() =>
    activeUtensilCatalog.where((u) => isUnlocked('utensil', u.id)).toList();

/// The blend catalog the shop draws from. Same seam as [activeUtensilCatalog], same reason.
///
/// `rollOffers` picks a blend by index off the seeded RNG, so the *length* of this list is
/// part of the seed contract: 6 entries and 20 entries hand a given roll different blends.
/// The differential traces in `test/runs_test.dart` narrow it to the ported six so they keep
/// pinning the run machine against a JS engine that has never heard of the other fourteen.
List<Blend> activeBlendCatalog = kBlends;

/// The festival catalog the shop draws from. Third instance of the same seam, same reason.
///
/// `rollOffers` does `rng.pick` over this list, so its length decides which festival a given
/// roll produces — appending three to a list of seven re-rolls every recorded festival offer.
/// `test/runs_test.dart` narrows it to [kPortedFestivals]; live play gets all ten.
List<Festival> activeFestivalCatalog = kFestivals;

/// The decks the start screen may offer.
///
/// `reserved` decks stay out even under [kShowAllContent]: Monsoon Larder is a v1.1 placeholder
/// with no mechanics behind it, so listing it would show a tester an empty box, not content.
List<Deck> unlockedDecks() =>
    activeDeckCatalog.where((d) => !d.reserved && isUnlocked('deck', d.id)).toList();

/// The highest stake selectable for [deckId]. [kShowAllContent] opens the whole ladder;
/// [setStakeProgress] keeps recording the real progression underneath either way.
int maxStake(String deckId) =>
    kShowAllContent ? kStakes.length : (profile.stakeProgress[deckId] ?? 1);

void setStakeProgress(String deckId, int stake) {
  if (stake > (profile.stakeProgress[deckId] ?? 1)) {
    profile.stakeProgress[deckId] = stake > 8 ? 8 : stake;
    saveProfile();
  }
}

/// Marks a recipe as seen in the Recipe Book. The three secret recipes announce themselves.
void recordRecipe(String pattern) {
  if (!profile.recipesDiscovered.contains(pattern)) {
    profile.recipesDiscovered.add(pattern);
    saveProfile();
    if (kSecretPatterns.contains(pattern)) {
      queueUnlock('🍽 Secret recipe found: ${kGenericNames[pattern]}');
    }
  }
}

void bumpStat(String k, int v) {
  profile.stats[k] = (profile.stats[k] ?? 0) + v;
  saveProfile();
}

void setBest(String k, int v) {
  if (v > (profile.stats[k] ?? 0)) {
    profile.stats[k] = v;
    saveProfile();
  }
}

// ---------------------------------------------------------------------------
// Achievement / unlock event bus
// ---------------------------------------------------------------------------

final List<String> _unlockQueue = <String>[];

/// Queues a toast line. The UI drains it with [drainUnlockQueue] after each action.
void queueUnlock(String msg) => _unlockQueue.add(msg);

/// Takes every queued unlock message and clears the queue.
List<String> drainUnlockQueue() {
  final msgs = List<String>.of(_unlockQueue);
  _unlockQueue.clear();
  return msgs;
}

String rewardLabel(Reward r) {
  if (r.type == 'utensil') return kUtensilById[r.id]?.name ?? r.id;
  if (r.type == 'deck') return kDeckById[r.id]?.name ?? r.id;
  if (r.type == 'blend') return kBlendById[r.id]?.name ?? r.id;
  if (r.type == 'cardback') return 'a card back';
  return r.id;
}

/// Applies [r]. Returns true when it was genuinely new.
bool grantReward(Reward r) {
  if (r.type == 'utensil') return unlockThing('utensil', r.id);
  if (r.type == 'deck') return unlockThing('deck', r.id);
  if (r.type == 'blend') return unlockThing('blend', r.id);
  if (r.type == 'cardback') return unlockThing('cardback', r.id);
  return false;
}

/// The facts an event carries. Every field is nullable: each event fills a different subset,
/// and [condMetAch] treats a missing field as "condition not met", matching JS, where
/// `undefined >= 3` is false.
class AchievementPayload {
  const AchievementPayload({
    this.pattern,
    this.score,
    this.heat,
    this.cards,
    this.allSameFamily,
    this.family,
    this.value,
    this.stake,
    this.deck,
    this.vendors,
    this.city,
    this.critic,
    this.maxCardsAll,
    this.noSwaps,
  });

  final String? pattern;
  final int? score;
  final double? heat;
  final int? cards;
  final bool? allSameFamily;
  final String? family;

  /// Generic scalar for the `min` conditions (coins held, reroll count, kitchen level).
  final num? value;
  final int? stake;
  final String? deck;
  final int? vendors;
  final int? city;
  final bool? critic;
  final int? maxCardsAll;
  final bool? noSwaps;
}

/// Evaluates one achievement's condition map against an event payload.
///
/// Every key must hold. An unrecognised key is skipped rather than failing — the web build's
/// if/else chain does the same, so a condition from a newer content pack degrades to "always
/// true" instead of silently locking the achievement.
bool condMetAch(Map<String, Object?> cond, AchievementPayload pl) {
  for (final e in cond.entries) {
    final v = e.value;
    switch (e.key) {
      case 'pattern':
        if (pl.pattern != v) return false;
      case 'cards':
        if (pl.cards != v) return false;
      case 'min_cards':
        if (!_atLeast(pl.cards, v)) return false;
      case 'min_score':
        if (!_atLeast(pl.score, v)) return false;
      case 'min_heat':
        if (!_atLeast(pl.heat, v)) return false;
      case 'all_family':
        if (pl.allSameFamily != true || pl.family != v) return false;
      case 'min':
        if (!_atLeast(pl.value, v)) return false;
      case 'min_stake':
        if (!_atLeast(pl.stake, v)) return false;
      case 'vendors':
        if (!_atLeast(pl.vendors, v)) return false;
      case 'city':
        if (pl.city != v) return false;
      case 'critic':
        if (pl.critic != true) return false;
      case 'max_cards_all':
        if (!_atMost(pl.maxCardsAll, v)) return false;
      case 'no_swaps':
        if (pl.noSwaps != true) return false;
    }
  }
  return true;
}

/// `actual >= threshold`, with a missing [actual] failing — JS `undefined >= n` is false.
bool _atLeast(num? actual, Object? threshold) =>
    actual != null && threshold is num && actual >= threshold;

/// `actual <= threshold`, with a missing [actual] failing.
bool _atMost(num? actual, Object? threshold) =>
    actual != null && threshold is num && actual <= threshold;

/// Fires [event]. Every not-yet-earned achievement listening for it whose condition holds is
/// marked done, granted, and queued for a toast — in [kAchievements] order, which matters
/// because granting a utensil widens the bazaar pool for the rest of the run.
void emit(String event, [AchievementPayload? payload]) {
  final pl = payload ?? const AchievementPayload();
  for (final a in kAchievements) {
    if (a.event != event || profile.achievementsDone.contains(a.id)) continue;
    if (!condMetAch(a.cond, pl)) continue;
    profile.achievementsDone.add(a.id);
    final got = grantReward(a.reward);
    saveProfile();
    queueUnlock('🏆 ${a.name}${got ? ' — unlocked ${rewardLabel(a.reward)}' : ''}');
  }
}

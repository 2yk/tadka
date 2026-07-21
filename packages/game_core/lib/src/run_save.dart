/// Saving and resuming a run in progress.
///
/// A full route is 24 services — half an hour or more. Phones background apps and the OS
/// reclaims them without warning, so a run that only exists in memory is a run the player
/// will eventually lose through no fault of their own. That is the worst bug this game can
/// have, because it destroys the thing the player was actually invested in.
///
/// What gets saved, and what gets rebuilt:
///
/// The immutable inputs — seed, stake, deck — are saved and everything derivable is REBUILT
/// from them on resume: the route (drawn from its own `Rng('route:$seed')`, so it is a pure
/// function of the seed), the deck config, the stake config, the base cook and swap counts.
/// Rebuilding rather than storing means a save can't disagree with the catalog it came from.
///
/// The RNG's position is saved explicitly. Determinism is the seed contract this whole
/// codebase is built on, so a resumed run has to continue the identical draw sequence — not
/// restart it, which would re-deal the deck the player already knows.
///
/// Cards are saved in full rather than by id, because blends mutate them: Chili Oil rewrites
/// a card's family and display, Fermentation its rank, Sun-Dry duplicates one into a card
/// whose id is no longer unique. An id lookup would silently undo every blend the player
/// spent coins on. Critics are saved in full for the same reason — merged Legend critics on
/// the Long Route are generated at runtime and exist in no catalog.
library;

import 'catalog.dart';
import 'models.dart';
import 'run.dart';

/// Bumped when the shape below changes incompatibly. A save from an older build is
/// discarded rather than guessed at — a half-restored run is worse than a lost one.
const int kRunSaveVersion = 1;

Map<String, Object?> _cardToJson(Card c) => {
  'id': c.id,
  'family': c.family,
  'rank': c.rank,
  'display': c.display,
  if (c.prized) 'prized': true,
};

Card _cardFromJson(Map<String, Object?> j) => Card(
  id: j['id']! as String,
  family: j['family']! as String,
  rank: (j['rank']! as num).toInt(),
  display: j['display']! as String,
  prized: j['prized'] == true,
);

Map<String, Object?> _criticToJson(Critic c) => {
  'id': c.id,
  'name': c.name,
  'rule': c.rule,
  if (c.maxCards != null) 'maxCards': c.maxCards,
  if (c.minCards != null) 'minCards': c.minCards,
  if (c.debuff != null) 'debuff': c.debuff,
  if (c.requireFamily != null) 'requireFamily': c.requireFamily,
};

Critic _criticFromJson(Map<String, Object?> j) => Critic(
  id: j['id']! as String,
  name: j['name']! as String,
  rule: j['rule']! as String,
  maxCards: (j['maxCards'] as num?)?.toInt(),
  minCards: (j['minCards'] as num?)?.toInt(),
  debuff: j['debuff'] as String?,
  requireFamily: j['requireFamily'] as String?,
);

Map<String, Object?> _cityToJson(City c) => {
  'id': c.id,
  'name': c.name,
  'targets': c.targets,
  'critic': c.critic,
  if (c.criticObj != null) 'criticObj': _criticToJson(c.criticObj!),
};

City _cityFromJson(Map<String, Object?> j) => City(
  id: j['id']! as String,
  name: j['name']! as String,
  targets: (j['targets']! as List<Object?>).map((t) => (t! as num).toInt()).toList(),
  critic: j['critic'] as String? ?? '',
  criticObj: j['criticObj'] == null
      ? null
      : _criticFromJson((j['criticObj']! as Map).cast<String, Object?>()),
);

Map<String, Object?> _recordToJson(ServiceRecord r) => {
  'city': r.city,
  'svc': r.svc,
  'score': r.score,
  'target': r.target,
  'win': r.win,
};

ServiceRecord _recordFromJson(Map<String, Object?> j) => ServiceRecord(
  city: j['city']! as String,
  svc: j['svc']! as String,
  score: (j['score']! as num).toInt(),
  target: (j['target']! as num).toInt(),
  win: j['win']! as bool,
);

/// Serialises a run in progress.
Map<String, Object?> runToJson(RunState run) => {
  'v': kRunSaveVersion,
  // inputs — everything derivable is rebuilt from these
  'seed': run.seed,
  'stake': run.stake,
  'deckId': run.deckId,
  // the generator's position, so the resumed run continues the same sequence
  'rng': run.rng.state,
  // progress
  'cityIndex': run.cityIndex,
  'serviceIndex': run.serviceIndex,
  'coins': run.coins,
  'kitchenLevel': run.kitchenLevel,
  'status': run.status,
  'totalScore': run.totalScore,
  'rerolls': run.rerolls,
  'target': run.target,
  'score': run.score,
  'cooksLeft': run.cooksLeft,
  'swapsLeft': run.swapsLeft,
  'dishesPlayed': run.dishesPlayed,
  'svcMaxCards': run.svcMaxCards,
  'svcSwapsUsed': run.svcSwapsUsed,
  // the Long Route
  'endless': run.endless,
  'endlessCity': run.endlessCity,
  'endlessBase': run.endlessBase,
  'distance': run.distance,
  if (run.endlessCityObj != null) 'endlessCityObj': _cityToJson(run.endlessCityObj!),
  // inventory — utensils and blends are never mutated, so ids are enough
  'utensils': run.utensils.map((u) => u.id).toList(),
  'blends': run.blends.map((b) => b.id).toList(),
  // cards are saved whole: blends rewrite family, rank, display and id
  'deck': run.deck.map(_cardToJson).toList(),
  'hand': run.hand.map(_cardToJson).toList(),
  if (run.critic != null) 'critic': _criticToJson(run.critic!),
  'history': run.history.map(_recordToJson).toList(),
};

/// Rebuilds a saved run, or returns null if the save is unusable.
///
/// Returns null rather than throwing, and rather than partially restoring: every failure
/// here — an old version, a renamed utensil, a truncated write — ends with the player at the
/// menu able to start a fresh run, which is recoverable. A half-restored run is not.
RunState? runFromJson(Map<String, Object?> j) {
  try {
    if ((j['v'] as num?)?.toInt() != kRunSaveVersion) return null;

    // Rebuild the immutable skeleton from the inputs, exactly as a fresh run would.
    final run = newRun(
      seed: j['seed']! as String,
      stake: (j['stake']! as num).toInt(),
      deckId: j['deckId']! as String,
    );

    // newRun deals a hand and draws from the RNG; overwrite all of it with the saved state.
    run.rng.restore((j['rng']! as num).toInt());

    run
      ..cityIndex = (j['cityIndex']! as num).toInt()
      ..serviceIndex = (j['serviceIndex']! as num).toInt()
      ..coins = (j['coins']! as num).toInt()
      ..kitchenLevel = (j['kitchenLevel']! as num).toInt()
      ..status = j['status']! as String
      ..totalScore = (j['totalScore']! as num).toInt()
      ..rerolls = (j['rerolls']! as num).toInt()
      ..target = (j['target']! as num).toInt()
      ..score = (j['score']! as num).toInt()
      ..cooksLeft = (j['cooksLeft']! as num).toInt()
      ..swapsLeft = (j['swapsLeft']! as num).toInt()
      ..dishesPlayed = (j['dishesPlayed']! as num).toInt()
      ..svcMaxCards = (j['svcMaxCards']! as num).toInt()
      ..svcSwapsUsed = (j['svcSwapsUsed']! as num).toInt()
      ..endless = j['endless']! as bool
      ..endlessCity = (j['endlessCity']! as num).toInt()
      ..endlessBase = (j['endlessBase']! as num).toDouble()
      ..distance = (j['distance']! as num).toInt();

    final endlessCity = j['endlessCityObj'];
    run.endlessCityObj = endlessCity == null
        ? null
        : _cityFromJson((endlessCity as Map).cast<String, Object?>());

    // An id that no longer names anything means the catalog changed under the save. Drop
    // the run rather than resume it a utensil short and let the player wonder why.
    final utensils = <Utensil>[];
    for (final id in (j['utensils']! as List<Object?>).cast<String>()) {
      final u = kUtensilById[id];
      if (u == null) return null;
      utensils.add(u);
    }
    final blends = <Blend>[];
    for (final id in (j['blends']! as List<Object?>).cast<String>()) {
      final b = kBlendById[id];
      if (b == null) return null;
      blends.add(b);
    }
    run
      ..utensils = utensils
      ..blends = blends
      ..deck = (j['deck']! as List<Object?>)
          .map((c) => _cardFromJson((c! as Map).cast<String, Object?>()))
          .toList()
      ..hand = (j['hand']! as List<Object?>)
          .map((c) => _cardFromJson((c! as Map).cast<String, Object?>()))
          .toList()
      ..history = (j['history']! as List<Object?>)
          .map((r) => _recordFromJson((r! as Map).cast<String, Object?>()))
          .toList();

    final critic = j['critic'];
    run.critic = critic == null
        ? null
        : _criticFromJson((critic as Map).cast<String, Object?>());

    return run;
  } on Object {
    // Deliberately broad: a corrupt or truncated save is data, not a programming error, and
    // it must never take the app down on launch.
    return null;
  }
}

/// True when a saved run is worth offering to resume — i.e. still in progress.
bool isResumable(RunState run) => run.status == 'playing';

/// A one-line description for the resume prompt.
String resumeSummary(RunState run) {
  if (run.endless) return 'The Long Route · ${run.endlessCity} — ${run.score} scored';
  final city = cityOf(run);
  final svc = kServiceNames[run.serviceIndex];
  return '${city.name} · $svc — ${run.score} / ${run.target}';
}

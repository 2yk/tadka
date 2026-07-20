/// Bridges the pure `game_core` run state to the Flutter widget tree.
///
/// Deliberately thin: it owns no rules. Every decision — legality, scoring, economy, offers —
/// is delegated to `game_core`, exactly as the web build's Coach drives the live engine rather
/// than reimplementing it. A parallel implementation that drifts is worse than none.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:shared_preferences/shared_preferences.dart';

import 'daily.dart';

/// Which screen the run is currently sitting on.
enum Phase { start, service, bazaar, summary, victory, recipeBook, help }

/// Persists the meta-save through `shared_preferences`, keeping `game_core` Flutter-free.
///
/// Writes are fire-and-forget against an in-memory mirror so `saveProfile()` can stay
/// synchronous, matching the web build's write-through `localStorage` behaviour.
class PrefsProfileStore implements gc.ProfileStore {
  PrefsProfileStore(this._prefs) : _cache = _prefs.getString(_key);

  static const _key = 'tadka_profile_v1';
  final SharedPreferences _prefs;
  String? _cache;

  @override
  String? read() => _cache;

  @override
  void write(String json) {
    _cache = json;
    unawaited(_prefs.setString(_key, json));
  }
}

class GameController extends ChangeNotifier {
  GameController([this._prefs]) {
    coachOn = _prefs?.getBool(_coachKey) ?? false;
  }

  static const _coachKey = 'tadka_coach';
  static const _seenHelpKey = 'tadka_seen_help';
  final SharedPreferences? _prefs;

  gc.RunState? run;
  Phase phase = Phase.start;

  /// Indices into `run.hand` the player has tapped.
  final List<int> selected = [];

  /// Offers on the current bazaar screen; null until rolled.
  List<gc.Offer>? offers;

  /// The most recent cook, so the service screen can animate it.
  gc.ScoreResult? lastResult;

  /// Unlock toasts drained from the achievement bus.
  final List<String> toasts = [];

  String? errorMessage;

  /// Coach visibility. Persisted, because it's a learning aid you leave on for a while and
  /// having to re-enable it every launch is exactly the friction that stops people using it.
  bool coachOn = false;

  // ---- start screen selections
  String deckId = 'home';
  int stake = 1;

  /// True while the current run is today's Daily Route, so the summary can record it and the
  /// UI can label it. Cleared by any normal run.
  bool isDaily = false;

  /// Injected so tests can pin a date instead of depending on when they run.
  DateTime Function() now = DateTime.now;

  DailyStatus get daily => dailyStatus(now());

  /// Starts today's Daily on fixed settings — a deck or stake choice would make scores
  /// incomparable, which is the only thing the mode is for.
  void startDaily() {
    deckId = kDailyDeck;
    stake = kDailyStake;
    startRun(dailySeed(now()));
    isDaily = true;
    notifyListeners();
  }

  void startRun(String seed) {
    run = gc.newRun(seed: seed, stake: stake, deckId: deckId);
    isDaily = false;
    final needsRules = !_seenHelp;
    phase = Phase.service;
    selected.clear();
    lastResult = null;
    errorMessage = null;
    _drainToasts();
    // A first-time player should meet the rules before the first hand, not after losing to
    // them. Shown once ever; the ? button is always there afterwards.
    if (needsRules) {
      _bookReturn = Phase.service;
      openHelp();
      return;
    }
    notifyListeners();
  }

  /// Ranked legal dishes for the current hand, straight from the game_core solver.
  /// Recomputed on demand rather than cached: it costs well under a frame (~0.6ms), and a
  /// stale suggestion is a suggestion that lies.
  List<gc.DishSuggestion> get suggestions {
    final r = run;
    if (r == null || !coachOn) return const [];
    return gc.suggestDishes(r);
  }

  /// Bazaar offers ranked by real marginal value to this build; best buy first.
  List<gc.OfferValuation> get offerValuations {
    final r = run;
    if (r == null || !coachOn || offers == null) return const [];
    return gc.rankOffers(r, offers!);
  }

  void toggleCoach() {
    coachOn = !coachOn;
    unawaited(_prefs?.setBool(_coachKey, coachOn) ?? Future<bool>.value(false));
    notifyListeners();
  }

  /// Replaces the selection with exactly the cards a Coach row describes.
  void loadSuggestion(List<int> handIndexes) {
    selected
      ..clear()
      ..addAll(handIndexes);
    errorMessage = null;
    notifyListeners();
  }

  void toggleCard(int index) {
    if (selected.contains(index)) {
      selected.remove(index);
    } else {
      if (selected.length >= 5) return;
      selected.add(index);
    }
    errorMessage = null;
    notifyListeners();
  }

  /// Live preview of the currently selected dish, or null if nothing is selected.
  /// Uses the real `scoreDish`, so the number shown is exactly what will be scored.
  gc.ScoreResult? get preview {
    final r = run;
    if (r == null || selected.isEmpty) return null;
    final cards = selected.map((i) => r.hand[i]).toList();
    if (gc.dishError(cards, r.critic) != null) return null;
    return gc.scoreDish(cards, gc.ctxFor(r));
  }

  /// Why COOK is disabled, or null when the dish is legal.
  String? get cookBlocker {
    final r = run;
    if (r == null) return null;
    return gc.dishError(selected.map((i) => r.hand[i]).toList(), r.critic);
  }

  /// Commits a cook. Returns the outcome so the screen can sequence its animation before
  /// advancing; state changes that affect layout are notified immediately.
  gc.CookOutcome? cook() {
    final r = run;
    if (r == null || selected.isEmpty) return null;
    final idxs = List<int>.of(selected)..sort();
    final out = gc.doCook(r, idxs);
    if (out.error != null) {
      errorMessage = out.error;
      notifyListeners();
      return out;
    }
    lastResult = out.result;
    selected.clear();
    _drainToasts();
    notifyListeners();
    return out;
  }

  /// Applies the blend in slot [index] to the current selection.
  ///
  /// Blends are the only route to the three secret recipes, and the only mechanic that
  /// edits cards rather than scoring them — so the selection is cleared afterwards and the
  /// hand re-rendered from scratch.
  String? useBlend(int index) {
    final r = run;
    if (r == null) return null;
    final out = gc.applyBlend(r, index, List<int>.of(selected));
    if (out.error != null) {
      errorMessage = out.error;
      notifyListeners();
      return out.error;
    }
    selected.clear();
    errorMessage = null;
    notifyListeners();
    return null;
  }

  void swap() {
    final r = run;
    if (r == null || selected.isEmpty) return;
    final out = gc.doSwap(r, List<int>.of(selected)..sort());
    if (out.error != null) {
      errorMessage = out.error;
    } else {
      selected.clear();
      errorMessage = null;
    }
    notifyListeners();
  }

  /// Service cleared: bank the economy, then either finish the run or open the bazaar.
  void afterServiceWon() {
    final r = run!;
    final wasBoss = r.serviceIndex == 2;
    gc.bankService(r);
    if (wasBoss) r.kitchenLevel += 3;
    if (gc.isFinalService(r)) {
      gc.onRunWon(r);
      r.status = 'won';
      if (isDaily) recordDaily(now(), r.totalScore);
      phase = Phase.victory;
    } else {
      offers = gc.rollOffers(r);
      phase = Phase.bazaar;
    }
    _drainToasts();
    notifyListeners();
  }

  void afterServiceLost() {
    gc.recordLoss(run!);
    if (isDaily) recordDaily(now(), run!.totalScore);
    phase = Phase.summary;
    _drainToasts();
    notifyListeners();
  }

  void buy(gc.Offer offer) {
    final r = run!;
    if (r.coins < offer.cost) return;
    switch (offer.kind) {
      case 'utensil':
        if (r.utensils.length >= r.utensilSlots) return;
        r.utensils.add(gc.kUtensilById[offer.id]!);
      case 'festival':
        r.kitchenLevel++;
      case 'blend':
        r.blends.add(gc.kBlendById[offer.id]!);
    }
    r.coins -= offer.cost;
    offers!.remove(offer);
    _drainToasts();
    notifyListeners();
  }

  static const rerollCost = 2;

  void reroll() {
    final r = run!;
    if (r.coins < rerollCost) return;
    r.coins -= rerollCost;
    r.rerolls++;
    offers = gc.rollOffers(r);
    notifyListeners();
  }

  void sellUtensil(int index) {
    final r = run!;
    final u = r.utensils[index];
    r.coins += (u.cost / 2).floor();
    r.utensils.removeAt(index);
    notifyListeners();
  }

  void nextService() {
    gc.advance(run!);
    if (run!.status == 'won') {
      phase = Phase.victory;
    } else {
      phase = Phase.service;
      selected.clear();
      lastResult = null;
    }
    notifyListeners();
  }

  /// Where to return to when the Recipe Book closes — it's reachable from more than one screen.
  Phase _bookReturn = Phase.start;

  /// Whether How to Play has ever been shown. Persisted so it interrupts exactly once.
  bool get _seenHelp => _prefs?.getBool(_seenHelpKey) ?? false;

  void openHelp() {
    _bookReturn = phase == Phase.help ? _bookReturn : phase;
    phase = Phase.help;
    unawaited(_prefs?.setBool(_seenHelpKey, true) ?? Future<bool>.value(false));
    notifyListeners();
  }

  void closeHelp() {
    phase = _bookReturn;
    notifyListeners();
  }

  void openRecipeBook() {
    _bookReturn = phase;
    phase = Phase.recipeBook;
    notifyListeners();
  }

  void closeRecipeBook() {
    phase = _bookReturn;
    notifyListeners();
  }

  /// Post-victory: keep going into the Long Route. Targets compound per city and the run
  /// only ends when you miss one — this is the leaderboard endgame.
  void continueEndless() {
    final r = run!;
    r.status = 'playing';
    gc.startEndlessCity(r, r.endlessCity + 1);
    phase = Phase.service;
    selected.clear();
    lastResult = null;
    _drainToasts();
    notifyListeners();
  }

  void backToStart() {
    run = null;
    offers = null;
    lastResult = null;
    selected.clear();
    phase = Phase.start;
    notifyListeners();
  }

  void dismissToast() {
    if (toasts.isNotEmpty) {
      toasts.removeAt(0);
      notifyListeners();
    }
  }

  void _drainToasts() => toasts.addAll(gc.drainUnlockQueue());
}

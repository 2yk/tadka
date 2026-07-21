/// Run persistence through the controller.
///
/// The reported symptom was "it resets when I come back". The cause was that a run existed
/// only in memory: a 24-service route is half an hour, phones background apps, and the OS
/// reclaims them without warning. These tests pin the fix at the layer the player feels it —
/// close the app mid-run, reopen, still there.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tadka_mobile/game_controller.dart';

/// A fresh controller over the SAME preferences — i.e. the app relaunching.
Future<GameController> _relaunch() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return GameController(prefs);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
  });

  test('a run in progress survives a relaunch', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = GameController(prefs)..startRun('KEEP-ME');
    c.run!.coins = 37;
    c.run!.kitchenLevel = 5;
    c.cook();
    final beforeHand = c.run!.hand.map((x) => x.id).toList();
    final beforeCoins = c.run!.coins;
    await c.flush();

    final fresh = await _relaunch();
    final saved = fresh.loadSavedRun();
    expect(saved, isNotNull, reason: 'the run must outlive the process');
    fresh.resumeRun(saved!);

    expect(fresh.phase, Phase.service, reason: 'resume lands in the game, not the menu');
    expect(fresh.run!.seed, 'KEEP-ME');
    expect(fresh.run!.coins, beforeCoins);
    expect(fresh.run!.kitchenLevel, 5);
    expect(fresh.run!.hand.map((x) => x.id).toList(), beforeHand);
  });

  test('the resumed run keeps dealing the same cards', () async {
    final prefs = await SharedPreferences.getInstance();
    final live = GameController(prefs)..startRun('DET-CHECK');
    live.toggleCard(0);
    live.cook();
    await live.flush();

    final fresh = await _relaunch();
    fresh.resumeRun(fresh.loadSavedRun()!);

    for (var i = 0; i < 5; i++) {
      live
        ..selected.clear()
        ..toggleCard(0)
        ..swap();
      fresh
        ..selected.clear()
        ..toggleCard(0)
        ..swap();
      expect(
        fresh.run!.hand.map((x) => x.id).toList(),
        live.run!.hand.map((x) => x.id).toList(),
        reason: 'draw $i diverged — a resumed run must not become a different game',
      );
    }
  });

  test('a finished run is not offered for resume', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = GameController(prefs)..startRun('DONE');
    c.run!.status = 'lost';
    c.afterServiceLost();
    await c.flush();

    final fresh = await _relaunch();
    expect(fresh.loadSavedRun(), isNull,
        reason: 'offering to resume a run that already ended would be nonsense');
  });

  test('a corrupt save never takes the app down on launch', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tadka_run_v1', '{not valid json at all');
    final fresh = await _relaunch();
    expect(fresh.loadSavedRun(), isNull);
  });

  test('a save from an incompatible build is declined', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tadka_run_v1', '{"v": 999, "seed": "X"}');
    final fresh = await _relaunch();
    expect(fresh.loadSavedRun(), isNull);
  });

  test('starting a new run replaces the saved one', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = GameController(prefs)..startRun('FIRST');
    await c.flush();
    c.startRun('SECOND');
    await c.flush();

    final fresh = await _relaunch();
    expect(fresh.loadSavedRun()!.seed, 'SECOND');
  });

  test('a Daily run resumes as a Daily, so it still records', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = GameController(prefs)..now = () => DateTime(2026, 7, 20);
    c.startDaily();
    await c.flush();

    final fresh = await _relaunch();
    fresh.resumeRun(fresh.loadSavedRun()!);
    expect(fresh.isDaily, isTrue,
        reason: 'losing the daily flag would silently drop the streak the run was for');
  });

  test('unlocks survive a relaunch', () async {
    final prefs = await SharedPreferences.getInstance();
    gc.profileStore = PrefsProfileStore(prefs);
    gc.reloadProfile();
    gc.unlockThing('utensil', 'clay_handi');

    // A new store over the same prefs is what the next launch actually does.
    gc.profileStore = PrefsProfileStore(await SharedPreferences.getInstance());
    gc.reloadProfile();
    expect(gc.isUnlocked('utensil', 'clay_handi'), isTrue,
        reason: 'death never takes unlocks away — nor should closing the app');
  });
}

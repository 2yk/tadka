/// Daily Route.
///
/// The mode's whole value is that everyone gets the same run, so the seed must be a pure
/// function of the date and the settings must be fixed. The streak rules are the other half —
/// a streak that survives a missed day isn't a streak.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:tadka_mobile/daily.dart';
import 'package:tadka_mobile/game_controller.dart';
import 'package:tadka_mobile/screens/start_screen.dart';
import 'package:tadka_mobile/theme.dart';

void main() {
  setUp(() {
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
  });

  group('seed', () {
    test('is a pure function of the calendar date', () {
      final morning = DateTime(2026, 7, 20, 6, 30);
      final night = DateTime(2026, 7, 20, 23, 59);
      expect(dailySeed(morning), dailySeed(night),
          reason: 'the puzzle must not change during the day');
      expect(dailySeed(morning), 'DAILY-20260720');
    });

    test('differs across days', () {
      expect(dailySeed(DateTime(2026, 7, 20)), isNot(dailySeed(DateTime(2026, 7, 21))));
    });

    test('produces an identical run for the same day — the point of the mode', () {
      final a = gc.newRun(seed: dailySeed(DateTime(2026, 7, 20)), stake: kDailyStake, deckId: kDailyDeck);
      final b = gc.newRun(seed: dailySeed(DateTime(2026, 7, 20)), stake: kDailyStake, deckId: kDailyDeck);
      expect(a.hand.map((c) => c.id).toList(), b.hand.map((c) => c.id).toList());
      expect(a.route.map((c) => c.id).toList(), b.route.map((c) => c.id).toList());
      expect(a.target, b.target);
    });
  });

  group('streak', () {
    test('starts at 1 on a first ever play', () {
      recordDaily(DateTime(2026, 7, 20), 5000);
      expect(gc.profile.daily.streak, 1);
      expect(gc.profile.daily.bestDailyScore, 5000);
    });

    test('advances on consecutive days', () {
      recordDaily(DateTime(2026, 7, 20), 100);
      recordDaily(DateTime(2026, 7, 21), 100);
      recordDaily(DateTime(2026, 7, 22), 100);
      expect(gc.profile.daily.streak, 3);
    });

    test('resets after a missed day — a streak that survives a gap is not a streak', () {
      recordDaily(DateTime(2026, 7, 20), 100);
      recordDaily(DateTime(2026, 7, 22), 100);
      expect(gc.profile.daily.streak, 1);
    });

    test('replaying the same day does not double-count', () {
      recordDaily(DateTime(2026, 7, 20), 100);
      recordDaily(DateTime(2026, 7, 20), 100);
      expect(gc.profile.daily.streak, 1);
    });

    test('a replay still raises the best score', () {
      recordDaily(DateTime(2026, 7, 20), 100);
      recordDaily(DateTime(2026, 7, 20), 900);
      expect(gc.profile.daily.bestDailyScore, 900);
      expect(gc.profile.daily.streak, 1, reason: 'a better replay is not another day');
    });

    test('a worse replay never lowers the best score', () {
      recordDaily(DateTime(2026, 7, 20), 900);
      recordDaily(DateTime(2026, 7, 20), 10);
      expect(gc.profile.daily.bestDailyScore, 900);
    });
  });

  group('controller', () {
    test('starts on fixed settings so scores stay comparable', () {
      final c = GameController()..now = () => DateTime(2026, 7, 20);
      c
        ..deckId = 'royal'
        ..stake = 6
        ..startDaily();
      expect(c.deckId, kDailyDeck);
      expect(c.stake, kDailyStake);
      expect(c.run!.seed, 'DAILY-20260720');
      expect(c.isDaily, isTrue);
    });

    test('a normal run clears the daily flag', () {
      final c = GameController()..now = () => DateTime(2026, 7, 20);
      c.startDaily();
      c.startRun('SPICE-ABCDE');
      expect(c.isDaily, isFalse, reason: 'a normal run must not record a daily result');
    });

    test('status reports whether today is done', () {
      final c = GameController()..now = () => DateTime(2026, 7, 20);
      expect(c.daily.playedToday, isFalse);
      recordDaily(DateTime(2026, 7, 20), 1);
      expect(c.daily.playedToday, isTrue);
    });
  });

  testWidgets('the start screen offers it, with the streak visible', (tester) async {
    const dpr = 3.0;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = const Size(390 * dpr, 844 * dpr);
    addTearDown(tester.view.reset);

    recordDaily(DateTime(2026, 7, 19), 4242);
    final c = GameController()..now = () => DateTime(2026, 7, 20);
    await tester.pumpWidget(MaterialApp(
      theme: T.theme(),
      home: Scaffold(body: StartScreen(controller: c)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('DAILY ROUTE'), findsOneWidget);
    expect(find.text('🔥 1'), findsOneWidget);
    expect(find.textContaining('4,242'), findsOneWidget);
  });
}

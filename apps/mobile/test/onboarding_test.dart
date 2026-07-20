/// Onboarding and Endless entry.
///
/// The rules must interrupt exactly once — never showing them strands a new player, showing
/// them every run is an insult. That "exactly once" is the whole contract, so it's asserted
/// rather than trusted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tadka_mobile/game_controller.dart';
import 'package:tadka_mobile/screens/help_sheet.dart';
import 'package:tadka_mobile/theme.dart';

Widget _wrap(Widget child) => MaterialApp(theme: T.theme(), home: child);

void main() {
  setUp(() {
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
    SharedPreferences.setMockInitialValues({});
  });

  group('How to Play', () {
    testWidgets('leads with flavor x heat, because nothing else parses without it',
        (tester) async {
      await tester.pumpWidget(_wrap(HelpSheet(onClose: () {})));
      expect(find.text('SCORE ='), findsOneWidget);
      expect(find.text('FLAVOR'), findsOneWidget);
      expect(find.text('HEAT'), findsOneWidget);
    });

    testWidgets('recipe numbers come from the engine, so they cannot drift', (tester) async {
      await tester.pumpWidget(_wrap(HelpSheet(onClose: () {})));
      // Straight Flush is 100 flavor x 8 heat in kRecipe.
      final base = gc.kRecipe['straight_flush']!;
      expect(find.text('${base.$1} flavor × ${base.$2} heat'), findsOneWidget);
    });

    testWidgets('does not name the secret recipes', (tester) async {
      await tester.pumpWidget(_wrap(HelpSheet(onClose: () {})));
      for (final p in gc.kSecretPatterns) {
        expect(find.text(gc.kGenericNames[p]!), findsNothing,
            reason: '$p must stay a discovery');
      }
    });

    testWidgets('close fires', (tester) async {
      var closed = 0;
      await tester.pumpWidget(_wrap(HelpSheet(onClose: () => closed++)));
      await tester.tap(find.text('GOT IT'));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });
  });

  group('first-run interruption', () {
    testWidgets('a first-ever run opens the rules before the first hand', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final c = GameController(prefs)..startRun('FIRST');
      expect(c.phase, Phase.help, reason: 'new players must meet the rules first');
    });

    testWidgets('closing the rules lands you in the service, not back at the menu',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final c = GameController(prefs)..startRun('FIRST');
      c.closeHelp();
      expect(c.phase, Phase.service);
      expect(c.run, isNotNull);
    });

    testWidgets('a second run does not interrupt again', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final c = GameController(prefs)..startRun('FIRST');
      c.closeHelp();
      c.startRun('SECOND');
      expect(c.phase, Phase.service, reason: 'the rules interrupt exactly once, ever');
    });

    testWidgets('a returning player is never interrupted', (tester) async {
      SharedPreferences.setMockInitialValues({'tadka_seen_help': true});
      final prefs = await SharedPreferences.getInstance();
      final c = GameController(prefs)..startRun('RETURNING');
      expect(c.phase, Phase.service);
    });
  });

  group('Endless', () {
    testWidgets('continuing after victory starts the Long Route', (tester) async {
      final c = GameController()..startRun('WIN');
      final run = c.run!;
      run.status = 'won';
      c.phase = Phase.victory;

      c.continueEndless();

      expect(c.phase, Phase.service);
      expect(run.endless, isTrue);
      expect(run.endlessCity, 1);
      expect(run.status, 'playing');
      expect(run.target, greaterThan(gc.kCities.last.targets.last),
          reason: 'the Long Route must escalate past the finale');
    });
  });
}

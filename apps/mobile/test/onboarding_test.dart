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
  final showAllDefault = gc.kShowAllContent;

  setUp(() {
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
    gc.kShowAllContent = showAllDefault;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => gc.kShowAllContent = showAllDefault);

  /// Drives the sheet until [finder] resolves — it is a long scroller and lazily built, so
  /// anything below the fold is genuinely absent from the tree until scrolled to.
  ///
  /// Rewinds to the top first, because `scrollUntilVisible` only ever drags one way: without
  /// this, checking for something that sits *above* the last thing checked scrolls off the
  /// bottom for fifty iterations and then fails on a heading that is plainly there.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, 20000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 150, scrollable: scrollable);
    await tester.pumpAndSettle();
  }

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

    testWidgets('a gated build does not name the secret recipes', (tester) async {
      gc.kShowAllContent = false;
      await tester.pumpWidget(_wrap(HelpSheet(onClose: () {})));
      // The sheet is a lazy scroller, so walk the whole thing rather than trusting the fold.
      await scrollTo(tester, find.text('GOT IT'));
      for (final p in gc.kSecretPatterns) {
        expect(find.text(gc.kGenericNames[p]!), findsNothing,
            reason: '$p must stay a discovery');
      }
    });

    testWidgets('an internal build names the secret recipes and how to reach them',
        (tester) async {
      await tester.pumpWidget(_wrap(HelpSheet(onClose: () {})));
      for (final p in gc.kSecretPatterns) {
        await scrollTo(tester, find.text(gc.kGenericNames[p]!));
        expect(find.text(gc.kGenericNames[p]!), findsOneWidget);
      }
    });

    // Blends are the least discoverable system in the game, and the Help listed none of them.
    // Generated from the catalog, so a twenty-first blend documents itself.
    testWidgets('lists every blend, by name, from the catalog', (tester) async {
      await tester.pumpWidget(_wrap(HelpSheet(onClose: () {})));
      expect(gc.kBlends, isNotEmpty);
      for (final b in gc.kBlends) {
        await scrollTo(tester, find.text(b.name));
        expect(find.text(b.name), findsOneWidget, reason: '${b.id} is undocumented');
      }
    });

    // Everything the owner reported as missing from the rules, asserted by its heading so a
    // future edit cannot quietly drop one.
    testWidgets('covers the systems a player has to be told about', (tester) async {
      await tester.pumpWidget(_wrap(HelpSheet(onClose: () {})));
      for (final heading in [
        'INGREDIENTS',
        'BLENDS ⚗️',
        'THE BAZAAR 🪙',
        'PANTRY DECKS',
        '📅 DAILY ROUTE',
        '♾️ THE LONG ROUTE',
        '📖 RECIPE BOOK',
        '🧠 COACH',
      ]) {
        await scrollTo(tester, find.text(heading));
        expect(find.text(heading), findsOneWidget, reason: '$heading is missing from Help');
      }
      // Two generated tables carry their own counts, so the heading proves the source.
      await scrollTo(tester, find.text('EVERY BLEND (${gc.kBlends.length})'));
      expect(find.text('EVERY BLEND (${gc.kBlends.length})'), findsOneWidget);
      await scrollTo(tester, find.text('STAKES — ${gc.kStakes.length} RUNGS OF HEAT'));
      expect(find.text('STAKES — ${gc.kStakes.length} RUNGS OF HEAT'), findsOneWidget);
    });

    // The stake table quotes StakeModifier.describe, and the deck table quotes Deck.identity —
    // both engine data. If either is ever retyped by hand, this fails.
    testWidgets('stake and deck copy is read out of the catalog, not restated', (tester) async {
      await tester.pumpWidget(_wrap(HelpSheet(onClose: () {})));
      final ghost = gc.kStakeById[7]!;
      await scrollTo(tester, find.text('${ghost.id}  ${ghost.name}'));
      expect(
        find.text(ghost.modifiers.map((m) => m.describe()).join(' · ')),
        findsOneWidget,
      );
      final royal = gc.kDeckById['royal']!;
      await scrollTo(tester, find.text(royal.identity));
      expect(find.text(royal.identity), findsOneWidget);
    });

    // The sheet roughly tripled in length and grew four generated tables. Rendered at the
    // default 800x600 test surface, a row that overflows a phone passes silently — and this
    // project has shipped layout bugs past unit tests before.
    testWidgets('lays out on a phone without overflowing', (tester) async {
      const dpr = 3.0;
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = const Size(390 * dpr, 844 * dpr);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(HelpSheet(onClose: () {})));
      await tester.pumpAndSettle();
      // Walk the whole sheet: overflow is thrown at paint, so an unvisited row is unchecked.
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 60; i++) {
        await tester.drag(scrollable, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.text('GOT IT'), findsOneWidget, reason: 'the sheet never reached its end');
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

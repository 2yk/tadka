/// Recipe Book tests.
///
/// The Book's job is to make the collection legible, and its one hard rule is that secret
/// recipes stay masked until played — spoiling them removes the discovery. That's asserted
/// here rather than trusted, because it's a one-character mistake to invert.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:tadka_mobile/screens/recipe_book_screen.dart';
import 'package:tadka_mobile/theme.dart';

Widget _wrap(Widget child) => MaterialApp(theme: T.theme(), home: child);

/// The Book's lists are lazy, so anything below the fold isn't built until scrolled to —
/// exactly as a player would have to scroll. Drives the list until [finder] resolves.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // Each test drives the meta-save directly, so start from a known-fresh profile.
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
  });

  testWidgets('opens on Recipes and offers all four sections', (tester) async {
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
    expect(find.text('📖 RECIPE BOOK'), findsOneWidget);
    for (final tab in ['RECIPES', 'UTENSILS', 'DECKS', 'STAKES']) {
      expect(find.text(tab), findsOneWidget);
    }
  });

  testWidgets('secret recipes are masked until discovered', (tester) async {
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));

    // Perfect Palate is secret and undiscovered on a fresh profile.
    expect(find.text('Perfect Palate'), findsNothing);
    expect(find.text('? ? ?'), findsWidgets);
    // Non-secret recipes are always named — they're the ladder you climb.
    expect(find.text('Straight Flush'), findsOneWidget);
    await _scrollTo(tester, find.text('Pair'));
    expect(find.text('Pair'), findsOneWidget);
  });

  testWidgets('a discovered secret recipe reveals its real name', (tester) async {
    gc.recordRecipe('perfect_palate');
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
    expect(find.text('Perfect Palate'), findsOneWidget);
  });

  testWidgets('locked utensils are hidden behind ??? and unlocked ones name themselves',
      (tester) async {
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
    await tester.tap(find.text('UTENSILS'));
    await tester.pumpAndSettle();

    // Iron Tawa is a starter utensil — available from the first run.
    expect(find.text('Iron Tawa'), findsOneWidget);

    // Sanity-check the fixture itself: this test is meaningless if the catalog ever ships
    // fully unlocked, and with 65 utensils it's no longer obvious by eye.
    final locked = gc.kUtensils.where((u) => !gc.isUnlocked('utensil', u.id)).toList();
    expect(locked, isNotEmpty, reason: 'nothing is gated — the ladder has nothing to give');

    // A locked entry must appear as a silhouette somewhere in the list. Scrolled to rather
    // than assumed on-screen: the list is long and lazily built, so a fixed drag distance
    // just tests where the scroll happened to land.
    await _scrollTo(tester, find.text('???'));
    expect(find.text('???'), findsWidgets);

    // Clay Handi is achievement-gated, so it must never be NAMED on a fresh profile.
    expect(find.text('Clay Handi'), findsNothing);
  });

  testWidgets('unlocking a utensil surfaces it in the book', (tester) async {
    gc.unlockThing('utensil', 'clay_handi');
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
    await tester.tap(find.text('UTENSILS'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Clay Handi'));
    expect(find.text('Clay Handi'), findsOneWidget);
  });

  testWidgets('the stake grid shows every deck as a row of eight', (tester) async {
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
    await tester.tap(find.text('STAKES'));
    await tester.pumpAndSettle();
    expect(find.text('Home Kitchen'), findsOneWidget);
    // stake 1 is always available, so cells 2..8 render as numbers on a fresh profile
    expect(find.text('8'), findsWidgets);
  });

  testWidgets('close fires the callback', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () => closed++)));
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(closed, 1);
  });
}

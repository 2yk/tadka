/// Recipe Book tests.
///
/// The Book's job is to make the collection legible. In a discovery-gated build its one hard
/// rule is that secret recipes stay masked until played — spoiling them removes the discovery —
/// and that is asserted here rather than trusted, because it's a one-character mistake to
/// invert.
///
/// `gc.kShowAllContent` is the internal-testing switch and ships **on**, which inverts every
/// one of those rules on purpose: an internal tester is here to see the content, not to
/// discover it. So the gated tests pin the flag off, and the group at the bottom asserts what
/// the flag does when it is on. Both positions are covered, because both ship.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:tadka_mobile/screens/recipe_book_screen.dart';
import 'package:tadka_mobile/theme.dart';

Widget _wrap(Widget child) => MaterialApp(theme: T.theme(), home: child);

/// The Book's lists are lazy, so anything below the fold isn't built until scrolled to —
/// exactly as a player would have to scroll. Drives the list until [finder] resolves.
///
/// Rewinds to the top first: `scrollUntilVisible` only drags one way, so looking for something
/// above the last thing found would otherwise scroll off the bottom and fail on a row that is
/// plainly in the list.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).last;
  await tester.drag(scrollable, const Offset(0, 20000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
  await tester.pumpAndSettle();
}

void main() {
  final showAllDefault = gc.kShowAllContent;

  setUp(() {
    // Each test drives the meta-save directly, so start from a known-fresh profile.
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
    gc.kShowAllContent = showAllDefault;
  });
  tearDown(() => gc.kShowAllContent = showAllDefault);

  /// Pins the discovery-gated build for one test.
  void gated() => gc.kShowAllContent = false;

  testWidgets('opens on Recipes and offers all four sections', (tester) async {
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
    expect(find.text('📖 RECIPE BOOK'), findsOneWidget);
    for (final tab in ['RECIPES', 'UTENSILS', 'DECKS', 'STAKES']) {
      expect(find.text(tab), findsOneWidget);
    }
  });

  testWidgets('secret recipes are masked until discovered', (tester) async {
    gated();
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
    gated();
    gc.recordRecipe('perfect_palate');
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
    expect(find.text('Perfect Palate'), findsOneWidget);
  });

  testWidgets('locked utensils are hidden behind ??? and unlocked ones name themselves',
      (tester) async {
    gated();
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
    gated();
    gc.unlockThing('utensil', 'clay_handi');
    await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
    await tester.tap(find.text('UTENSILS'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Clay Handi'));
    expect(find.text('Clay Handi'), findsOneWidget);
  });

  testWidgets('the stake grid shows every deck as a row of eight', (tester) async {
    gated();
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

  // The internal-testing build. These are the four things the owner could not see, asserted
  // from the screen rather than from the flag: if any of them regresses, a tester spends days
  // looking at a fraction of the content they paid for.
  group('with kShowAllContent on', () {
    testWidgets('every secret recipe is named on a fresh profile', (tester) async {
      await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
      expect(find.text('? ? ?'), findsNothing);
      for (final p in gc.kSecretPatterns) {
        await _scrollTo(tester, find.text(gc.kGenericNames[p]!));
        expect(find.text(gc.kGenericNames[p]!), findsOneWidget, reason: '$p is still masked');
      }
    });

    testWidgets('no utensil is a silhouette', (tester) async {
      await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
      await tester.tap(find.text('UTENSILS'));
      await tester.pumpAndSettle();
      expect(
        gc.kUtensils.where((u) => !gc.isUnlocked('utensil', u.id)),
        isEmpty,
        reason: 'every one of the ${gc.kUtensils.length} utensils must be reachable',
      );
      // Clay Handi is achievement-gated and is the one the gated test asserts is hidden.
      await _scrollTo(tester, find.text('Clay Handi'));
      expect(find.text('Clay Handi'), findsOneWidget);
    });

    testWidgets('every deck is named and every stake is open', (tester) async {
      await tester.pumpWidget(_wrap(RecipeBookScreen(onClose: () {})));
      await tester.tap(find.text('DECKS'));
      await tester.pumpAndSettle();
      for (final d in gc.kDecks.where((d) => !d.reserved)) {
        expect(find.text(d.name), findsOneWidget, reason: '${d.id} is locked');
      }
      expect(find.text('???'), findsNothing);
      for (final d in gc.kDecks.where((d) => !d.reserved)) {
        expect(gc.maxStake(d.id), gc.kStakes.length, reason: '${d.id} stake ladder is closed');
      }
    });
  });
}

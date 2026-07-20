/// Widget tests for the presentation layer.
///
/// These deliberately assert on what the player can see rather than internals — a card that
/// renders the wrong rank or silently drops the debuff marker is a real bug, and neither is
/// caught by the engine's differential tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:tadka_mobile/theme.dart';
import 'package:tadka_mobile/widgets/ingredient_card.dart';
import 'package:tadka_mobile/widgets/juice.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: T.theme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('IngredientCard', () {
    const card = gc.Card(id: 'spicy_7', family: 'spicy', rank: 7, display: "Bird's Eye Chili");

    testWidgets('shows rank, family and name', (tester) async {
      await tester.pumpWidget(_wrap(const IngredientCard(card: card)));
      expect(find.text('7'), findsOneWidget);
      expect(find.text('SPICY'), findsOneWidget);
      expect(find.text("Bird's Eye Chili"), findsOneWidget);
    });

    testWidgets('selection is visible and does not change the data shown', (tester) async {
      await tester.pumpWidget(_wrap(const IngredientCard(card: card, selected: true)));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
      expect(find.byType(IngredientCard), findsOneWidget);
    });

    testWidgets('debuffed cards are marked, so the critic penalty is visible on the card',
        (tester) async {
      await tester.pumpWidget(_wrap(const IngredientCard(card: card, debuffed: true)));
      expect(find.text('DEBUFFED'), findsOneWidget);
    });

    testWidgets('tap fires only when a handler is attached', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(IngredientCard(card: card, onTap: () => taps++)));
      await tester.tap(find.byType(IngredientCard));
      expect(taps, 1);

      await tester.pumpWidget(_wrap(const IngredientCard(card: card)));
      await tester.tap(find.byType(IngredientCard));
      expect(taps, 1, reason: 'disabled cards must not be tappable mid-animation');
    });
  });

  group('score formatting', () {
    test('stays readable as runs reach Endless magnitudes', () {
      expect(formatScore(0), '0');
      expect(formatScore(999), '999');
      expect(formatScore(1200), '1,200');
      expect(formatScore(999999), '999,999');
      expect(formatScore(1200000), '1.20M');
      expect(formatScore(34500000000), '34.5B');
      // Past 1e15 it must not render a 16-digit number into a phone-width layout.
      expect(formatScore(1e16), contains('e+'));
    });
  });

  group('shake magnitude', () {
    test('scales with the multiplier and caps at 8px per the motion spec', () {
      expect(Motion.shakePixels(2), 3.0);
      expect(Motion.shakePixels(3), 4.0);
      expect(Motion.shakePixels(7), 8.0);
      expect(Motion.shakePixels(40), 8.0, reason: 'cap must hold for absurd multipliers');
    });
  });

  testWidgets('CountUpScore eases to its target rather than snapping', (tester) async {
    var value = 0;
    late StateSetter setSt;
    await tester.pumpWidget(_wrap(
      StatefulBuilder(builder: (context, set) {
        setSt = set;
        return CountUpScore(value: value, size: 30);
      }),
    ));
    expect(find.text('0'), findsOneWidget);

    setSt(() => value = 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final mid = tester.widget<Text>(find.byType(Text)).data!;
    expect(mid, isNot('1,000'), reason: 'should still be counting up, not snapped');

    await tester.pumpAndSettle();
    expect(find.text('1,000'), findsOneWidget);
  });
}

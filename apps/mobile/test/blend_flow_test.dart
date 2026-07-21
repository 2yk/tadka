/// End-to-end blend flow through the real service screen.
///
/// Blends were a dead-end purchase for the whole M1 port — buyable, never usable — so this
/// drives the actual UI rather than the engine: chip renders, arms only when it has targets,
/// consumes on use, and genuinely mutates the hand.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:tadka_mobile/game_controller.dart';
import 'package:tadka_mobile/screens/service_screen.dart';
import 'package:tadka_mobile/theme.dart';
import 'package:tadka_mobile/widgets/ingredient_card.dart';
import 'package:tadka_mobile/widgets/juice.dart';

/// iPhone 14 / mid-range Android portrait, in logical pixels.
const _phone = Size(390, 844);

/// Pins a real phone viewport. Flutter's default test surface is 800x600 — landscape-ish,
/// and a shape this portrait-locked game can never run at, so layout assertions against it
/// are meaningless. physicalSize is in device pixels, hence the dpr multiply.
Future<void> _pumpPhone(WidgetTester tester, Widget app) async {
  const dpr = 3.0;
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(_phone.width * dpr, _phone.height * dpr);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Widget _wrap(GameController c) => MaterialApp(
  theme: T.theme(),
  home: Scaffold(
    body: ServiceScreen(
      controller: c,
      particles: ParticleController(),
      shake: ShakeController(),
    ),
  ),
);

GameController _controllerWithBlend(String blendId) {
  final c = GameController();
  c.deckId = 'coastal';
  c.startRun('BLEND-TEST');
  // Exactly one blend in the rack. Every deck now opens with one or two so the mechanic is
  // discoverable, and the rack is a horizontal scroller — so leaving the deck's own blends in
  // puts the chip under test off the right edge of a 390pt phone, where `tap()` lands on
  // whichever chip is actually at those coordinates. Each test drives one blend.
  c.run!.blends
    ..clear()
    ..add(gc.kBlendById[blendId]!);
  return c;
}

void main() {
  setUp(() {
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
  });

  testWidgets('a blend in inventory shows a chip stating what it needs', (tester) async {
    final c = _controllerWithBlend('sun_dry');
    await _pumpPhone(tester, _wrap(c));

    expect(find.text('Sun-Dry'), findsOneWidget);
    expect(find.text('tap 1 card'), findsWidgets);
  });

  testWidgets('Mise en Place needs no target and says so', (tester) async {
    final c = _controllerWithBlend('mise');
    await _pumpPhone(tester, _wrap(c));
    expect(find.text('Mise en Place'), findsOneWidget);
    expect(find.text('tap to use'), findsWidgets);
  });

  testWidgets('using a blend with no selection is refused and consumes nothing',
      (tester) async {
    final c = _controllerWithBlend('sun_dry');
    final before = c.run!.blends.length;
    await _pumpPhone(tester, _wrap(c));

    await tester.tap(find.text('Sun-Dry'));
    await tester.pumpAndSettle();

    expect(c.run!.blends.length, before, reason: 'a refused blend must not be spent');
    expect(find.textContaining('Select ingredient'), findsOneWidget);
  });

  testWidgets('Sun-Dry duplicates the chosen card and is consumed', (tester) async {
    final c = _controllerWithBlend('sun_dry');
    await _pumpPhone(tester, _wrap(c));

    final handBefore = c.run!.hand.length;
    final blendsBefore = c.run!.blends.length;
    final target = c.run!.hand.first;

    await tester.tap(find.byType(IngredientCard).first);
    await tester.pumpAndSettle();
    expect(c.selected, isNotEmpty, reason: 'card tap should select');

    await tester.tap(find.text('Sun-Dry'));
    await tester.pumpAndSettle();

    expect(c.run!.hand.length, handBefore + 1, reason: 'Sun-Dry adds a copy');
    expect(c.run!.blends.length, blendsBefore - 1, reason: 'the blend is spent');
    expect(c.selected, isEmpty, reason: 'selection clears after use');
    expect(
      c.run!.hand.where((x) => x.rank == target.rank && x.family == target.family).length,
      greaterThanOrEqualTo(2),
      reason: 'the duplicate must match the card it copied',
    );
  });

  testWidgets('Chili Oil converts the chosen card to Spicy', (tester) async {
    final c = _controllerWithBlend('chili_oil');
    await _pumpPhone(tester, _wrap(c));

    // pick a card that isn't already Spicy, so the conversion is observable
    final idx = c.run!.hand.indexWhere((x) => x.family != 'spicy');
    expect(idx, isNot(-1));
    c.toggleCard(idx);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chili Oil'));
    await tester.pumpAndSettle();

    expect(c.run!.hand[idx].family, 'spicy');
    expect(c.run!.hand[idx].display, startsWith('Chili '));
  });

  _sourcedBlendTests();

  testWidgets('no blends means no rack — the row costs nothing when empty', (tester) async {
    final c = GameController()..startRun('NO-BLENDS');
    c.run!.blends.clear();
    await _pumpPhone(tester, _wrap(c));
    expect(find.text('tap to use'), findsNothing);
    expect(find.text('Sun-Dry'), findsNothing);
  });
}

/// Source-based blends read the FIRST selected card and edit the rest to match it. Getting
/// that order backwards burns the blend, so the chip has to say which tap is which.
void _sourcedBlendTests() {
  testWidgets('a source-based blend says which tap is the source', (tester) async {
    final c = _controllerWithBlend('julienne');
    await _pumpPhone(tester, _wrap(c));
    expect(find.text('Julienne'), findsOneWidget);
    expect(find.textContaining('1st is source'), findsWidgets);
  });

  testWidgets('a plain multi-target blend does not claim a source', (tester) async {
    final c = _controllerWithBlend('chili_oil');
    await _pumpPhone(tester, _wrap(c));
    expect(find.text('Chili Oil'), findsOneWidget);
    expect(find.textContaining('1st is source'), findsNothing);
  });

  testWidgets('a two-card verb on one card is refused, not silently spent', (tester) async {
    final c = _controllerWithBlend('julienne');
    await _pumpPhone(tester, _wrap(c));
    final before = c.run!.blends.length;

    c.toggleCard(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Julienne'));
    await tester.pumpAndSettle();

    expect(c.run!.blends.length, before,
        reason: 'burning a blend for no effect is the worst failure this system has');
    expect(find.textContaining('source'), findsWidgets);
  });
}

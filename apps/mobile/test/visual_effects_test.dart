/// The effects layer: ambient gate, 3D tilt, foil, shockwave rings, the living background.
///
/// Two properties are load-bearing and easy to lose silently:
///
/// 1. Every ambient (endless) effect must be inert under `flutter test`, or every
///    pumpAndSettle in this suite hangs. The gate is asserted directly, and each effect is
///    mounted and settled — a regression re-hangs these tests, which is the point.
/// 2. The tilt must actually be 3D — a perspective entry plus real rotations. A refactor
///    that quietly drops the matrix leaves a flat game that still compiles.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:tadka_mobile/game_controller.dart';
import 'package:tadka_mobile/screens/service_screen.dart';
import 'package:tadka_mobile/theme.dart';
import 'package:tadka_mobile/widgets/ambient.dart';
import 'package:tadka_mobile/widgets/ingredient_card.dart';
import 'package:tadka_mobile/widgets/juice.dart';
import 'package:tadka_mobile/widgets/midnight_background.dart';
import 'package:tadka_mobile/widgets/tilt.dart';

const _phone = Size(390, 844);

Future<void> _pumpPhone(WidgetTester tester, Widget app) async {
  const dpr = 3.0;
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(_phone.width * dpr, _phone.height * dpr);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Widget _wrap(Widget child) => MaterialApp(
  theme: T.theme(),
  home: Scaffold(body: Center(child: child)),
);

/// The Transform a Tilt3D paints with — identified by its perspective entry, which nothing
/// else in these minimal trees sets.
Matrix4 _tiltMatrix(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(Tilt3D),
    matching: find.byWidgetPredicate((w) => w is Transform && w.transform.entry(3, 2) != 0),
  );
  expect(finder, findsOneWidget, reason: 'the tilt must keep its perspective transform');
  return tester.widget<Transform>(finder).transform.clone();
}

void main() {
  setUp(() {
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
  });

  test('ambient animation is gated OFF under flutter test', () {
    // Everything endless (sway, shimmer, shader sky, embers) runs through this gate. If it
    // opens under test, every pumpAndSettle in the suite stops settling.
    expect(debugAmbientOverride, isNull,
        reason: 'no test may leave the override set for the others');
  });

  testWidgets('the gate answers false in a test build context', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_wrap(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(ambientEnabled(ctx), isFalse);
  });

  group('Tilt3D', () {
    testWidgets('applies perspective, and settles at rest', (tester) async {
      await tester.pumpWidget(_wrap(
        Tilt3D(child: Container(width: 92, height: 129, color: T.parch)),
      ));
      await tester.pumpAndSettle();
      final m = _tiltMatrix(tester);
      expect(m.entry(3, 2), isNot(0), reason: 'no perspective means no 3D at all');
      // At rest in tests (sway gated off, nothing pressed) the rotations are zero.
      expect(m.entry(2, 1).abs() + m.entry(2, 0).abs(), lessThan(1e-6));
    });

    testWidgets('a press tilts the card toward the finger and it springs back on release',
        (tester) async {
      await tester.pumpWidget(_wrap(
        Tilt3D(child: Container(width: 92, height: 129, color: T.parch)),
      ));
      await tester.pumpAndSettle();

      final corner = tester.getTopLeft(find.byType(Tilt3D)) + const Offset(8, 8);
      final g = await tester.startGesture(corner);
      // Two pumps: a ticker's first frame is its elapsed-zero baseline; the second
      // actually advances the press animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final pressed = _tiltMatrix(tester);
      expect(pressed.entry(2, 1).abs() + pressed.entry(2, 0).abs(), greaterThan(0.01),
          reason: 'pressing a corner must rotate the card in 3D');

      await g.up();
      await tester.pumpAndSettle();
      final rest = _tiltMatrix(tester);
      expect(rest.entry(2, 1).abs() + rest.entry(2, 0).abs(), lessThan(1e-3),
          reason: 'the card must spring back flat after release');
    });
  });

  group('foil on prized cards', () {
    const plain = gc.Card(id: 'sweet_5', family: 'sweet', rank: 5, display: 'Honey');
    const prized =
        gc.Card(id: 'sweet_5', family: 'sweet', rank: 5, display: 'Honey', prized: true);

    testWidgets('a prized card shimmers; an ordinary one does not', (tester) async {
      await tester.pumpWidget(_wrap(const IngredientCard(card: prized)));
      await tester.pumpAndSettle();
      expect(find.byType(FoilShimmer), findsOneWidget);

      await tester.pumpWidget(_wrap(const IngredientCard(card: plain)));
      await tester.pumpAndSettle();
      expect(find.byType(FoilShimmer), findsNothing,
          reason: 'foil on everything is foil on nothing');
    });
  });

  group('shockwave rings', () {
    testWidgets('a ring paints, then expires and the layer cleans itself up', (tester) async {
      final particles = ParticleController();
      await tester.pumpWidget(_wrap(
        ParticleField(controller: particles, child: const SizedBox(width: 300, height: 300)),
      ));
      final layer = find.descendant(
        of: find.byType(ParticleField),
        matching: find.byType(CustomPaint),
      );
      expect(layer, findsNothing, reason: 'no effects, no paint layer');

      particles.ring(const Offset(150, 150), T.brass);
      await tester.pump();
      expect(layer, findsOneWidget);

      // The ticker must stop itself once the ring dies — this settle hanging is the
      // regression signal for an always-on ticker.
      await tester.pumpAndSettle();
      expect(layer, findsNothing);
    });

    testWidgets('reduced motion swallows rings entirely', (tester) async {
      final particles = ParticleController();
      await tester.pumpWidget(MaterialApp(
        theme: T.theme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: ParticleField(controller: particles, child: const SizedBox.expand()),
          ),
        ),
      ));
      particles.ring(const Offset(100, 100), T.brass);
      await tester.pump();
      expect(
        find.descendant(of: find.byType(ParticleField), matching: find.byType(CustomPaint)),
        findsNothing,
      );
    });
  });

  group('MidnightBackground', () {
    testWidgets('mounts its child over a background and settles', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: T.theme(),
        home: const MidnightBackground(child: Center(child: Text('over the sky'))),
      ));
      // First frame: the shader is still compiling (or unavailable), so the gradient
      // fallback must already be painting — the app never shows a void.
      expect(find.byKey(const ValueKey('midnight_fallback')), findsOneWidget);
      expect(find.text('over the sky'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('over the sky'), findsOneWidget);
    });
  });

  group('service screen integration', () {
    testWidgets('every hand card is wrapped in Tilt3D, prized cards get foil, and the '
        'screen still settles with all effects mounted', (tester) async {
      final c = GameController()..startRun('FX-TEST');
      c.run!.hand[0] = c.run!.hand[0].copyWith(prized: true);
      await _pumpPhone(
        tester,
        MaterialApp(
          theme: T.theme(),
          home: Scaffold(
            body: ServiceScreen(
              controller: c,
              particles: ParticleController(),
              shake: ShakeController(),
            ),
          ),
        ),
      );

      expect(find.byType(Tilt3D), findsNWidgets(c.run!.hand.length),
          reason: 'the whole hand tilts, or the one flat card looks broken');
      expect(find.byType(FoilShimmer), findsOneWidget);
    });
  });
}

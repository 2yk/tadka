/// The route strip must describe the run it's in, not a hardcoded route.
///
/// A run draws 8 cities from a pool of 12, so anything reading the global city list renders
/// the wrong journey — which is exactly what it did before the route expansion.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:tadka_mobile/game_controller.dart';
import 'package:tadka_mobile/screens/service_screen.dart';
import 'package:tadka_mobile/theme.dart';
import 'package:tadka_mobile/widgets/juice.dart';

Future<void> _pump(WidgetTester tester, GameController c) async {
  const dpr = 3.0;
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = const Size(390 * dpr, 844 * dpr);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: T.theme(),
    home: Scaffold(
      body: ServiceScreen(
        controller: c,
        particles: ParticleController(),
        shake: ShakeController(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
  });

  testWidgets('counts the run\'s own route, not the global city list', (tester) async {
    final c = GameController()..startRun('ROUTE-UI');
    final run = c.run!;
    expect(run.route.length, greaterThan(gc.kCities.length),
        reason: 'fixture assumes an expanded route');

    await _pump(tester, c);
    expect(find.text('CITY 1/${run.route.length}'), findsOneWidget);
  });

  testWidgets('advances as the run does', (tester) async {
    final c = GameController()..startRun('ROUTE-UI-2');
    final run = c.run!;
    run.cityIndex = 3;
    run.serviceIndex = 1;
    await _pump(tester, c);
    expect(find.text('CITY 4/${run.route.length}'), findsOneWidget);
  });
}

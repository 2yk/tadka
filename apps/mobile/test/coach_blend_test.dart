/// The Coach's blend advice, driven through the real service screen.
///
/// Blends are the least discoverable system in the game: they edit cards instead of scoring
/// them, they are the only route to the three secret recipes, and until now nothing on screen
/// said what one would do until you spent it. So the Coach now measures each blend in the rack
/// against the hand in front of you.
///
/// The rule it inherits is the one that makes the Coach worth having (CLAUDE.md): it drives the
/// live engine and must never state a number the game won't produce. The load-bearing test here
/// is `the number on the row is what applyBlend actually pays` — everything else is scaffolding
/// around it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:tadka_mobile/game_controller.dart';
import 'package:tadka_mobile/screens/service_screen.dart';
import 'package:tadka_mobile/theme.dart';
import 'package:tadka_mobile/widgets/coach_panel.dart';
import 'package:tadka_mobile/widgets/juice.dart';

const _phone = Size(390, 844);

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

gc.Card _card(String family, int rank) =>
    gc.Card(id: '${family}_$rank', family: family, rank: rank, display: '$rank $family');

/// A run with the Coach on, a named rack, and a hand that has an obvious blend play in it:
/// four 9s and a stray, where copying a 9 onto the stray reaches Five of a Kind — a recipe no
/// pantry can deal.
GameController _coached(List<String> blendIds, {List<gc.Card>? hand}) {
  final c = GameController()..startRun('COACH-BLEND');
  c.coachOn = true;
  c.run!
    // Copied, never aliased: a caller that passes another run's hand and then applies a blend
    // would otherwise mutate both, and the second assertion in a loop would measure a hand the
    // first one already edited.
    ..hand = List<gc.Card>.of(hand ??
        [
          _card('spicy', 9),
          _card('sweet', 9),
          _card('sour', 9),
          _card('salty', 9),
          _card('umami', 2),
        ])
    ..blends = [for (final id in blendIds) gc.kBlendById[id]!];
  return c;
}

/// Drives the Coach's own list until [finder] resolves. It is a short, lazily built panel, so
/// a row below the fold is genuinely absent from the tree — exactly as a player would scroll.
Future<void> _scrollCoach(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 60, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    gc.profileStore = gc.MemoryProfileStore();
    gc.reloadProfile();
  });

  testWidgets('names the blend and what it would do for this hand', (tester) async {
    final c = _coached(['julienne']);
    await _pumpPhone(tester, _wrap(c));

    expect(find.byType(BlendAdviceRow), findsOneWidget);
    // Two "Julienne" texts now: the rack chip and the Coach row.
    expect(find.text('Julienne'), findsNWidgets(2));
    expect(find.textContaining('Five of a Kind'), findsWidgets);
  });

  // THE anti-drift guarantee for this feature. The row promises a score; applying the blend
  // for real must produce a hand that pays exactly it.
  testWidgets('the number on the row is what applyBlend actually pays', (tester) async {
    final c = _coached(['julienne', 'sun_dry']);
    await _pumpPhone(tester, _wrap(c));

    final advice = gc.suggestBlends(c.run!).where((b) => b.result != null).toList();
    expect(advice, isNotEmpty, reason: 'the fixture hand must have a blend play in it');

    for (final a in advice) {
      expect(find.text(formatScore(a.result!.score)), findsWidgets,
          reason: '${a.blend.id}: the promised score is not on screen');

      // Replay it on a private run and cook the hand it builds.
      final replay = _coached(['julienne', 'sun_dry'], hand: c.run!.hand).run!;
      expect(gc.applyBlend(replay, a.blendIndex, a.handIndexes).error, isNull);
      final best = gc.suggestDishes(replay).first.result.score;
      expect(best, equals(a.result!.score),
          reason: '${a.blend.id}: the Coach promised ${a.result!.score}, the hand pays $best');
    }
  });

  testWidgets('tapping the advice loads exactly the cards it names', (tester) async {
    final c = _coached(['julienne']);
    await _pumpPhone(tester, _wrap(c));

    final advice = gc.suggestBlends(c.run!).single;
    expect(advice.handIndexes, isNotEmpty);

    await tester.tap(find.byType(BlendAdviceRow));
    await tester.pumpAndSettle();
    expect(c.selected, equals(advice.handIndexes),
        reason: 'the tap must arm the blend, in the order the advice named');
  });

  testWidgets('a blend that cannot help still explains itself', (tester) async {
    // Five Spicy 9s is already a Perfect Palate — nothing can improve it, and the row has to
    // teach the verb rather than vanish.
    final c = _coached(['chili_oil'], hand: [for (var i = 0; i < 5; i++) _card('spicy', 9)]);
    await _pumpPhone(tester, _wrap(c));
    expect(gc.suggestBlends(c.run!).single.result, isNull, reason: 'fixture must be unimprovable');
    // It files below the dish ladder rather than above it, so scroll the panel.
    await _scrollCoach(tester, find.byType(BlendAdviceRow));
    expect(find.byType(BlendAdviceRow), findsOneWidget);
    expect(find.textContaining('completes a Flush'), findsWidgets);
  });

  testWidgets('every deck opens with a rack, so the mechanic is never invisible',
      (tester) async {
    for (final d in gc.kDecks.where((d) => !d.reserved)) {
      final c = GameController()
        ..deckId = d.id
        ..coachOn = true;
      c.startRun('RACK-${d.id}');
      expect(c.run!.blends, isNotEmpty, reason: '${d.id} deals no blend');
      await _pumpPhone(tester, _wrap(c));
      // The rack chip states what the blend needs — that row only renders when one is held.
      expect(
        find.text(c.run!.blends.first.name),
        findsWidgets,
        reason: '${d.id}: the blend rack never rendered',
      );
    }
  });

  testWidgets('no rack means no blend rows', (tester) async {
    final c = _coached(const []);
    await _pumpPhone(tester, _wrap(c));
    expect(find.byType(BlendAdviceRow), findsNothing);
  });
}

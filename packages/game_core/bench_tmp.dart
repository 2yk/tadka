import 'package:game_core/game_core.dart';

void main() {
  final run = newRun(seed: 'BENCH-1');
  final ctx = ctxFor(run);
  final cards = run.hand.take(5).toList();
  // warm
  for (var i = 0; i < 1000; i++) { scoreDish(cards, ctx); }
  final sw = Stopwatch()..start();
  const n = 200000;
  for (var i = 0; i < n; i++) { scoreDish(cards, ctx); }
  sw.stop();
  print('scoreDish: ${sw.elapsedMicroseconds / n} us/call');

  final sw2 = Stopwatch()..start();
  for (var i = 0; i < 200; i++) { suggestDishes(run); }
  sw2.stop();
  print('suggestDishes: ${sw2.elapsedMicroseconds / 200} us/call');

  final sw3 = Stopwatch()..start();
  for (var i = 0; i < n; i++) { bestPattern(cards); }
  sw3.stop();
  print('bestPattern: ${sw3.elapsedMicroseconds / n} us/call');
}

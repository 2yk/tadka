// game_core is the headless rules engine. If Flutter (or Flame, or dart:ui)
// leaks in, the package stops being unit-testable and tools/sim stops being
// able to run the real engine — which is the whole reason the package exists.
// This test is the guard rail; it should outlive every other test here.

import 'dart:io';

import 'package:test/test.dart';

/// Import prefixes that must never appear anywhere under `lib/`.
const List<String> _forbiddenPrefixes = <String>[
  'package:flutter',
  'package:flame',
  'dart:ui',
];

/// Resolves `lib/` whether tests are run from the package root or the repo root.
Directory _libDirectory() {
  const List<String> candidates = <String>['lib', 'packages/game_core/lib'];
  for (final String candidate in candidates) {
    final Directory dir = Directory(candidate);
    if (dir.existsSync()) return dir;
  }
  throw StateError(
    'Could not locate game_core/lib from ${Directory.current.path}. '
    'Run `dart test` from packages/game_core or from the repo root.',
  );
}

void main() {
  test('game_core lib/ has zero Flutter, Flame or dart:ui imports', () {
    final Directory lib = _libDirectory();
    final List<String> violations = <String>[];

    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i].trim();
        if (!line.startsWith('import ') && !line.startsWith('export ')) continue;

        for (final String prefix in _forbiddenPrefixes) {
          if (line.contains("'$prefix") || line.contains('"$prefix')) {
            violations.add('${entity.path}:${i + 1}: $line');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'game_core must stay pure Dart (build spec §3). Offending directives:\n'
          '${violations.join('\n')}',
    );
  });
}

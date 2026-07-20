// The content loader and validator have to run under `dart test` and inside
// tools/sim, not just inside the app — so this package stays Flutter-free too.

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
  const List<String> candidates = <String>['lib', 'packages/content/lib'];
  for (final String candidate in candidates) {
    final Directory dir = Directory(candidate);
    if (dir.existsSync()) return dir;
  }
  throw StateError(
    'Could not locate content/lib from ${Directory.current.path}. '
    'Run `dart test` from packages/content or from the repo root.',
  );
}

void main() {
  test('content lib/ has zero Flutter, Flame or dart:ui imports', () {
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
          'content must stay pure Dart (build spec §3). Offending directives:\n'
          '${violations.join('\n')}',
    );
  });
}

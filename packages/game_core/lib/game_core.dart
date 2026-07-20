/// The pure-Dart rules engine for Project Tadka.
///
/// Hard constraint: this package must never import `package:flutter`,
/// `package:flame` or `dart:ui`. Everything here has to run headless so
/// `tools/sim` and the unit tests can exercise the real engine rather than a
/// parallel implementation that drifts (see CLAUDE.md). The constraint is
/// enforced by `test/no_flutter_imports_test.dart`.
///
/// Ported so far: §RNG, §CONTENT, §ENGINE. §PROGRESSION and §RUN land next.
/// The web build remains the behavioural reference — `test/vectors_test.dart`
/// asserts this port matches it case for case.
library;

export 'src/catalog.dart';
export 'src/engine.dart';
export 'src/models.dart';
export 'src/rng.dart';

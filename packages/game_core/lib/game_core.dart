/// The pure-Dart rules engine for Project Tadka.
///
/// Hard constraint: this package must never import `package:flutter`,
/// `package:flame` or `dart:ui`. Everything here has to run headless so
/// `tools/sim` and the unit tests can exercise the real engine rather than a
/// parallel implementation that drifts (see CLAUDE.md). The constraint is
/// enforced by `test/no_flutter_imports_test.dart`.
///
/// Ported: §RNG, §CONTENT, §ENGINE, §PROGRESSION, §RUN — the whole pure core —
/// plus the two pieces of game logic that live in §UI over there and have no
/// business in a view layer: the Coach's solver (`src/coach.dart`), which drives
/// that engine rather than shadowing it, and blend application
/// (`src/blends.dart`), without which a bought blend can never be played.
/// The web build remains the behavioural reference — `test/vectors_test.dart`
/// asserts scoring matches it case for case, and `test/runs_test.dart` replays
/// whole scripted runs against traces recorded from it.
///
/// The one thing the app must wire up: assign a real [ProfileStore] to
/// `profileStore` at startup, before the meta-save is first read. Left alone it
/// falls back to an in-memory store and unlocks vanish when the app closes.
library;

export 'src/blends.dart';
export 'src/catalog.dart';
export 'src/coach.dart';
export 'src/engine.dart';
export 'src/models.dart';
export 'src/progression.dart';
export 'src/rng.dart';
export 'src/run.dart';
export 'src/run_save.dart';

/// The pure-Dart rules engine for Project Tadka.
///
/// Hard constraint: this package must never import `package:flutter`,
/// `package:flame` or `dart:ui`. Everything here has to run headless so
/// `tools/sim` and the unit tests can exercise the real engine rather than a
/// parallel implementation that drifts (see CLAUDE.md). The constraint is
/// enforced by `test/no_flutter_imports_test.dart`.
///
/// Scaffold only — the ports of §RNG, §ENGINE, §PROGRESSION and §RUN from
/// `web/tadka.html` land here next.
library;

// Public API is exported from here as `src/` fills in.

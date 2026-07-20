/// The pure-Dart content layer for Project Tadka.
///
/// Owns the JSON tables (ingredients, utensils, blends, critics, palates, dish
/// names) plus the loader and the schema validator. The validator must reject
/// unknown condition/effect keys in the utensil effect DSL — that is what keeps
/// 100+ future utensils safe (build spec §5, CLAUDE.md).
///
/// No Flutter imports: the validator has to run under `dart test` and inside
/// `tools/sim`, not just in the app.
///
/// Scaffold only — the port of §CONTENT from `web/tadka.html` lands here next.
library;

// Public API is exported from here as `src/` fills in.

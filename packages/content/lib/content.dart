/// The pure-Dart content layer for Project Tadka.
///
/// Owns the JSON tables (ingredients, utensils, blends, critics, palates, dish
/// names) plus the loader and the schema validator. The validator must reject
/// unknown condition/effect keys in the utensil effect DSL — that is what keeps
/// 100+ future utensils safe (build spec §5, CLAUDE.md).
///
/// There are now **two** effect DSLs to validate, and they share no keys: the
/// utensil one scores a dish, the blend one edits cards. `game_core`'s
/// `blends.dart` documents the blend key set; `test/blends_test.dart` and
/// `test/utensils_test.dart` hold the two allow-lists that this validator has to
/// reproduce once the tables move to JSON.
///
/// No Flutter imports: the validator has to run under `dart test` and inside
/// `tools/sim`, not just in the app.
///
/// Scaffold only — the port of §CONTENT from `web/tadka.html` lands here next.
library;

// Public API is exported from here as `src/` fills in.

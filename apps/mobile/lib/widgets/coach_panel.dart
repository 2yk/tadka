/// The Coach — a solver overlay for players still learning the combos.
///
/// It never lies, because it drives the live engine: every row comes from `suggestDishes`,
/// which scores with the same `scoreDish` the COOK button will use. That property is the
/// whole point (CLAUDE.md calls it out) — a parallel solver that drifts is worse than none.
///
/// It occupies the stage area, which is otherwise empty while you're choosing. Tapping a row
/// loads exactly those cards, so the Coach teaches by letting you see the hand it would play
/// rather than by telling you a number you then have to reconstruct.
library;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../theme.dart';
import 'juice.dart';

class CoachPanel extends StatelessWidget {
  const CoachPanel({
    required this.run,
    required this.suggestions,
    required this.onLoad,
    required this.selected,
    super.key,
  });

  final gc.RunState run;
  final List<gc.DishSuggestion> suggestions;
  final void Function(List<int> handIndexes) onLoad;
  final List<int> selected;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return Center(
        child: Text(
          run.critic == null
              ? 'No legal dish in this hand.'
              : '${run.critic!.name} leaves no legal dish — swap.',
          textAlign: TextAlign.center,
          style: T.bodyDim,
        ),
      );
    }

    final cityId = gc.cityOf(run).id;
    final needed = run.target - run.score;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('🧠 COACH', style: T.label.copyWith(color: T.brass)),
            const Spacer(),
            Text(
              needed > 0 ? '${formatScore(needed)} to go' : 'target cleared',
              style: T.label.copyWith(color: needed > 0 ? T.dim : T.good),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: suggestions.length,
            itemBuilder: (context, i) {
              final s = suggestions[i];
              final isLoaded = _sameSelection(s.handIndexes, selected);
              return _SuggestionRow(
                suggestion: s,
                cityId: cityId,
                rank: i,
                clears: needed > 0 && s.result.score >= needed,
                loaded: isLoaded,
                onTap: () => onLoad(s.handIndexes),
              );
            },
          ),
        ),
      ],
    );
  }

  static bool _sameSelection(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final sortedB = List<int>.of(b)..sort();
    for (var i = 0; i < a.length; i++) {
      if (a[i] != sortedB[i]) return false;
    }
    return true;
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.cityId,
    required this.rank,
    required this.clears,
    required this.loaded,
    required this.onTap,
  });

  final gc.DishSuggestion suggestion;
  final String cityId;
  final int rank;

  /// This single dish would finish the service — the most actionable thing the Coach knows.
  final bool clears;
  final bool loaded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = suggestion.result;
    final dish = gc.kDishNames[cityId]?[r.pattern] ?? r.pattern;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: loaded ? T.panel2 : T.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: loaded
                ? T.brass
                : clears
                    ? T.good
                    : T.line,
            width: loaded || clears ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (rank == 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Text('◎', style: TextStyle(fontSize: 12, color: T.brass)),
                        ),
                      Flexible(
                        child: Text(dish, style: T.dish(15), overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${suggestion.handIndexes.length} card${suggestion.handIndexes.length == 1 ? '' : 's'}',
                        style: T.label.copyWith(fontSize: 9),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    suggestion.why,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.bodyDim.copyWith(fontSize: 10.5, height: 1.2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatScore(r.score), style: T.score(18)),
                if (clears)
                  Text('CLEARS', style: T.label.copyWith(fontSize: 8.5, color: T.good)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Coach annotations for the Bazaar: what an offer is actually worth to this build.
class CoachBuyHint extends StatelessWidget {
  const CoachBuyHint({required this.valuation, required this.isBest, super.key});

  final gc.OfferValuation valuation;
  final bool isBest;

  @override
  Widget build(BuildContext context) {
    final v = valuation;
    // Coin utensils genuinely measure at zero here — the valuation is denominated in dish
    // score and they pay in coins. Showing "+0" would read as "worthless", which is wrong,
    // so economy buys get the reason instead of the number.
    final showNumber = v.category != 'economy' && v.marginalValue > 0;
    return Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: T.bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: isBest ? T.brass : T.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isBest ? '◎' : '🧠', style: TextStyle(fontSize: 11, color: T.brass)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              v.why,
              style: T.bodyDim.copyWith(fontSize: 10.5, height: 1.25),
            ),
          ),
          if (showNumber) ...[
            const SizedBox(width: 6),
            Text(
              '+${formatScore(v.marginalValue.round())}',
              style: T.label.copyWith(fontSize: 10, color: T.good),
            ),
          ],
        ],
      ),
    );
  }
}

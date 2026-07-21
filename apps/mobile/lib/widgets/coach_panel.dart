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

class CoachPanel extends StatefulWidget {
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
  State<CoachPanel> createState() => _CoachPanelState();
}

class _CoachPanelState extends State<CoachPanel> {
  /// Blend advice, memoised on [gc.blendAdviceKey].
  ///
  /// `suggestBlends` runs a dish search per candidate play, which is an order of magnitude
  /// more work than the dish ladder, and this panel rebuilds on every card tap — where the
  /// hand, the rack, the deck and the scoring context have all stayed exactly as they were.
  /// The key covers every input the solver reads (game_core owns it, and a test pins that),
  /// so a hit is a genuinely identical question and a miss recomputes from the live engine.
  String? _blendKey;
  List<gc.BlendSuggestion> _blends = const [];

  List<gc.BlendSuggestion> _blendAdvice() {
    final key = gc.blendAdviceKey(widget.run);
    if (key != _blendKey) {
      _blendKey = key;
      _blends = gc.suggestBlends(widget.run);
    }
    return _blends;
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final suggestions = widget.suggestions;
    final blends = _blendAdvice();

    if (suggestions.isEmpty && blends.isEmpty) {
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
    final best = suggestions.isEmpty ? 0 : suggestions.first.result.score;

    // A blend that beats everything cookable right now IS the play, so it leads. The rest
    // drop below the ladder as reference — a blend you cannot use well yet is still a
    // mechanic worth learning, and nothing else in the game explains it.
    final leading = [for (final b in blends) if (b.result != null && b.result!.score > best) b];
    final trailing = [for (final b in blends) if (!leading.contains(b)) b];

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
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final b in leading)
                BlendAdviceRow(
                  advice: b,
                  loaded: _sameSelection(b.handIndexes, widget.selected),
                  onTap: () => widget.onLoad(b.handIndexes),
                ),
              for (var i = 0; i < suggestions.length; i++)
                _SuggestionRow(
                  suggestion: suggestions[i],
                  cityId: cityId,
                  rank: leading.isEmpty ? i : i + 1,
                  clears: needed > 0 && suggestions[i].result.score >= needed,
                  loaded: _sameSelection(suggestions[i].handIndexes, widget.selected),
                  onTap: () => widget.onLoad(suggestions[i].handIndexes),
                ),
              if (trailing.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('⚗️ YOUR BLENDS', style: T.label.copyWith(fontSize: 9)),
                const SizedBox(height: 4),
                for (final b in trailing)
                  BlendAdviceRow(
                    advice: b,
                    loaded: b.handIndexes.isNotEmpty &&
                        _sameSelection(b.handIndexes, widget.selected),
                    onTap: b.handIndexes.isEmpty ? null : () => widget.onLoad(b.handIndexes),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static bool _sameSelection(List<int> a, List<int> b) {
    if (a.isEmpty || a.length != b.length) return false;
    final sortedA = List<int>.of(a)..sort();
    final sortedB = List<int>.of(b)..sort();
    for (var i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }
}

/// One blend in the rack, and what the engine says it would do for this hand.
///
/// Tapping loads the exact cards the advice names, so the player's next tap is the blend chip
/// itself — the same "show me, don't tell me" grammar as the dish rows.
class BlendAdviceRow extends StatelessWidget {
  const BlendAdviceRow({
    required this.advice,
    required this.loaded,
    required this.onTap,
    super.key,
  });

  final gc.BlendSuggestion advice;
  final bool loaded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final helps = advice.result != null;
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
            color: loaded ? T.brass : (helps ? T.umami : T.line),
            width: loaded || helps ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Text('⚗️', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(advice.blend.name, style: T.dish(14)),
                  const SizedBox(height: 2),
                  Text(
                    advice.why,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.bodyDim.copyWith(fontSize: 10.5, height: 1.2),
                  ),
                ],
              ),
            ),
            if (helps) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatScore(advice.result!.score), style: T.score(16)),
                  Text('+${formatScore(advice.gain)}',
                      style: T.label.copyWith(fontSize: 8.5, color: T.good)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
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
    //
    // Blends are excluded for the opposite reason: their number is a rank weight, not dish
    // score (see `blendRankWeight`), and printing "+55" beside a measured "+360" claims a
    // measurement the engine never made. The Coach may not state a number the game won't pay.
    final showNumber =
        v.category != 'economy' && v.category != 'consumable' && v.marginalValue > 0;
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

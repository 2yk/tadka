/// How to Play.
///
/// The whole game is "score = flavor × heat, and everything else bends those two numbers".
/// A player who doesn't have that sentence is guessing, and guessing isn't the fun kind of
/// uncertainty — so this leads with it rather than with a feature tour.
///
/// Reachable from every screen via ?, and shown once automatically on a first-ever run so a
/// new player isn't dropped into a service cold.
library;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../theme.dart';
import '../widgets/buttons.dart';

class HelpSheet extends StatelessWidget {
  const HelpSheet({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('HOW TO PLAY', style: T.label.copyWith(color: T.brass)),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: T.dim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Lead(),
                const SizedBox(height: 16),
                _Section(
                  title: 'THE GOAL',
                  body: 'Each service has a target score. Reach it before you run out of cooks '
                      'and you travel on. Clear all three services in a city to move to the next, '
                      'and clear the whole route to win. Every run visits '
                      '${gc.kRouteLength} cities drawn from ${gc.kCityPool.length}, starting in '
                      'Kochi — so no two journeys are the same.',
                ),
                const _Section(
                  title: 'COOKING',
                  body: 'You hold 8 ingredients. Tap 1–5, then COOK — you get 4 cooks per service. '
                      'Don\'t like your hand? Select cards and SWAP them for new ones (3 per service).',
                ),
                const _RecipeTable(),
                const _Section(
                  title: 'WHAT MAKES A RECIPE',
                  body: 'Matching ranks make Pair / Three / Four of a Kind / Full House. '
                      'Five cards of one flavor family make a Flush. Five cards in a rank-run make '
                      'a Straight. Each city renames them after a local dish — a Pair is a Chaat in '
                      'Kochi and an Onigiri in Tokyo.',
                ),
                const _Section(
                  title: 'UTENSILS',
                  body: 'Permanent boosts, up to 5. They fire left to right on every dish and '
                      'ORDER MATTERS — a utensil that adds flavor before one that multiplies heat '
                      'is worth more than the other way round.',
                ),
                const _Section(
                  title: 'BLENDS',
                  body: 'One-time helpers. Tap the ingredients you want to change, then tap the '
                      'blend. They\'re the only way to reach the three secret recipes.',
                ),
                const _Section(
                  title: 'FESTIVALS 🎉',
                  body: 'Permanently level up your Kitchen — every recipe\'s base score grows for '
                      'the rest of the run. Buy them in the Bazaar; bosses grant free levels. '
                      'This compounding is how you reach the big late-city targets, so don\'t skip them.',
                ),
                const _Section(
                  title: 'PALATES & CRITICS',
                  body: 'The green line is the city\'s palate — a scoring bonus worth building '
                      'around. The red line is a critic on the third service, with a rule you must '
                      'obey. Debuffed cards are marked in your hand.',
                ),
                const _Section(
                  title: '🧠 COACH',
                  body: 'Tap the brain to toggle it. It lists your best possible dishes, highest '
                      'first, with the exact reason each scores what it does — tap a row to load '
                      'those cards. In the Bazaar it ranks what\'s actually worth buying. '
                      'Leave it on while you learn the combos, turn it off once they click.',
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PressableButton(
            onTap: onClose,
            child: const Text('GOT IT',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ),
        ],
      ),
    ),
  );
}

/// The one sentence that makes the rest of the game legible.
class _Lead extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: T.panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: T.brass, width: 1.5),
    ),
    child: Column(
      children: [
        Text('SCORE =', style: T.label),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('FLAVOR', style: T.dish(22, color: T.good)),
            Text('  ×  ', style: T.dish(20, color: T.dim)),
            Text('HEAT', style: T.dish(22, color: T.bad)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Flavor adds up. Heat multiplies. A dish with big flavor and no heat scores '
          'almost nothing — and so does the reverse. Every card, utensil and palate in the '
          'game is bending one of those two numbers.',
          textAlign: TextAlign.center,
          style: T.bodyDim.copyWith(fontSize: 12.5, height: 1.4),
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: T.label.copyWith(color: T.ink)),
        const SizedBox(height: 4),
        Text(body, style: T.bodyDim.copyWith(fontSize: 12.5, height: 1.4)),
      ],
    ),
  );
}

/// Recipes with their real base numbers, straight from the engine tables — so the ladder is
/// concrete rather than a vague "bigger is better", and can never drift from what scores.
class _RecipeTable extends StatelessWidget {
  const _RecipeTable();

  @override
  Widget build(BuildContext context) {
    final order = gc.kPatternOrder.reversed
        .where((p) => !gc.kSecretPatterns.contains(p))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RECIPES — BIGGER IS MUCH BETTER', style: T.label.copyWith(color: T.ink)),
          const SizedBox(height: 6),
          for (final p in order)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(gc.kGenericNames[p] ?? p,
                        style: T.body.copyWith(fontSize: 12.5)),
                  ),
                  Text(
                    '${gc.kRecipe[p]!.$1} flavor × ${gc.kRecipe[p]!.$2} heat',
                    style: T.bodyDim.copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Three more recipes are hidden — reachable only with blends.',
            style: T.bodyDim.copyWith(fontSize: 11.5, color: T.umami),
          ),
        ],
      ),
    );
  }
}

/// How to Play.
///
/// The whole game is "score = flavor × heat, and everything else bends those two numbers".
/// A player who doesn't have that sentence is guessing, and guessing isn't the fun kind of
/// uncertainty — so this leads with it rather than with a feature tour.
///
/// Reachable from every screen via ?, and shown once automatically on a first-ever run so a
/// new player isn't dropped into a service cold.
///
/// **Every number here is read out of the engine tables**, and every list is generated from the
/// catalog it documents — recipes from `kRecipe`, stakes from `kStakes`, decks from `kDecks`,
/// blends from `kBlends`. Help that restates constants in prose is help that is wrong one
/// content drop later, and nobody re-reads the tutorial to check.
library;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../daily.dart';
import '../game_controller.dart';
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
                _Section(
                  title: 'INGREDIENTS',
                  body: 'Every card has a flavor family (${gc.kFamilies.map(_title).join(', ')}) '
                      'and an intensity from 1 to 10. Intensity is the flavor the card adds; the '
                      'family is what makes Flushes and what palates pay bonuses on. Two cards in '
                      'the pantry are PRIZED — Saffron and Ghee — and add '
                      '+${gc.kPrizedBonus} flavor on top of their intensity. A blend can gild any '
                      'card into a prized one.',
                ),
                const _Section(
                  title: 'UTENSILS',
                  body: 'Permanent boosts, up to 5. They fire left to right on every dish and '
                      'ORDER MATTERS — a utensil that adds flavor before one that multiplies heat '
                      'is worth more than the other way round. Some multiply heat, some multiply '
                      'flavor; a rack with one of each is the biggest jump in the game.',
                ),
                const _Section(
                  title: 'BLENDS ⚗️',
                  body: 'One-time helpers, and the game\'s hidden half. They EDIT your cards '
                      'instead of scoring them: tap the ingredients you want to change, then tap '
                      'the blend. Some take two cards, and for those the FIRST card you tap is '
                      'the source — the one that gets copied. They are the only way to reach the '
                      'secret recipes.',
                ),
                const _BlendTable(),
                const _SecretRecipes(),
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
                      'obey. Debuffed cards are marked in your hand: they contribute nothing at '
                      'all, not even the palate bonus.',
                ),
                _Section(
                  title: 'THE BAZAAR 🪙',
                  body: 'Between services you shop. Clearing a service pays 4 coins, plus 1 for '
                      'every cook you did NOT use — so winning early is worth real money. On top '
                      'of that you earn interest: 1 coin for every 5 you are holding, capped at '
                      '5 a service. Sitting on 25 coins is a free utensil every two services, '
                      'which is why banking is a real decision.\n\n'
                      'Three offers a time. ${GameController.rerollCost} coins rerolls all three. '
                      'You can sell a utensil from your rack for half its shop price to make room '
                      'or raise coins. Utensil slots are limited (5, fewer on some decks and at '
                      'the top stake) and you can hold at most 3 blends.',
                ),
                const _DeckTable(),
                const _StakeTable(),
                _Section(
                  title: '📅 DAILY ROUTE',
                  body: 'One run a day, the same for everybody — the seed is the date, so every '
                      'player gets identical cards, shops and critics and the scores are directly '
                      'comparable. Fixed to the '
                      '${gc.kDeckById[kDailyDeck]?.name ?? kDailyDeck} at stake $kDailyStake, '
                      'because a deck choice would make that comparison meaningless. Finishing on '
                      'consecutive days builds a streak.',
                ),
                const _Section(
                  title: '♾️ THE LONG ROUTE',
                  body: 'Win, and you can keep going instead of banking the run. Targets compound '
                      'harder with every extra city, every third one stacks two critics into a '
                      'single "Legend" demand, and it ends when the numbers finally outrun your '
                      'build. How far you get is your distance, and the top 10 are kept.',
                ),
                const _Section(
                  title: '📖 RECIPE BOOK',
                  body: 'The whole collection, from the start screen: every recipe with its real '
                      'base numbers, every utensil, every deck, and the stake grid showing which '
                      'of the 8 chilis you have cleared on each deck.',
                ),
                const _Section(
                  title: '🧠 COACH',
                  body: 'Tap the brain to toggle it. It lists your best possible dishes, highest '
                      'first, with the exact reason each scores what it does — tap a row to load '
                      'those cards. It also says what each blend you are holding would do for '
                      'this exact hand, and tapping that loads the cards to target. In the Bazaar '
                      'it ranks what\'s actually worth buying. Everything it shows comes from the '
                      'real scoring engine, so it can never promise a number the game won\'t pay. '
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

String _title(String s) => '${s[0].toUpperCase()}${s.substring(1)}';

/// A titled block of `label — value` rows, which is the shape every generated table here has.
class _Table extends StatelessWidget {
  const _Table({required this.title, required this.rows, this.footer, this.footerColor});

  final String title;
  final List<(String label, String value)> rows;
  final String? footer;
  final Color? footerColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: T.label.copyWith(color: T.ink)),
        const SizedBox(height: 6),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 108,
                  child: Text(label, style: T.body.copyWith(fontSize: 12.5)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(value, style: T.bodyDim.copyWith(fontSize: 11.5, height: 1.3)),
                ),
              ],
            ),
          ),
        if (footer != null) ...[
          const SizedBox(height: 4),
          Text(footer!,
              style: T.bodyDim.copyWith(fontSize: 11.5, color: footerColor ?? T.dim)),
        ],
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
    return _Table(
      title: 'RECIPES — BIGGER IS MUCH BETTER',
      rows: [
        for (final p in order)
          (
            gc.kGenericNames[p] ?? p,
            '${gc.kRecipe[p]!.$1} flavor × ${gc.kRecipe[p]!.$2} heat',
          ),
      ],
      footer: '${gc.kSecretPatterns.length} more recipes are hidden — reachable only with '
          'blends. Each city renames every recipe after a local dish.',
      footerColor: T.umami,
    );
  }
}

/// The secret recipes, and the fact that blends are the only road to them.
///
/// Masked in a public build, because finding one is the payoff for having understood the blend
/// system. `kShowAllContent` is the internal-testing switch and names them outright.
class _SecretRecipes extends StatelessWidget {
  const _SecretRecipes();

  @override
  Widget build(BuildContext context) {
    if (!gc.kShowAllContent) {
      return _Section(
        title: 'THE SECRET RECIPES',
        body: '${gc.kSecretPatterns.length} recipes are not in the table above and cannot be '
            'dealt to you. Each needs cards the pantry does not contain — five of one '
            'intensity, or a whole dish in one family — so the only way to reach one is to '
            'build it with blends. Cook one and it names itself in the Recipe Book.',
      );
    }
    return _Table(
      title: 'THE SECRET RECIPES — BLENDS ONLY',
      rows: [
        for (final p in gc.kSecretPatterns)
          (
            gc.kGenericNames[p] ?? p,
            '${gc.kRecipe[p]!.$1} flavor × ${gc.kRecipe[p]!.$2} heat — '
                '${_secretHow[p] ?? 'built with blends'}',
          ),
      ],
      footer: 'None of these can be dealt to you: no pantry holds five cards of one intensity. '
          'Duplicate, copy or merge your way there.',
      footerColor: T.umami,
    );
  }
}

/// How each secret recipe is actually assembled. Authored, because it is strategy rather than
/// a number — but it describes exactly what `bestPattern` looks for.
const Map<String, String> _secretHow = {
  'five_kind': 'five cards of one intensity (Sun-Dry, Conserva, Julienne, Whetstone)',
  'full_family': 'a Full House whose five cards all share one family (Chili Oil, Infusion)',
  'perfect_palate': 'five of one intensity AND one family — the apex (Lievito Madre)',
};

/// Every blend in the game, generated from the catalog so it can never go stale.
class _BlendTable extends StatelessWidget {
  const _BlendTable();

  @override
  Widget build(BuildContext context) => _Table(
    title: 'EVERY BLEND (${gc.kBlends.length})',
    rows: [
      for (final b in gc.kBlends)
        (
          b.name,
          '${b.desc} · ${b.cost}🪙'
              '${b.select == 0 ? ' · no target' : ' · tap ${b.select}'}'
              '${b.select > 1 && gc.blendReadsSource(b) ? ', 1st is the source' : ''}',
        ),
    ],
    footer: 'You can carry 3 at a time. They are bought in the Bazaar, and some decks start '
        'with one.',
  );
}

/// The decks, generated from the catalog. Reserved decks are unimplemented and stay out.
class _DeckTable extends StatelessWidget {
  const _DeckTable();

  @override
  Widget build(BuildContext context) => _Table(
    title: 'PANTRY DECKS',
    rows: [
      for (final d in gc.kDecks.where((d) => !d.reserved)) (d.name, d.identity),
    ],
    footer: 'Each deck changes the cards you draw and what you open with. Win a run to unlock '
        'the next one.',
  );
}

/// The stake ladder, with each rung's real modifiers from `StakeModifier.describe`.
class _StakeTable extends StatelessWidget {
  const _StakeTable();

  @override
  Widget build(BuildContext context) => _Table(
    title: 'STAKES — ${gc.kStakes.length} RUNGS OF HEAT',
    rows: [
      for (final s in gc.kStakes)
        (
          '${s.id}  ${s.name}',
          s.modifiers.isEmpty
              ? 'the tutorial stake — no penalties'
              : s.modifiers.map((m) => m.describe()).join(' · '),
        ),
    ],
    footer: 'Stakes are cumulative: stake 5 carries everything from 1 to 4. Win a deck at one '
        'stake to unlock the next for that deck.',
  );
}

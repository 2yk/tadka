/// The Recipe Book — the collection, made visible.
///
/// Unlocks are the "one more run" engine, and they're worthless if the player can't see
/// what exists to chase. Locked items show as silhouettes rather than being hidden, because
/// a visible gap is a goal and an absent one is nothing.
///
/// Secret recipes stay masked as ??? until played once — they're only reachable through blend
/// manipulation, and spoiling them removes the discovery.
library;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../theme.dart';
import '../widgets/buttons.dart';

class RecipeBookScreen extends StatefulWidget {
  const RecipeBookScreen({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  State<RecipeBookScreen> createState() => _RecipeBookScreenState();
}

class _RecipeBookScreenState extends State<RecipeBookScreen> {
  int _tab = 0;
  static const _tabs = ['RECIPES', 'UTENSILS', 'DECKS', 'STAKES'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('📖 RECIPE BOOK', style: T.label.copyWith(color: T.brass)),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 20, color: T.dim),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == _tabs.length - 1 ? 0 : 5),
                      child: GestureDetector(
                        onTap: () => setState(() => _tab = i),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _tab == i ? T.panel2 : T.panel,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _tab == i ? T.brass : T.line),
                          ),
                          child: Text(
                            _tabs[i],
                            style: T.label.copyWith(
                              fontSize: 9.5,
                              color: _tab == i ? T.ink : T.dim,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_tab) {
                0 => const _Recipes(),
                1 => const _Utensils(),
                2 => const _Decks(),
                _ => const _Stakes(),
              },
            ),
            const SizedBox(height: 10),
            PressableButton(
              onTap: widget.onClose,
              child: const Text('CLOSE',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Recipes extends StatelessWidget {
  const _Recipes();

  @override
  Widget build(BuildContext context) {
    final discovered = gc.profile.recipesDiscovered.toSet();
    // strongest first — the ladder reads as something to climb
    final order = gc.kPatternOrder.reversed.toList();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: order.length,
      itemBuilder: (context, i) {
        final p = order[i];
        final secret = gc.kSecretPatterns.contains(p);
        final known = discovered.contains(p) || !secret;
        final base = gc.kRecipe[p]!;
        return _Row(
          title: known ? (gc.kGenericNames[p] ?? p) : '? ? ?',
          subtitle: known
              ? '${base.$1} flavor × ${base.$2} heat'
              : 'A secret recipe — reachable only with blends',
          locked: !known,
          trailing: secret
              ? Text('SECRET', style: T.label.copyWith(fontSize: 8.5, color: T.umami))
              : null,
        );
      },
    );
  }
}

class _Utensils extends StatelessWidget {
  const _Utensils();

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: EdgeInsets.zero,
    itemCount: gc.kUtensils.length,
    itemBuilder: (context, i) {
      final u = gc.kUtensils[i];
      final unlocked = gc.isUnlocked('utensil', u.id);
      return _Row(
        title: unlocked ? u.name : '???',
        subtitle: unlocked ? u.text : 'Locked — earn it by playing',
        locked: !unlocked,
        accent: T.rarityColor(u.rarity),
        trailing: Text(
          u.rarity.toUpperCase(),
          style: T.label.copyWith(fontSize: 8.5, color: T.rarityColor(u.rarity)),
        ),
      );
    },
  );
}

class _Decks extends StatelessWidget {
  const _Decks();

  @override
  Widget build(BuildContext context) {
    final decks = gc.kDecks.where((d) => !d.reserved).toList();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: decks.length,
      itemBuilder: (context, i) {
        final d = decks[i];
        final unlocked = gc.isUnlocked('deck', d.id);
        return _Row(
          title: unlocked ? d.name : '???',
          subtitle: unlocked ? d.identity : 'Locked',
          locked: !unlocked,
        );
      },
    );
  }
}

/// The Heat Ladder: 5 decks x 8 stakes = 40 goals, shown as a grid so the endgame is legible.
class _Stakes extends StatelessWidget {
  const _Stakes();

  @override
  Widget build(BuildContext context) {
    final decks = gc.kDecks.where((d) => !d.reserved).toList();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(
          'Win a deck at stake N to unlock N+1 for that deck.',
          style: T.bodyDim.copyWith(fontSize: 11.5),
        ),
        const SizedBox(height: 10),
        for (final d in decks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gc.isUnlocked('deck', d.id) ? d.name : '???',
                  style: T.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: gc.isUnlocked('deck', d.id) ? T.ink : T.dim,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    for (var s = 1; s <= 8; s++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: s == 8 ? 0 : 4),
                          child: Container(
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: gc.maxStake(d.id) > s ? T.brass.withValues(alpha: 0.22) : T.panel,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: gc.maxStake(d.id) > s
                                    ? T.brass
                                    : (gc.maxStake(d.id) == s ? T.dim : T.line),
                              ),
                            ),
                            child: Text(
                              gc.maxStake(d.id) > s ? '🌶️' : '$s',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: gc.maxStake(d.id) >= s ? T.ink : T.dim.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.locked,
    this.trailing,
    this.accent,
  });

  final String title;
  final String subtitle;
  final bool locked;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: locked ? 0.45 : 1,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: locked ? T.line : (accent ?? T.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.dish(15)),
                const SizedBox(height: 1),
                Text(subtitle, style: T.bodyDim.copyWith(fontSize: 11)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    ),
  );
}

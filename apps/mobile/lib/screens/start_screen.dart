/// Start screen — deck, stake, seed.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:package_info_plus/package_info_plus.dart';

import '../daily.dart';
import '../game_controller.dart';
import '../theme.dart';
import '../widgets/juice.dart';
import '../widgets/buttons.dart';

/// Mints a run's seed. This is the ONE place entropy enters a run — everything downstream
/// is seeded, so every run stays exactly reproducible.
///
/// There is deliberately no seed input on this screen: it asked the player to care about
/// something that only matters after the fact. The seed is generated silently and surfaced
/// on the summary screen, where "replay this exact run" is a thing you actually want.
/// Determinism itself is load-bearing (bug reports, the future Daily Route, golden tests)
/// and is unaffected by hiding the field.
///
/// The alphabet omits I/O/0/1 so a seed read off a phone can be retyped without ambiguity.
String randomSeed() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random();
  return 'SPICE-${List.generate(5, (_) => alphabet[r.nextInt(alphabet.length)]).join()}';
}

class StartScreen extends StatefulWidget {
  const StartScreen({required this.controller, super.key});

  final GameController controller;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final decks = gc.unlockedDecks();
    final maxStake = gc.maxStake(c.deckId);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Text('SPICE ROUTE', style: T.dish(34, color: T.brass))),
            const SizedBox(height: 2),
            Center(child: Text('A DELICIOUS ROGUELIKE', style: T.label)),
            const SizedBox(height: 26),

            Text('PANTRY DECK', style: T.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in gc.kDecks.where((d) => !d.reserved))
                  _Chip(
                    label: decks.any((u) => u.id == d.id) ? d.name : '🔒 ${d.name}',
                    selected: c.deckId == d.id,
                    enabled: decks.any((u) => u.id == d.id),
                    onTap: () => setState(() {
                      c.deckId = d.id;
                      c.stake = c.stake.clamp(1, gc.maxStake(d.id));
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              gc.kDeckById[c.deckId]?.identity ?? '',
              style: T.bodyDim.copyWith(fontSize: 12),
            ),

            const SizedBox(height: 20),
            Text('STAKE · ${gc.kStakeById[c.stake]!.name.toUpperCase()}', style: T.label),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var s = 1; s <= 8; s++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: s == 8 ? 0 : 5),
                      child: _Chip(
                        label: s <= maxStake ? '$s' : '🔒',
                        selected: c.stake == s,
                        enabled: s <= maxStake,
                        dense: true,
                        onTap: () => setState(() => c.stake = s),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Builder(builder: (context) {
              // Red is for the penalties a stake imposes. Stake 1 has none, so colouring its
              // description as a warning misreads the tutorial stake as dangerous.
              final mods = gc.kStakeById[c.stake]!.modifiers;
              return Text(
                mods.isEmpty
                    ? 'Base difficulty — the tutorial stake.'
                    : mods.map((m) => m.describe()).join(' · '),
                style: T.bodyDim.copyWith(fontSize: 12, color: mods.isEmpty ? T.dim : T.bad),
              );
            }),

            const SizedBox(height: 22),
            _DailyCard(status: c.daily, onPlay: c.startDaily),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
              onTap: c.openRecipeBook,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: T.panel,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: T.line),
                ),
                child: Text('📖  RECIPE BOOK', style: T.label.copyWith(color: T.ink)),
              ),
            ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: c.openHelp,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: T.panel,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: T.line),
                    ),
                    child: Text('?', style: T.label.copyWith(fontSize: 14, color: T.ink)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PressableButton(
              height: 60,
              onTap: () => c.startRun(randomSeed()),
              child: const Text(
                '▶  PLAY',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: T.inkDark,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // A tester who says "it crashed" is telling you almost nothing without this.
            const Center(child: _BuildStamp()),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.4,
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 13, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? T.panel2 : T.panel,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? T.brass : T.line, width: selected ? 1.6 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? T.ink : T.dim,
          ),
        ),
      ),
    ),
  );
}

/// Today's Daily Route.
///
/// Given top billing on the start screen because it is the one reason to open the app on a
/// day you weren't otherwise going to play — which is exactly what a retention hook is for.
/// It shows the streak even at zero, so the number is visibly something to protect.
class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.status, required this.onPlay});

  final DailyStatus status;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onPlay,
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: status.playedToday ? T.line : T.brass, width: 1.5),
      ),
      child: Row(
        children: [
          const Text('📅', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DAILY ROUTE', style: T.label.copyWith(color: T.brass)),
                const SizedBox(height: 2),
                Text(
                  status.playedToday
                      ? 'Played today — tap to replay'
                      : 'The same run for everyone, today only',
                  style: T.bodyDim.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('🔥 ${status.streak}', style: T.dish(15, color: T.brass)),
              if (status.bestScore > 0)
                Text('best ${formatScore(status.bestScore)}',
                    style: T.label.copyWith(fontSize: 8.5)),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Build identifier, shown quietly on the start screen.
///
/// External testers report bugs hours or days later, often on a build that has since been
/// replaced. Without a version on screen, "it crashed on the third city" can't be matched to a
/// commit — and since every run is already reproducible from its seed, a build plus a seed is a
/// complete bug report.
class _BuildStamp extends StatelessWidget {
  const _BuildStamp();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: PackageInfo.fromPlatform(),
    builder: (context, snap) {
      final info = snap.data;
      if (info == null) return const SizedBox(height: 12);
      return Text(
        'v${info.version}+${info.buildNumber}',
        style: T.label.copyWith(fontSize: 9, color: T.dim.withValues(alpha: 0.6)),
      );
    },
  );
}

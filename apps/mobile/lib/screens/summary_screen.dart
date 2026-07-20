/// Run summary — per-service history, cause of death, and the seed.
///
/// This is the only place the seed surfaces. There's no seed input on the start screen —
/// it asked the player to care up front about something that only matters in hindsight —
/// but every run is seeded, so "replay that exact run" still works from here.
library;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../game_controller.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/juice.dart';
import 'start_screen.dart';

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({required this.controller, super.key});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final run = c.run!;
    final won = run.status == 'won';
    final last = run.history.isNotEmpty ? run.history.last : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              won ? '🏆 THE ROUTE IS YOURS' : 'RUN OVER',
              textAlign: TextAlign.center,
              style: T.dish(26, color: won ? T.brass : T.bad),
            ),
            const SizedBox(height: 4),
            Text(
              won
                  ? 'You cooked your way from Kochi to Naples.'
                  : last == null
                      ? ''
                      : 'Missed ${last.svc} in ${last.city} — '
                          '${formatScore(last.score)} of ${formatScore(last.target)}.',
              textAlign: TextAlign.center,
              style: T.bodyDim,
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: T.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: T.line),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Stat(label: 'TOTAL', value: formatScore(run.totalScore)),
                  _Stat(label: 'KITCHEN', value: 'Lv ${run.kitchenLevel}'),
                  _Stat(label: 'STAKE', value: gc.kStakeById[run.stake]!.name),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Expanded(
              child: ListView(
                children: [
                  for (final h in run.history)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                      decoration: BoxDecoration(
                        color: T.panel,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: h.win ? T.line : T.bad),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${h.city} · ${h.svc}',
                                style: T.body.copyWith(fontSize: 13)),
                          ),
                          Text(
                            '${formatScore(h.score)} / ${formatScore(h.target)}',
                            style: T.bodyDim.copyWith(
                              fontSize: 12,
                              color: h.win ? T.good : T.bad,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SEED  ', style: T.label),
                SelectableText(
                  run.seed,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: T.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (won) ...[
              PressableButton(
                onTap: c.continueEndless,
                child: const Text('CONTINUE THE ROUTE →',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
              const SizedBox(height: 6),
              Text(
                'Targets keep compounding. The run ends when you miss one.',
                textAlign: TextAlign.center,
                style: T.bodyDim.copyWith(fontSize: 11.5),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: PressableButton(
                    filled: false,
                    child: const Text('REPLAY RUN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    onTap: () {
                      final seed = run.seed;
                      final stake = run.stake;
                      final deck = run.deckId;
                      c
                        ..deckId = deck
                        ..stake = stake
                        ..startRun(seed);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PressableButton(
                    onTap: () => c.startRun(randomSeed()),
                    child: const Text('PLAY AGAIN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: c.backToStart,
              child: Text('← Change deck / stake',
                  textAlign: TextAlign.center, style: T.bodyDim.copyWith(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: T.label),
      const SizedBox(height: 2),
      Text(value, style: T.dish(17)),
    ],
  );
}

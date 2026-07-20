/// Start screen — deck, stake, seed.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../game_controller.dart';
import '../theme.dart';

/// Mints a human-readable seed. This is the ONE place entropy enters a run — everything
/// downstream is seeded, so a blank field still produces a fully replayable run rather than
/// an unseeded one. The alphabet omits I/O/0/1 because players read seeds off a phone and
/// retype them.
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
  final _seed = TextEditingController();

  @override
  void dispose() {
    _seed.dispose();
    super.dispose();
  }

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
            Text(
              gc.kStakeById[c.stake]!.modifiers.isEmpty
                  ? 'Base difficulty — the tutorial stake.'
                  : gc.kStakeById[c.stake]!.modifiers.map((m) => m.describe()).join(' · '),
              style: T.bodyDim.copyWith(fontSize: 12, color: T.bad),
            ),

            const SizedBox(height: 22),
            TextField(
              controller: _seed,
              style: const TextStyle(fontFamily: 'monospace', color: T.ink, fontSize: 15),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'seed — blank for random',
                hintStyle: T.bodyDim.copyWith(fontSize: 14),
                filled: true,
                fillColor: T.panel,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: T.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: T.brass),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                final s = _seed.text.trim();
                c.startRun(s.isEmpty ? randomSeed() : s);
              },
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [T.brassLight, T.brass],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(bottom: BorderSide(color: T.brassDark, width: 4)),
                ),
                child: const Text(
                  '▶  START RUN',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: T.inkDark,
                  ),
                ),
              ),
            ),
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

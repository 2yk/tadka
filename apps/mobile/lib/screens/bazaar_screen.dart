/// The Bazaar — spend coins between services.
///
/// Festivals are the scaling engine: each one permanently levels a recipe for the rest of the
/// run, and leveled base × utensil multipliers is what makes the late-city targets reachable.
/// They're visually distinguished for that reason.
library;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../game_controller.dart';
import '../theme.dart';
import '../widgets/buttons.dart';

class BazaarScreen extends StatelessWidget {
  const BazaarScreen({required this.controller, super.key});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final run = c.run!;
    final offers = c.offers ?? const <gc.Offer>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('THE BAZAAR', style: T.label),
                const Spacer(),
                Text('🪙 ${run.coins}', style: T.dish(22, color: T.brass)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Kitchen Lv ${run.kitchenLevel}  ·  ${run.utensils.length}/${run.utensilSlots} utensils',
                style: T.bodyDim.copyWith(fontSize: 12)),
            const SizedBox(height: 14),

            Expanded(
              child: ListView(
                children: [
                  for (final o in offers)
                    _OfferTile(
                      offer: o,
                      affordable: run.coins >= o.cost,
                      blockedReason: o.kind == 'utensil' && run.utensils.length >= run.utensilSlots
                          ? 'No free slot'
                          : null,
                      onBuy: () => c.buy(o),
                    ),
                  if (offers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('Everything bought.', textAlign: TextAlign.center, style: T.bodyDim),
                    ),
                  const SizedBox(height: 14),
                  if (run.utensils.isNotEmpty) ...[
                    Text('YOUR RACK — tap to sell for half', style: T.label),
                    const SizedBox(height: 8),
                    for (var i = 0; i < run.utensils.length; i++)
                      _RackRow(
                        utensil: run.utensils[i],
                        onSell: () => c.sellUtensil(i),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PressableButton(
                    enabled: run.coins >= GameController.rerollCost,
                    onTap: c.reroll,
                    filled: false,
                    child: Text('REROLL (${GameController.rerollCost}🪙)',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PressableButton(
                    onTap: c.nextService,
                    child: const Text('NEXT SERVICE →',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({
    required this.offer,
    required this.affordable,
    required this.blockedReason,
    required this.onBuy,
  });

  final gc.Offer offer;
  final bool affordable;
  final String? blockedReason;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final enabled = affordable && blockedReason == null;
    final tint = T.rarityColor(offer.rarity);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onBuy : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: T.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tint, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: T.panel2,
                  shape: BoxShape.circle,
                  border: Border.all(color: tint, width: 2),
                ),
                child: Text(
                  switch (offer.kind) { 'festival' => '🎉', 'blend' => '⚗️', _ => '🍳' },
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.name, style: T.dish(16)),
                    const SizedBox(height: 2),
                    Text(
                      offer.kind == 'festival'
                          ? 'Level up ${gc.kGenericNames[offer.pattern] ?? offer.pattern} — permanent this run'
                          : offer.desc,
                      style: T.bodyDim.copyWith(fontSize: 11.5),
                    ),
                    if (blockedReason != null)
                      Text(blockedReason!, style: T.bodyDim.copyWith(fontSize: 11, color: T.bad)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${offer.cost}🪙', style: T.dish(16, color: T.brass)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RackRow extends StatelessWidget {
  const _RackRow({required this.utensil, required this.onSell});

  final gc.Utensil utensil;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onSell,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: T.rarityColor(utensil.rarity)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(utensil.name, style: T.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(utensil.text, style: T.bodyDim.copyWith(fontSize: 11)),
              ],
            ),
          ),
          Text('+${(utensil.cost / 2).floor()}🪙', style: T.bodyDim.copyWith(color: T.good)),
        ],
      ),
    ),
  );
}

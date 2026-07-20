/// The service screen — the minute-to-minute game.
///
/// Layout is portrait and thumb-zoned: the action bar sits low and the space above it is
/// intentional, so the whole loop is one-handed. Every number shown comes from `game_core`
/// (`scoreDish` / `dishError`), never from a parallel calculation here.
library;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../game_controller.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/ingredient_card.dart';
import '../widgets/juice.dart';

class ServiceScreen extends StatefulWidget {
  const ServiceScreen({
    required this.controller,
    required this.particles,
    required this.shake,
    super.key,
  });

  final GameController controller;
  final ParticleController particles;
  final ShakeController shake;

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  /// Per-hand-slot keys so particle bursts can originate from the actual card on screen.
  final Map<int, GlobalKey> _cardKeys = {};

  /// Anchor for where a cooked dish resolves, so cards have somewhere to fly to.
  final GlobalKey _panelKey = GlobalKey();

  /// Blocks input while the cook animation plays, so a double-tap can't cook twice.
  bool _busy = false;
  gc.ScoreResult? _toast;

  GlobalKey _keyFor(int i) => _cardKeys.putIfAbsent(i, GlobalKey.new);

  /// Sends the played cards up into the dish panel.
  ///
  /// Without this the cards simply vanish from the hand and a number appears elsewhere —
  /// the two events don't read as connected. Flying them into the panel is what makes the
  /// score feel *caused* by the cards you chose.
  void _flyCards(List<(Offset from, gc.Card card, double width)> cards, Offset to) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _FlyingCards(
        cards: cards,
        target: to,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  Future<void> _cook() async {
    final c = widget.controller;
    if (_busy || c.selected.isEmpty) return;
    final blocker = c.cookBlocker;
    if (blocker != null) {
      setState(() => c.errorMessage = blocker);
      return;
    }
    setState(() => _busy = true);

    // Capture positions before the cards leave the hand.
    final positions = <(Offset, Color)>[];
    final flying = <(Offset, gc.Card, double)>[];
    for (final i in c.selected) {
      final box = _keyFor(i).currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final card = c.run!.hand[i];
        positions.add((
          box.localToGlobal(box.size.center(Offset.zero)),
          T.family[card.family] ?? T.umami,
        ));
        flying.add((box.localToGlobal(Offset.zero), card, box.size.width));
      }
    }
    final panelBox = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    final target = panelBox?.localToGlobal(panelBox.size.center(Offset.zero));

    final out = c.cook();
    final result = out?.result;
    if (result == null) {
      setState(() => _busy = false);
      return;
    }

    setState(() => _toast = result);

    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduced && target != null && flying.isNotEmpty) {
      _flyCards(flying, target);
    }

    // Stagger a burst per triggered card, matching the web build's per-card cascade.
    for (var i = 0; i < positions.length; i++) {
      Future<void>.delayed(Duration(milliseconds: 70 * i), () {
        if (!mounted) return;
        widget.particles.burst(positions[i].$1, positions[i].$2);
      });
    }

    final heat = result.heat;
    hapticForScore(heat >= 8 ? 4 : (heat >= 4 ? 2 : 1));
    final hasMult = result.steps.any((s) => s.cls == 'mult');
    if (hasMult) widget.shake.shake(heat >= 8 ? 5 : 2);

    // Let the count-up land before resolving the service.
    await Future<void>.delayed(Motion.countUp + const Duration(milliseconds: 620));
    if (!mounted) return;
    setState(() {
      _toast = null;
      _busy = false;
    });
    if (out!.outcome == 'won') {
      c.afterServiceWon();
    } else if (out.outcome == 'lost') {
      c.afterServiceLost();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final run = c.run!;
    final city = gc.cityOf(run);
    final palate = gc.kPalates[city.id];
    final preview = c.preview;
    final pad = MediaQuery.paddingOf(context);

    return Padding(
      padding: EdgeInsets.only(top: pad.top + 6, bottom: pad.bottom + 6, left: 12, right: 12),
      child: Column(
        children: [
          _Header(run: run, city: city, palate: palate),
          const SizedBox(height: 10),
          _ScoreBar(run: run),
          const SizedBox(height: 8),
          _UtensilRack(run: run),
          const SizedBox(height: 12),
          _RouteStrip(run: run),
          // Everything below is anchored to the thumb zone; the gap above is the "stage" the
          // dish resolves into, and is intentional per the layout brief.
          const Spacer(),
          KeyedSubtree(
            key: _panelKey,
            child: _toast != null
                ? _DishToast(result: _toast!, cityId: city.id)
                : _PreviewBar(
                    preview: preview,
                    blocker: c.selected.isEmpty ? null : c.cookBlocker,
                    error: c.errorMessage,
                  ),
          ),
          const SizedBox(height: 10),
          _Hand(
            run: run,
            selected: c.selected,
            keyFor: _keyFor,
            enabled: !_busy,
            onTap: (i) => setState(() => c.toggleCard(i)),
          ),
          const SizedBox(height: 12),
          _ActionBar(
            cooksLeft: run.cooksLeft,
            swapsLeft: run.swapsLeft,
            canCook: !_busy && c.selected.isNotEmpty && c.cookBlocker == null,
            canSwap: !_busy && c.selected.isNotEmpty && run.swapsLeft > 0,
            onCook: _cook,
            onSwap: () => setState(c.swap),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.run, required this.city, required this.palate});

  final gc.RunState run;
  final gc.City city;
  final gc.Palate? palate;

  @override
  Widget build(BuildContext context) {
    final critic = run.critic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(city.name, style: T.dish(24), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text('🪙 ${run.coins}', style: T.dish(18, color: T.brass)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: T.panel2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: T.line),
              ),
              child: Text('Lv ${run.kitchenLevel}', style: T.label.copyWith(color: T.ink)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          run.endless ? 'Route +${run.endlessCity}' : gc.kServiceNames[run.serviceIndex].toUpperCase(),
          style: T.label,
        ),
        if (palate != null) ...[
          const SizedBox(height: 4),
          Text('◈ ${palate!.label}', style: T.bodyDim.copyWith(color: T.good, fontSize: 12)),
        ],
        if (critic != null) ...[
          const SizedBox(height: 2),
          Text('✦ ${critic.name} — ${critic.rule}',
              style: T.bodyDim.copyWith(color: T.bad, fontSize: 12)),
        ],
      ],
    );
  }
}

/// The journey, at a glance: three cities of three services, with the current one lit.
///
/// A run is a route — the concept doc's whole pitch is travelling it — but the header only
/// ever shows where you are, never how far you've come or what's left. This makes the shape
/// of the run legible without spending a tap.
class _RouteStrip extends StatelessWidget {
  const _RouteStrip({required this.run});

  final gc.RunState run;

  @override
  Widget build(BuildContext context) {
    if (run.endless) {
      return Text('THE LONG ROUTE · ${run.endlessCity}  ·  DISTANCE ${run.distance}',
          textAlign: TextAlign.center, style: T.label);
    }
    return Row(
      children: [
        for (var ci = 0; ci < gc.kCities.length; ci++) ...[
          if (ci > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('›', style: T.bodyDim.copyWith(fontSize: 13)),
            ),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (si) {
                    final done = ci < run.cityIndex || (ci == run.cityIndex && si < run.serviceIndex);
                    final here = ci == run.cityIndex && si == run.serviceIndex;
                    final boss = si == 2;
                    return Container(
                      width: here ? 9 : 6,
                      height: here ? 9 : 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? T.good
                            : here
                                ? T.brass
                                : Colors.transparent,
                        border: Border.all(
                          color: done ? T.good : (here ? T.brass : (boss ? T.bad : T.line)),
                          width: 1.4,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Text(
                  gc.kCities[ci].name.split(' ').first.toUpperCase(),
                  style: T.label.copyWith(
                    fontSize: 9.5,
                    color: ci == run.cityIndex ? T.ink : T.dim.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.run});

  final gc.RunState run;

  @override
  Widget build(BuildContext context) {
    final pct = run.target == 0 ? 0.0 : (run.score / run.target).clamp(0.0, 1.0);
    final hit = run.score >= run.target;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CountUpScore(value: run.score, size: 40, color: hit ? T.good : T.brass),
            Padding(
              padding: const EdgeInsets.only(bottom: 5, left: 6),
              child: Text('/ ${formatScore(run.target)}', style: T.bodyDim.copyWith(fontSize: 15)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: Motion.countUp,
            curve: Motion.countUpCurve,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 7,
              backgroundColor: T.panel2,
              valueColor: AlwaysStoppedAnimation(hit ? T.good : T.brass),
            ),
          ),
        ),
      ],
    );
  }
}

class _UtensilRack extends StatelessWidget {
  const _UtensilRack({required this.run});

  final gc.RunState run;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: Row(
      children: List.generate(run.utensilSlots, (i) {
        final u = i < run.utensils.length ? run.utensils[i] : null;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == run.utensilSlots - 1 ? 0 : 5),
            decoration: BoxDecoration(
              color: u == null ? Colors.transparent : T.panel2,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: u == null ? T.line : T.rarityColor(u.rarity),
                width: u == null ? 1 : 1.6,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              u?.name ?? '—',
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 8.5,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: u == null ? T.dim.withValues(alpha: 0.5) : T.ink,
              ),
            ),
          ),
        );
      }),
    ),
  );
}

/// Live dish preview. Shows the real `scoreDish` output, so it can never disagree with COOK.
class _PreviewBar extends StatelessWidget {
  const _PreviewBar({required this.preview, required this.blocker, required this.error});

  final gc.ScoreResult? preview;
  final String? blocker;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final message = error ?? blocker;
    if (message != null) {
      return _Panel(
        border: T.bad,
        child: Text(message, textAlign: TextAlign.center, style: T.body.copyWith(color: T.bad)),
      );
    }
    if (preview == null) {
      return _Panel(
        child: Text('Tap 1–5 ingredients', textAlign: TextAlign.center, style: T.bodyDim),
      );
    }
    final p = preview!;
    return _Panel(
      border: T.brass,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(gc.kGenericNames[p.pattern] ?? p.pattern, style: T.dish(17)),
          const SizedBox(height: 3),
          Text(
            '${formatScore(p.flavor.round())} flavor × ${_trim(p.heat)} heat',
            style: T.bodyDim.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(formatScore(p.score), style: T.score(26)),
        ],
      ),
    );
  }
}

String _trim(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

/// Post-cook breakdown, mirroring the web build's result toast.
class _DishToast extends StatelessWidget {
  const _DishToast({required this.result, required this.cityId});

  final gc.ScoreResult result;
  final String cityId;

  @override
  Widget build(BuildContext context) {
    final dish = gc.kDishNames[cityId]?[result.pattern] ?? result.pattern;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: 0.9 + 0.1 * t, child: Opacity(opacity: t.clamp(0, 1), child: child)),
      child: _Panel(
        border: T.brass,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dish, style: T.dish(19)),
            Text(gc.kGenericNames[result.pattern] ?? '', style: T.label),
            const SizedBox(height: 4),
            Text('+${formatScore(result.score)}', style: T.score(30)),
            const SizedBox(height: 4),
            ...result.steps.skip(1).take(4).map(
              (s) => Text(
                s.text,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: s.cls == 'mult' ? T.bad : T.dim,
                  fontWeight: s.cls == 'mult' ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.border});

  final Widget child;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 74),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: T.panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: border ?? T.line, width: border == null ? 1 : 1.5),
    ),
    child: child,
  );
}

class _Hand extends StatelessWidget {
  const _Hand({
    required this.run,
    required this.selected,
    required this.keyFor,
    required this.enabled,
    required this.onTap,
  });

  final gc.RunState run;
  final List<int> selected;
  final GlobalKey Function(int) keyFor;
  final bool enabled;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Two rows of four rather than one row of eight. Eight across a phone forced cards down
    // to ~55px — too small to read a rank and an ingredient name at a glance, which is the
    // one thing the player does constantly. Halving the columns roughly doubles the card and
    // spends the vertical space the layout had going spare.
    const gap = 7.0;
    final cardW = ((width - 24 - gap * 3) / 4).clamp(56.0, 108.0);
    final rows = <List<int>>[];
    for (var i = 0; i < run.hand.length; i += 4) {
      rows.add([for (var j = i; j < i + 4 && j < run.hand.length; j++) j]);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: EdgeInsets.only(bottom: row == rows.last ? 0 : gap),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final i in row)
                  Padding(
                    padding: EdgeInsets.only(right: i == row.last ? 0 : gap),
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('${run.hand[i].id}_$i'),
                      tween: Tween(begin: 0, end: 1),
                      duration: Motion.deal,
                      // stagger the deal across the whole hand, not per row
                      curve: Interval(
                        (i / run.hand.length) * 0.45,
                        1,
                        curve: Curves.easeOutCubic,
                      ),
                      builder: (context, t, child) => Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 30 * (1 - t)),
                          child: child,
                        ),
                      ),
                      child: IngredientCard(
                        key: keyFor(i),
                        card: run.hand[i],
                        width: cardW,
                        selected: selected.contains(i),
                        debuffed: run.critic?.debuff == run.hand[i].family,
                        onTap: enabled ? () => onTap(i) : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.cooksLeft,
    required this.swapsLeft,
    required this.canCook,
    required this.canSwap,
    required this.onCook,
    required this.onSwap,
  });

  final int cooksLeft;
  final int swapsLeft;
  final bool canCook;
  final bool canSwap;
  final VoidCallback onCook;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        flex: 3,
        child: PressableButton(
          enabled: canCook,
          onTap: onCook,
          height: 56,
          child: Text(
            'COOK  ($cooksLeft)',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: PressableButton(
          enabled: canSwap,
          onTap: onSwap,
          filled: false,
          height: 56,
          child: Text(
            'SWAP  ($swapsLeft)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
        ),
      ),
    ],
  );
}

/// Cards arcing from the hand into the dish panel, then popping out of existence.
///
/// Deliberately short (340ms) and overlapping the count-up rather than preceding it: the
/// point is to link cause and effect, not to make the player wait to see their score.
class _FlyingCards extends StatefulWidget {
  const _FlyingCards({required this.cards, required this.target, required this.onDone});

  final List<(Offset from, gc.Card card, double width)> cards;
  final Offset target;
  final VoidCallback onDone;

  @override
  State<_FlyingCards> createState() => _FlyingCardsState();
}

class _FlyingCardsState extends State<_FlyingCards> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  )..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Stack(
          children: [
            for (var i = 0; i < widget.cards.length; i++)
              Builder(builder: (context) {
                final (from, card, width) = widget.cards[i];
                // stagger so the dish assembles rather than teleporting as a block
                final delay = i * 0.11;
                final t = ((_c.value - delay) / (1 - delay)).clamp(0.0, 1.0);
                final eased = Curves.easeInBack.transform(t);
                final pos = Offset.lerp(from, widget.target - Offset(width / 2, width * 0.7), eased)!;
                return Positioned(
                  left: pos.dx,
                  top: pos.dy,
                  child: Opacity(
                    opacity: 1 - Curves.easeIn.transform(t),
                    child: Transform.scale(
                      scale: 1 - 0.45 * eased,
                      child: Transform.rotate(
                        angle: (i.isEven ? 1 : -1) * 0.22 * eased,
                        child: IngredientCard(card: card, width: width, selected: true),
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    ),
  );
}

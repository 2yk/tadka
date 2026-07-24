/// The juice layer: count-up ticker, particle bursts, screen shake.
///
/// Implements DESIGN-SYSTEM.md §Motion. The build spec calls the score count-up "the one
/// piece of juice M0 keeps — it's load-bearing for fun", so this is product, not polish.
///
/// Every effect here checks [MediaQuery.disableAnimations] and degrades to a plain opacity
/// fade or an instant value, per the design system's reduced-motion rule.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Score counter that eases to a new value and pops on landing.
class CountUpScore extends StatefulWidget {
  const CountUpScore({
    required this.value,
    required this.size,
    this.color = T.brass,
    this.onArrive,
    super.key,
  });

  final int value;
  final double size;
  final Color color;
  final VoidCallback? onArrive;

  @override
  State<CountUpScore> createState() => _CountUpScoreState();
}

class _CountUpScoreState extends State<CountUpScore> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.countUp);
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  int _from = 0;
  int _to = 0;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.value;
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _pop.forward(from: 0);
        widget.onArrive?.call();
      }
    });
  }

  @override
  void didUpdateWidget(CountUpScore old) {
    super.didUpdateWidget(old);
    if (widget.value != _to) {
      _from = _current;
      _to = widget.value;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _c.value = 1;
        widget.onArrive?.call();
      } else {
        _c.forward(from: 0);
      }
    }
  }

  int get _current {
    final t = Motion.countUpCurve.transform(_c.value);
    return (_from + (_to - _from) * t).round();
  }

  @override
  void dispose() {
    _c.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_c, _pop]),
      builder: (context, _) {
        // 1.0 -> 1.12 -> 1.0
        final p = _pop.value;
        final scale = 1 + 0.12 * math.sin(p * math.pi);
        return Transform.scale(
          scale: scale,
          child: Text(
            _fmt(_current),
            style: T.score(widget.size).copyWith(color: widget.color),
          ),
        );
      },
    );
  }
}

/// Compact score formatting — runs reach the billions in Endless, and a 12-digit number
/// destroys the layout on a phone.
String _fmt(num n) {
  if (n < 1000) return '$n';
  if (n < 1e6) return n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  if (n < 1e9) return '${(n / 1e6).toStringAsFixed(n < 1e7 ? 2 : 1)}M';
  if (n < 1e12) return '${(n / 1e9).toStringAsFixed(n < 1e10 ? 2 : 1)}B';
  if (n < 1e15) return '${(n / 1e12).toStringAsFixed(1)}T';
  return n.toStringAsExponential(2);
}

String formatScore(num n) => _fmt(n);

/// Shakes its child. Magnitude scales with the multiplier, per the motion spec.
class ShakeBox extends StatefulWidget {
  const ShakeBox({required this.controller, required this.child, super.key});

  final ShakeController controller;
  final Widget child;

  @override
  State<ShakeBox> createState() => _ShakeBoxState();
}

class ShakeController extends ChangeNotifier {
  double _pixels = 0;
  int _token = 0;

  /// Trigger a shake sized for [multiplier] (the dish's total heat multiplier).
  void shake(double multiplier) {
    _pixels = Motion.shakePixels(multiplier);
    _token++;
    notifyListeners();
  }
}

class _ShakeBoxState extends State<ShakeBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.shake);
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onShake);
  }

  void _onShake() {
    if (!mounted) return;
    if (widget.controller._token == _seen) return;
    _seen = widget.controller._token;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onShake);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        if (_c.isDismissed) return child!;
        final amp = widget.controller._pixels * (1 - _c.value);
        final dx = math.sin(_c.value * math.pi * 6) * amp;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

class _P {
  _P(this.origin, this.angle, this.dist, this.color, this.size, this.born);

  final Offset origin;
  final double angle;
  final double dist;
  final Color color;
  final double size;
  final Duration born;
}

class _Ring {
  _Ring(this.origin, this.color, this.born);

  final Offset origin;
  final Color color;
  final Duration born;
}

/// Full-screen particle layer. Bursts and rings are requested in global coordinates.
class ParticleField extends StatefulWidget {
  const ParticleField({required this.controller, required this.child, super.key});

  final ParticleController controller;
  final Widget child;

  @override
  State<ParticleField> createState() => _ParticleFieldState();
}

class ParticleController extends ChangeNotifier {
  final List<({Offset at, Color color})> _pending = [];
  final List<({Offset at, Color color})> _pendingRings = [];

  /// Request a burst at a global position.
  void burst(Offset globalPosition, Color color) {
    _pending.add((at: globalPosition, color: color));
    notifyListeners();
  }

  /// Request an expanding shockwave ring — the payoff mark for a landed score.
  void ring(Offset globalPosition, Color color) {
    _pendingRings.add((at: globalPosition, color: color));
    notifyListeners();
  }
}

class _ParticleFieldState extends State<ParticleField> with SingleTickerProviderStateMixin {
  /// Created on first use, NOT `late final`: a lazy-final first touched in dispose()
  /// (possible when no effect ever fired) would run createTicker during teardown, where
  /// the ancestor lookup it does is illegal.
  Ticker? _ticker;
  final List<_P> _live = [];
  final List<_Ring> _rings = [];
  final _rng = math.Random();
  Duration _now = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_drain);
  }

  void _drain() {
    if (!mounted) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      widget.controller._pending.clear();
      widget.controller._pendingRings.clear();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    for (final p in widget.controller._pending) {
      final local = box?.globalToLocal(p.at) ?? p.at;
      final n = Motion.burstMin + _rng.nextInt(Motion.burstMax - Motion.burstMin + 1);
      for (var i = 0; i < n; i++) {
        _live.add(_P(
          local,
          _rng.nextDouble() * math.pi * 2,
          18 + _rng.nextDouble() * 36,
          p.color,
          4 + _rng.nextDouble() * 4,
          _now,
        ));
      }
    }
    widget.controller._pending.clear();
    for (final r in widget.controller._pendingRings) {
      final local = box?.globalToLocal(r.at) ?? r.at;
      _rings.add(_Ring(local, r.color, _now));
    }
    widget.controller._pendingRings.clear();

    // The ticker runs only while something is alive. An always-on ticker schedules frames
    // forever, which drains battery repainting nothing and hangs pumpAndSettle in tests.
    if ((_live.isNotEmpty || _rings.isNotEmpty) && !(_ticker?.isActive ?? false)) {
      _now = Duration.zero;
      for (var i = 0; i < _live.length; i++) {
        _live[i] = _P(_live[i].origin, _live[i].angle, _live[i].dist, _live[i].color,
            _live[i].size, Duration.zero);
      }
      for (var i = 0; i < _rings.length; i++) {
        _rings[i] = _Ring(_rings[i].origin, _rings[i].color, Duration.zero);
      }
      (_ticker ??= createTicker(_tick)).start();
    }
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    _live.removeWhere((p) => (elapsed - p.born) > Motion.burst);
    _rings.removeWhere((r) => (elapsed - r.born) > Motion.ring);
    if (_live.isEmpty && _rings.isEmpty) _ticker?.stop();
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_drain);
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_live.isNotEmpty || _rings.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ParticlePainter(_live, _rings, _now)),
            ),
          ),
      ],
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.particles, this.rings, this.now);

  final List<_P> particles;
  final List<_Ring> rings;
  final Duration now;

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in rings) {
      final t = ((now - r.born).inMilliseconds / Motion.ring.inMilliseconds).clamp(0.0, 1.0);
      final e = Curves.easeOutCubic.transform(t);
      final alpha = (1 - t) * 0.85;
      canvas.drawCircle(
        r.origin,
        14 + 86 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (4.5 * (1 - t)).clamp(0.8, 4.5)
          ..color = r.color.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        r.origin,
        6 + 52 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = r.color.withValues(alpha: alpha * 0.45),
      );
    }
    for (final p in particles) {
      final t = ((now - p.born).inMilliseconds / Motion.burst.inMilliseconds).clamp(0.0, 1.0);
      final eased = 1 - math.pow(1 - t, 2).toDouble();
      final d = p.dist * eased;
      final pos = p.origin + Offset(math.cos(p.angle) * d, math.sin(p.angle) * d);
      canvas.drawCircle(
        pos,
        p.size * (1 - 0.65 * t) / 2,
        Paint()..color = p.color.withValues(alpha: 1 - t),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

/// Haptics tied to how big the dish was. Concept doc lists this in the M2 juice checklist;
/// it costs nothing here and does a lot of work selling the multiplier moment on a phone.
void hapticForScore(double heatMultiplier) {
  if (heatMultiplier >= 4) {
    HapticFeedback.heavyImpact();
  } else if (heatMultiplier >= 2) {
    HapticFeedback.mediumImpact();
  } else {
    HapticFeedback.selectionClick();
  }
}

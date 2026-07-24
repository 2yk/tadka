/// Embers drifting up the start screen — the night market's fire, felt not shown.
///
/// A fixed constellation of motes rises slowly with a sinusoidal sway. Positions come from
/// a fixed-seed Random so the field is deterministic; ambient-gated, so under reduced
/// motion or in tests it renders one static scatter of faint sparks.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';
import 'ambient.dart';

class _Mote {
  _Mote(math.Random r)
      : x = r.nextDouble(),
        y0 = r.nextDouble(),
        speed = 0.014 + r.nextDouble() * 0.022,
        size = 1.3 + r.nextDouble() * 2.2,
        swayAmp = 0.008 + r.nextDouble() * 0.02,
        phase = r.nextDouble() * math.pi * 2,
        color = switch (r.nextInt(5)) {
          0 => T.brassLight,
          1 => T.spicy,
          _ => T.brass,
        },
        alpha = 0.10 + r.nextDouble() * 0.20;

  final double x, y0, speed, size, swayAmp, phase, alpha;
  final Color color;
}

class EmberField extends StatefulWidget {
  const EmberField({this.count = 16, super.key});

  final int count;

  @override
  State<EmberField> createState() => _EmberFieldState();
}

class _EmberFieldState extends State<EmberField> with TickerProviderStateMixin {
  late final List<_Mote> _motes = () {
    final r = math.Random(7);
    return List.generate(widget.count, (_) => _Mote(r));
  }();

  Ticker? _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = ambientEnabled(context);
    if (animate && _ticker == null) {
      _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)..start();
    } else if (!animate && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _EmberPainter(_motes, _time),
            size: Size.infinite,
          ),
        ),
      );
}

class _EmberPainter extends CustomPainter {
  _EmberPainter(this.motes, this.time) : super(repaint: time);

  final List<_Mote> motes;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    for (final m in motes) {
      // Wraps top-to-bottom; the 1.1 overshoot keeps respawns off-screen.
      final y = 1.1 - ((m.y0 + t * m.speed) % 1.2);
      final x = m.x + math.sin(t * 0.5 + m.phase) * m.swayAmp;
      // Fade in near the bottom, out near the top.
      final fade = (y * 6).clamp(0.0, 1.0) * ((1.05 - y) * 5).clamp(0.0, 1.0);
      if (fade <= 0) continue;
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        m.size,
        Paint()..color = m.color.withValues(alpha: m.alpha * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_EmberPainter old) => old.motes != motes;
}

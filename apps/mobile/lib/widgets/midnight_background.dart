/// The living sky behind the whole app.
///
/// A fragment shader paints a slow silk-smoke swirl in the Midnight Bazaar palette — the
/// single biggest "this is a game, not a form" signal on screen, borrowed from the genre's
/// best (Balatro's swirl does exactly this job). It mounts once in [GameRoot] so the world
/// persists across screen transitions instead of resetting with each phase.
///
/// Degrades in order: no ambient motion → the same shader frozen on one frame; no shader
/// support at all (or still loading) → a plain vertical gradient. Both fallbacks are what
/// the flat background used to be, so nothing is ever worse than before.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'ambient.dart';

class MidnightBackground extends StatefulWidget {
  const MidnightBackground({required this.child, this.intensity = 1.0, super.key});

  final Widget child;

  /// 0–1 dial on the colored accents (umami bloom, brass pool, embers). The night base is
  /// constant so UI contrast never depends on this.
  final double intensity;

  @override
  State<MidnightBackground> createState() => _MidnightBackgroundState();
}

class _MidnightBackgroundState extends State<MidnightBackground> with TickerProviderStateMixin {
  /// One compile per process; every instance shares it.
  static Future<ui.FragmentProgram>? _programLoader;

  ui.FragmentShader? _shader;
  Ticker? _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _programLoader ??= ui.FragmentProgram.fromAsset('shaders/midnight_bazaar.frag');
    _programLoader!.then((program) {
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    }).catchError((Object _) {
      // No runtime-shader support here (old GPU, headless test) — keep the gradient.
    });
  }

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
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: shader == null
                ? const DecoratedBox(
                    key: ValueKey('midnight_fallback'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1A1531), Color(0xFF171426), Color(0xFF120F1E)],
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: _SilkPainter(shader, _time, widget.intensity),
                    isComplex: true,
                    willChange: _ticker != null,
                  ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _SilkPainter extends CustomPainter {
  _SilkPainter(this.shader, this.time, this.intensity) : super(repaint: time);

  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, intensity);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SilkPainter old) => old.shader != shader || old.intensity != intensity;
}

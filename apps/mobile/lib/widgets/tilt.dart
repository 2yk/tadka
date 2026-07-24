/// Real 3D perspective on flat things — the card-game trick for looking dimensional.
///
/// Two motions compose here: a slow idle sway (each card breathes on its own phase, so the
/// hand reads as a living fan rather than a printed sheet) and a press tilt toward the
/// finger with a springy return. A moving gloss highlight rides the tilt, which is what
/// sells the surface as glossy card stock catching lantern light.
///
/// The sway is ambient and runs through [ambientEnabled]; the press tilt is finite and
/// always on, because it is feedback, not decoration. Perspective transforms are paint-only
/// in Flutter, so layout and hit-testing stay exactly where they were.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'ambient.dart';

class Tilt3D extends StatefulWidget {
  const Tilt3D({
    required this.child,
    this.phase = 0.0,
    this.maxTilt = 0.14,
    this.swayTilt = 0.030,
    this.glossRadius,
    super.key,
  });

  final Widget child;

  /// Offsets this instance's sway so neighbours never move in lockstep.
  final double phase;

  /// Radians of press tilt at the card's edge.
  final double maxTilt;

  /// Radians of idle sway amplitude.
  final double swayTilt;

  /// Rounds the gloss overlay to the child's corners. Null disables the gloss.
  final BorderRadius? glossRadius;

  @override
  State<Tilt3D> createState() => _Tilt3DState();
}

class _Tilt3DState extends State<Tilt3D> with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    reverseDuration: const Duration(milliseconds: 420),
  );
  late final CurvedAnimation _pressCurve = CurvedAnimation(
    parent: _press,
    curve: Curves.easeOut,
    // The spring-back overshoot is most of the "physical object" feel.
    reverseCurve: Curves.easeOutBack.flipped,
  );

  /// Target tilt while pressed, in radians. Updated on pointer move.
  final ValueNotifier<Offset> _target = ValueNotifier(Offset.zero);

  Ticker? _sway;
  final ValueNotifier<double> _time = ValueNotifier(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = ambientEnabled(context);
    if (animate && _sway == null) {
      _sway = createTicker((d) => _time.value = d.inMicroseconds / 1e6)..start();
    } else if (!animate && _sway != null) {
      _sway!.dispose();
      _sway = null;
    }
  }

  @override
  void dispose() {
    _sway?.dispose();
    _pressCurve.dispose();
    _press.dispose();
    _target.dispose();
    _time.dispose();
    super.dispose();
  }

  void _aim(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return;
    final local = box.globalToLocal(globalPosition);
    final nx = ((local.dx / box.size.width) * 2 - 1).clamp(-1.0, 1.0);
    final ny = ((local.dy / box.size.height) * 2 - 1).clamp(-1.0, 1.0);
    // Tilt the pressed corner AWAY, like pushing on real card stock.
    _target.value = Offset(ny * widget.maxTilt, -nx * widget.maxTilt);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (e) {
        _aim(e.position);
        _press.forward();
      },
      onPointerMove: (e) => _aim(e.position),
      onPointerUp: (_) => _press.reverse(),
      onPointerCancel: (_) => _press.reverse(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_pressCurve, _target, _time]),
        builder: (context, child) {
          final t = _time.value;
          final swayOn = _sway != null ? 1.0 : 0.0;
          final idleRx = widget.swayTilt * math.sin(t * 1.15 + widget.phase) * swayOn;
          final idleRy = widget.swayTilt * 1.3 * math.cos(t * 0.9 + widget.phase * 1.7) * swayOn;
          final k = _pressCurve.value;
          final rx = idleRx + _target.value.dx * k;
          final ry = idleRy + _target.value.dy * k;

          Widget out = child!;
          final radius = widget.glossRadius;
          if (radius != null) {
            // Lantern-light gloss that slides opposite the tilt.
            out = Stack(
              children: [
                out,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: radius,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-ry * 7, -1.0 - rx * 7),
                            end: Alignment(ry * 7, 1.0 + rx * 7),
                            colors: [
                              Colors.white.withValues(alpha: 0.05 + 0.09 * k),
                              Colors.white.withValues(alpha: 0.0),
                              Colors.black.withValues(alpha: 0.04 + 0.06 * k),
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateX(rx)
              ..rotateY(ry)
              ..scaleByDouble(1.0 + 0.02 * k, 1.0 + 0.02 * k, 1.0, 1.0),
            child: out,
          );
        },
        child: widget.child,
      ),
    );
  }
}

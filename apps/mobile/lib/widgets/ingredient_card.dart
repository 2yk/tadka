/// The parchment ticket card — the game's signature object.
///
/// Geometry follows DESIGN-SYSTEM.md §Components: parchment face, inner keyline, family band
/// with a scalloped ticket edge, rank numeral top-left, family caps top-right, sunburst behind
/// a centred motif, hairline rule above the name footer. Selected state lifts 6px with a brass
/// outer glow.
///
/// The centred motif is the family emoji rather than the asset pack's illustrated icons — the
/// design system already calls those placeholders a human artist upgrades, and shipping emoji
/// keeps the app fully offline with no asset pipeline.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../theme.dart';

/// The "sunburst" — the one signature motif, behind every ingredient, badge and the icon.
class _SunburstPainter extends CustomPainter {
  const _SunburstPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.62;
    final paint = Paint()..color = color.withValues(alpha: 0.16);
    const rays = 16;
    for (var i = 0; i < rays; i++) {
      final a0 = (i * 2 * math.pi / rays) - 0.055;
      final a1 = (i * 2 * math.pi / rays) + 0.055;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a0), c.dy + r * math.sin(a0))
        ..lineTo(c.dx + r * math.cos(a1), c.dy + r * math.sin(a1))
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(c, size.width * 0.20, Paint()..color = color.withValues(alpha: 0.22));
  }

  @override
  bool shouldRepaint(_SunburstPainter old) => old.color != color;
}

/// The scalloped bottom edge of the family band, which gives the card its ticket identity.
class _ScallopClipper extends CustomClipper<Path> {
  const _ScallopClipper();

  @override
  Path getClip(Size size) {
    const scallop = 5.0;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - scallop);
    final count = (size.width / (scallop * 2)).floor().clamp(1, 60);
    final step = size.width / count;
    for (var i = count - 1; i >= 0; i--) {
      path.arcToPoint(
        Offset(i * step, size.height - scallop),
        radius: const Radius.circular(scallop),
        clockwise: true,
      );
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_ScallopClipper oldClipper) => false;
}

class IngredientCard extends StatelessWidget {
  const IngredientCard({
    required this.card,
    this.selected = false,
    this.debuffed = false,
    this.onTap,
    this.width = 92,
    super.key,
  });

  final gc.Card card;
  final bool selected;

  /// Rendered greyed with a strike when the active critic zeroes this family, so the player
  /// can see the debuff on the card instead of discovering it in the score breakdown.
  final bool debuffed;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final fam = T.family[card.family] ?? T.umami;
    final famDark = T.familyDark[card.family] ?? T.umamiDark;
    final height = width * 1.4;
    final bandH = height * 0.30;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, selected ? -10 : 0, 0),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: T.parch,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? T.brass : T.parchDark, width: selected ? 3 : 2),
          boxShadow: [
            if (selected)
              BoxShadow(color: T.brass.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1)
            else
              BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 7, offset: const Offset(0, 3)),
          ],
        ),
        child: Opacity(
          opacity: debuffed ? 0.45 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                // family band with scalloped ticket edge
                ClipPath(
                  clipper: const _ScallopClipper(),
                  child: Container(
                    height: bandH,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [fam, famDark],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 3, 6, 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${card.rank}',
                            style: TextStyle(
                              fontFamily: T.display,
                              fontWeight: FontWeight.w700,
                              fontSize: width * 0.26,
                              color: T.cream,
                              height: 1.0,
                            ),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              card.family.toUpperCase(),
                              style: TextStyle(
                                fontSize: width * 0.085,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: T.cream.withValues(alpha: 0.92),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: width * 0.62,
                                height: width * 0.62,
                                child: CustomPaint(painter: _SunburstPainter(fam)),
                              ),
                              Text(
                                card.prized ? '✨' : (T.familyEmoji[card.family] ?? '🍽'),
                                style: TextStyle(fontSize: width * 0.32),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(height: 1, color: T.parchDark),
                      const SizedBox(height: 3),
                      // Ingredient names run long ("Condensed Milk", "Fermented Lime") and a
                      // fixed size breaks them mid-word on a narrow card. Scale to fit instead,
                      // so wrapping only ever happens at spaces.
                      SizedBox(
                        height: width * 0.30,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: width * 1.6),
                            child: Text(
                              card.display,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: T.display,
                                fontWeight: FontWeight.w600,
                                fontSize: width * 0.145,
                                color: T.inkDark,
                                height: 1.12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (debuffed)
                  Center(
                    child: Transform.rotate(
                      angle: -0.35,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        color: T.bad.withValues(alpha: 0.85),
                        child: const Text(
                          'DEBUFFED',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

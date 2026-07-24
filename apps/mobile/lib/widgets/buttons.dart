/// Buttons with physical press feedback.
///
/// DESIGN-SYSTEM.md specifies COOK as a brass vertical gradient with a 4px darker bottom
/// edge "(physical press feel)". A static gradient only half-delivers that: the edge reads
/// as depth, so the button has to actually depress when touched. On press the face slides
/// down into its own shadow and the edge collapses, which is what makes a tap feel landed
/// on a phone where there's no cursor state to lean on.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class PressableButton extends StatefulWidget {
  const PressableButton({
    required this.child,
    required this.onTap,
    this.enabled = true,
    this.filled = true,
    this.glow = false,
    this.height = 54,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool enabled;

  /// Brass gradient when true, outlined when false.
  final bool filled;

  /// Brass halo behind the face while enabled — reserved for the primary action, so the
  /// one button that advances the game is always the brightest thing near the thumb.
  final bool glow;
  final double height;

  @override
  State<PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<PressableButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    const edge = 4.0;
    final depth = _down ? edge : 0.0;
    return Opacity(
      opacity: widget.enabled ? 1 : 0.4,
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => _set(true) : null,
        onTapCancel: widget.enabled ? () => _set(false) : null,
        onTapUp: widget.enabled ? (_) => _set(false) : null,
        onTap: widget.enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap();
              }
            : null,
        child: SizedBox(
          height: widget.height + edge,
          child: Stack(
            children: [
              // the fixed bottom edge the face presses into
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: widget.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.filled ? T.brassDark : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: widget.filled
                        ? null
                        : Border.all(color: const Color(0xFF443C68), width: 2),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 60),
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: depth,
                height: widget.height,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: widget.filled
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [T.brassLight, T.brass],
                          )
                        : null,
                    color: widget.filled ? null : T.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: widget.filled
                        ? null
                        : Border.all(color: const Color(0xFF443C68), width: 2),
                    boxShadow: [
                      if (widget.glow && widget.enabled && !_down)
                        BoxShadow(
                          color: T.brass.withValues(alpha: 0.40),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: widget.filled ? T.inkDark : T.ink),
                    child: widget.child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

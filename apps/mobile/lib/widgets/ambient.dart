/// The gate for ambient — i.e. endless — animation.
///
/// Triggered juice (bursts, count-ups, shakes) is finite and self-limits. Ambient effects
/// (the shader sky, card sway, foil shimmer, ember drift) repeat forever, and anything that
/// repeats forever schedules frames forever — which hangs `pumpAndSettle` in every widget
/// test and burns battery repainting a screen nobody is touching. So all of it runs through
/// this one gate:
///
/// * under `flutter test` the gate is closed and every ambient effect renders one static
///   frame — the suite's pumpAndSettle calls keep settling;
/// * when the platform asks for reduced motion the gate is closed too, per the design
///   system's rule that motion degrades to stillness, not absence.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

/// Test override: force the gate open or closed regardless of environment.
/// Left null in production, where the environment decides.
bool? debugAmbientOverride;

final bool _inFlutterTest = () {
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } on Object {
    return false;
  }
}();

/// Whether ambient animation may run right now.
///
/// Call from `didChangeDependencies` (it reads MediaQuery) and start or stop tickers on the
/// answer — never start a repeating controller without consulting this.
bool ambientEnabled(BuildContext context) {
  final override = debugAmbientOverride;
  if (override != null) return override;
  if (_inFlutterTest) return false;
  return !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
}

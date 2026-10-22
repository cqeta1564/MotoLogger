import 'package:flutter/widgets.dart';

/// Short, interruptible motion; accessibility settings always take precedence.
abstract final class AppMotion {
  static Duration duration(BuildContext context, [int milliseconds = 260]) {
    final media = MediaQuery.of(context);
    return media.disableAnimations || media.accessibleNavigation
        ? Duration.zero
        : Duration(milliseconds: milliseconds);
  }

  /// Apple-style responsive physics spring curve (matches iOS interactive spring: response 0.35s, damping 0.86).
  static const springCurve = Cubic(0.16, 1.0, 0.3, 1.0);
  static const curve = springCurve;
}

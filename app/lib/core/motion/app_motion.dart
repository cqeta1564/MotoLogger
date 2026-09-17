import 'package:flutter/widgets.dart';

/// Short, interruptible motion; accessibility settings always take precedence.
abstract final class AppMotion {
  static Duration duration(BuildContext context, [int milliseconds = 260]) {
    final media = MediaQuery.of(context);
    return media.disableAnimations || media.accessibleNavigation
        ? Duration.zero
        : Duration(milliseconds: milliseconds);
  }

  static const curve = Curves.easeOutCubic;
}

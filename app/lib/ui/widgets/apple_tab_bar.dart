import 'package:flutter/cupertino.dart';
import '../../core/theme/app_theme.dart';
import '../../core/motion/app_motion.dart';
import 'glass_surface.dart';

/// Shared floating navigation; the fill marks selection inside one material.
class AppleTabBar extends StatelessWidget {
  const AppleTabBar(
      {super.key,
      required this.currentIndex,
      required this.onTabSelected,
      this.isLandscape = false});
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) => GlassSurface(
        radius: 36,
        padding: const EdgeInsets.all(6),
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: AppMotion.duration(context),
              curve: AppMotion.curve,
              alignment: Alignment(currentIndex - 1.0, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                heightFactor: 1,
                child: DecoratedBox(
                  key: const ValueKey('tab-selection'),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3EDFB),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          ),
          Row(children: [
            _tab(context, 0, CupertinoIcons.speedometer, 'Jízda'),
            _tab(context, 1, CupertinoIcons.chart_bar_alt_fill, 'Historie'),
            _tab(context, 2, CupertinoIcons.gear_alt, 'Nastavení'),
          ]),
        ]),
      );

  Widget _tab(BuildContext context, int index, IconData icon, String label) {
    final selected = currentIndex == index;
    final color = selected ? AppTheme.appleBlue : AppTheme.textMuted;
    return Expanded(
        child: Semantics(
      selected: selected,
      button: true,
      label: label,
      child: ExcludeSemantics(
          child: CupertinoButton(
        key: ValueKey('tab-$index'),
        padding: EdgeInsets.zero,
        onPressed: () => onTabSelected(index),
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          width: double.infinity,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
          ]),
        ),
      )),
    ));
  }
}

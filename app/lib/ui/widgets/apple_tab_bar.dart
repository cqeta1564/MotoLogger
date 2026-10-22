import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/motion/app_motion.dart';
import 'glass_surface.dart';

/// Shared floating navigation capsule with true physical spring dynamics.
class AppleTabBar extends StatefulWidget {
  const AppleTabBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    this.isLandscape = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final bool isLandscape;

  @override
  State<AppleTabBar> createState() => _AppleTabBarState();
}

class _AppleTabBarState extends State<AppleTabBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _springController;
  late double _currentOffset;

  static const _springDescription = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 28.0,
  );

  @override
  void initState() {
    super.initState();
    _currentOffset = widget.currentIndex.toDouble();
    _springController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() {
          _currentOffset = _springController.value;
        });
      });
  }

  @override
  void didUpdateWidget(AppleTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _animateTo(widget.currentIndex.toDouble());
    }
  }

  void _animateTo(double target) {
    if (!mounted) return;
    final isReduced = AppMotion.isReducedMotion(context);
    if (isReduced) {
      _springController.stop();
      setState(() {
        _currentOffset = target;
      });
      return;
    }

    final simulation = SpringSimulation(
      _springDescription,
      _currentOffset,
      target,
      _springController.velocity,
    );
    _springController.animateWith(simulation);
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 36,
      padding: const EdgeInsets.all(5),
      child: Stack(
        children: [
          // True Apple sliding capsule: solid white with soft shadow
          Positioned.fill(
            child: Align(
              alignment: Alignment((_currentOffset - 1.0).clamp(-1.0, 1.0), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                heightFactor: 1,
                child: DecoratedBox(
                  key: const ValueKey('tab-selection'),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x18000000),
                        blurRadius: 4,
                        offset: Offset(0, 1.5),
                      ),
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _tab(context, 0, CupertinoIcons.speedometer, 'Jízda'),
              _tab(context, 1, CupertinoIcons.chart_bar_alt_fill, 'Historie'),
              _tab(context, 2, CupertinoIcons.gear_alt, 'Nastavení'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int index, IconData icon, String label) {
    final selected = widget.currentIndex == index;
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
            onPressed: () {
              if (widget.currentIndex != index) {
                HapticFeedback.selectionClick();
              }
              widget.onTabSelected(index);
              _animateTo(index.toDouble());
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 22),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Authentic Apple iOS Tab Bar.
///
/// Features:
/// - Frosted / System Grouped Gray background (#F2F2F7)
/// - Precision hairline top divider (#E5E5EA)
/// - SF Pro typography with bold active state and muted inactive state
/// - Built-in tactile haptic feedback on tab changes
/// - Optional trailing action (e.g. "Zamknout" for Dashboard)
class AppleTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final Widget? trailingAction;
  final bool isLandscape;

  const AppleTabBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    this.trailingAction,
    this.isLandscape = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: isLandscape ? 56 : 70,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F2F7),
        border: Border(
          top: BorderSide(color: Color(0xFFE5E5EA), width: 1.0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildTabItem(
              icon: Icons.two_wheeler_rounded,
              label: 'Jízda',
              index: 0,
            ),
            _buildTabItem(
              icon: Icons.bar_chart_rounded,
              label: 'Historie',
              index: 1,
            ),
            _buildTabItem(
              icon: Icons.settings_rounded,
              label: 'Nastavení',
              index: 2,
            ),
            if (trailingAction != null) trailingAction!,
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isActive = currentIndex == index;
    final color = isActive ? Colors.black : const Color(0xFF8E8E93);

    return Expanded(
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () {
          HapticFeedback.selectionClick();
          onTabSelected(index);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -0.2,
                fontFamily: '-apple-system',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

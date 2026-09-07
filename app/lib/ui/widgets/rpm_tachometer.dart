import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class RpmTachometer extends StatelessWidget {
  final int currentRpm;
  final int maxRpm;
  final int redlineRpm;

  const RpmTachometer({
    super.key,
    required this.currentRpm,
    this.maxRpm = 14000,
    this.redlineRpm = 11500,
  });

  @override
  Widget build(BuildContext context) {
    final double fraction = (currentRpm / maxRpm).clamp(0.0, 1.0);
    final bool isShiftLight = currentRpm >= redlineRpm;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isShiftLight ? AppTheme.danger.withOpacity(0.2) : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isShiftLight ? AppTheme.danger : AppTheme.surfaceLight,
          width: isShiftLight ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    currentRpm.toString(),
                    style: TextStyle(
                      color: isShiftLight ? AppTheme.danger : AppTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'RPM',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (isShiftLight)
                const Text(
                  'SHIFT!',
                  style: TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 12,
              backgroundColor: AppTheme.surfaceLight,
              valueColor: AlwaysStoppedAnimation<Color>(
                isShiftLight
                    ? AppTheme.danger
                    : (fraction > 0.75
                        ? AppTheme.accent
                        : (fraction > 0.5 ? AppTheme.warning : AppTheme.success)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

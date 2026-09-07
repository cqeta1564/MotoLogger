import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class GearSpeedWidget extends StatelessWidget {
  final int gear;             // -1 = unknown, 0 = N, 1..6
  final int speedKmh;         // Speed in km/h

  const GearSpeedWidget({
    super.key,
    required this.gear,
    required this.speedKmh,
  });

  @override
  Widget build(BuildContext context) {
    final bool isNeutral = (gear == 0);
    final String gearText = isNeutral ? 'N' : (gear > 0 ? gear.toString() : '-');
    final Color gearColor = isNeutral ? AppTheme.success : AppTheme.textPrimary;

    return Row(
      children: [
        // Gear Badge
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isNeutral ? AppTheme.success.withOpacity(0.5) : AppTheme.surfaceLight,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                gearText,
                style: TextStyle(
                  color: gearColor,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const Text(
                'GEAR',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        // Speed Display
        Expanded(
          child: Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.surfaceLight),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'SPEED',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'KM / H',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  speedKmh.toString(),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 54,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1.0,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

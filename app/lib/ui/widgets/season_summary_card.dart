import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session.dart';

/// Season and all-time aggregate statistics card formatted according to Apple Fitness & Health aesthetic.
class SeasonSummaryCard extends StatelessWidget {
  final SeasonStats stats;
  final int? selectedYear;

  const SeasonSummaryCard({
    super.key,
    required this.stats,
    this.selectedYear,
  });

  String _formatRideCount(int count) {
    if (count == 1) return '1 jízda';
    if (count >= 2 && count <= 4) return '$count jízdy';
    return '$count jízd';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    if (hours == 0) return '$mins min';
    return '$hours h $mins min';
  }

  @override
  Widget build(BuildContext context) {
    final year = selectedYear ?? DateTime.now().year;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with Year & Total Rides badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SEZÓNNÍ SOUHRN',
                    style: TextStyle(
                      color: AppTheme.appleBlack,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      fontFamily: '-apple-system',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sezóna $year • ${_formatRideCount(stats.totalRides)}',
                    style: const TextStyle(
                      color: AppTheme.appleMutedGray,
                      fontSize: 12,
                      fontFamily: '-apple-system',
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.appleBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.two_wheeler_rounded, size: 14, color: AppTheme.appleBlue),
                    const SizedBox(width: 5),
                    Text(
                      '${stats.totalDistanceKm.toStringAsFixed(0)} km',
                      style: const TextStyle(
                        color: AppTheme.appleBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFamily: '-apple-system',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 2x2 Apple Fitness Metric Tiles
          Row(
            children: [
              Expanded(
                child: _buildTile(
                  label: 'Celkový nájezd',
                  value: '${stats.totalDistanceKm.toStringAsFixed(1)} km',
                  icon: Icons.route_rounded,
                  color: AppTheme.appleBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTile(
                  label: 'Čas v sedle',
                  value: _formatDuration(stats.totalDuration),
                  icon: Icons.timer_outlined,
                  color: AppTheme.appleGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildTile(
                  label: 'Rekord náklonu (L / P)',
                  value: stats.totalRides > 0
                      ? '◀ ${stats.maxLeanLeftDeg.toStringAsFixed(1)}° | ${stats.maxLeanRightDeg.toStringAsFixed(1)}° ▶'
                      : '0.0° | 0.0°',
                  icon: Icons.swap_horiz_rounded,
                  color: AppTheme.appleOrange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTile(
                  label: 'Maximální rychlost',
                  value: '${stats.topSpeedKmh.toStringAsFixed(0)} km/h',
                  icon: Icons.speed_rounded,
                  color: AppTheme.appleRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.appleMutedGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: '-apple-system',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.appleBlack,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              fontFamily: '-apple-system',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

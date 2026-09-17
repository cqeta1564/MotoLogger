import 'package:flutter/cupertino.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session.dart';
import 'glass_surface.dart';

/// Opaque ride statistics. Unfiltered history is explicitly an all-time total.
class SeasonSummaryCard extends StatelessWidget {
  const SeasonSummaryCard({super.key, required this.stats, this.selectedYear});
  final SeasonStats stats;
  final int? selectedYear;

  String get _count => stats.totalRides == 1
      ? '1 jízda'
      : stats.totalRides >= 2 && stats.totalRides <= 4
          ? '${stats.totalRides} jízdy'
          : '${stats.totalRides} jízd';
  String _duration(Duration value) => value.inHours == 0
      ? '${value.inMinutes} min'
      : '${value.inHours} h ${value.inMinutes % 60} min';

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ContentGroup(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(CupertinoIcons.chart_bar_alt_fill,
                    color: AppTheme.appleBlue, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        selectedYear == null
                            ? 'CELKOVÝ PŘEHLED'
                            : 'SEZÓNNÍ SOUHRN',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .8))),
              ]),
              const SizedBox(height: 8),
              Text(
                  selectedYear == null
                      ? 'Všechny jízdy · $_count'
                      : 'Sezóna $selectedYear • $_count',
                  style:
                      const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, constraints) {
                final columns =
                    MediaQuery.textScalerOf(context).scale(17) > 23 ? 1 : 2;
                final width =
                    (constraints.maxWidth - (columns - 1) * 16) / columns;
                final metrics = [
                  (
                    'Celkový nájezd',
                    '${stats.totalDistanceKm.toStringAsFixed(1)} km'
                  ),
                  ('Čas v sedle', _duration(stats.totalDuration)),
                  (
                    'Rekord náklonu (L / P)',
                    stats.totalRides > 0
                        ? '${stats.maxLeanLeftDeg.toStringAsFixed(1)}° / ${stats.maxLeanRightDeg.toStringAsFixed(1)}°'
                        : '—'
                  ),
                  ('Maximální rychlost', '${stats.topSpeedKmh.round()} km/h'),
                ];
                return Wrap(spacing: 16, runSpacing: 20, children: [
                  for (final metric in metrics)
                    SizedBox(
                        width: width,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(metric.$1,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.textMuted)),
                              const SizedBox(height: 5),
                              Text(metric.$2,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.5,
                                      fontFeatures: [
                                        FontFeature.tabularFigures()
                                      ])),
                            ])),
                ]);
              }),
            ])),
      );
}

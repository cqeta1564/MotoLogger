import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session.dart';
import '../../models/fused_sample.dart';
import '../../services/database_service.dart';
import '../widgets/gps_track_map_card.dart';
import '../widgets/gg_friction_card.dart';
import '../widgets/glass_surface.dart';

/// Detailed breakdown and telemetry inspection screen for a ride session.
/// Formatted according to Apple Fitness & Health aesthetic.
class SessionDetailScreen extends StatefulWidget {
  final RideSession session;
  final DatabaseService dbService;

  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.dbService,
  });

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late Future<List<FusedSample>> _samplesFuture;

  @override
  void initState() {
    super.initState();
    _samplesFuture = widget.dbService.getSamplesForSession(widget.session.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        leading: const GlassBackButton(),
        title: Text(widget.session.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 22),
            tooltip: 'Exportovat data',
            onPressed: _showExportSheet,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppTheme.appleRed, size: 22),
            tooltip: 'Smazat jízdu',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: FutureBuilder<List<FusedSample>>(
        future: _samplesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CupertinoActivityIndicator(radius: 14));
          }
          if (snapshot.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Data jízdy se nepodařilo načíst.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        PrimaryAction(
                            label: 'Zkusit znovu',
                            onPressed: () => setState(() {
                                  _samplesFuture = widget.dbService
                                      .getSamplesForSession(widget.session.id!);
                                })),
                      ],
                    )));
          }
          final samples = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Apple Summary Card
                _buildSummaryCard(samples),
                const SizedBox(height: 16),

                // GPS Track Trajectory Map Card
                GpsTrackMapCard(samples: samples),
                const SizedBox(height: 16),

                // Post-Ride G-G Friction Diagram Card
                GgFrictionCard(samples: samples),
                const SizedBox(height: 16),

                // Lean Angle Chart
                _buildChartCard(
                  title: 'PRŮBĚH NÁKLONU V ČASE',
                  subtitle: 'Klopení motocyklu v zatáčkách',
                  chart: _buildLeanChart(samples),
                ),
                const SizedBox(height: 16),

                // Speed Chart
                _buildChartCard(
                  title: 'RYCHLOST V ČASE',
                  subtitle: 'Průběh rychlosti během jízdy',
                  chart: _buildSpeedChart(samples),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(List<FusedSample> samples) {
    final s = widget.session;
    final double avgSpeedKmh;
    if (samples.isNotEmpty) {
      final totalSpeed =
          samples.map((e) => e.vehicleSpeedKmh).reduce((a, b) => a + b);
      avgSpeedKmh = totalSpeed / samples.length;
    } else if (s.duration.inSeconds > 5) {
      avgSpeedKmh = s.totalDistanceKm / (s.duration.inSeconds / 3600.0);
    } else {
      avgSpeedKmh = 0.0;
    }

    final metrics = [
      ('Náklon vlevo', '${s.maxLeanLeftDeg.abs().toStringAsFixed(1)}°'),
      ('Náklon vpravo', '${s.maxLeanRightDeg.abs().toStringAsFixed(1)}°'),
      ('Max. rychlost', '${s.topSpeedKmh.round()} km/h'),
      ('Max. přetížení', '${s.maxGForce.toStringAsFixed(2)} G'),
      (
        'Doba jízdy',
        '${s.duration.inMinutes} min ${s.duration.inSeconds % 60} s'
      ),
      ('Průměrná rychlost', '${avgSpeedKmh.round()} km/h'),
      ('Vzdálenost', '${s.totalDistanceKm.toStringAsFixed(2)} km'),
    ];
    return ContentGroup(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(builder: (context, constraints) {
          final columns =
              MediaQuery.textScalerOf(context).scale(17) > 24 ? 1 : 2;
          return Wrap(spacing: 16, runSpacing: 24, children: [
            for (final metric in metrics)
              SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 16) / columns,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(metric.$1,
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textMuted)),
                        const SizedBox(height: 6),
                        Text(metric.$2,
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w600)),
                      ])),
          ]);
        }));
  }

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required Widget chart,
  }) {
    return Container(
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
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.appleBlack,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.appleMutedGray,
              fontSize: 11,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(height: 200, child: chart),
        ],
      ),
    );
  }

  Widget _buildLeanChart(List<FusedSample> samples) {
    if (samples.isEmpty) {
      return const Center(
        child: Text(
          'Žádná data grafu',
          style: TextStyle(color: AppTheme.appleMutedGray, fontSize: 13),
        ),
      );
    }

    final step = (samples.length / 100).ceil().clamp(1, 1000);
    final spots = <FlSpot>[];
    for (int i = 0; i < samples.length; i += step) {
      spots.add(FlSpot(i.toDouble(), samples[i].leanAngleDeg));
    }

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 8,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final angle = spot.y;
                final direction = angle < -0.5
                    ? 'vlevo'
                    : angle > 0.5
                        ? 'vpravo'
                        : 'přímo';
                return LineTooltipItem(
                  '${angle.abs().toStringAsFixed(1)}° $direction',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 15,
          getDrawingHorizontalLine: (val) {
            final isZero = val.abs() < 0.1;
            return FlLine(
              color: isZero ? const Color(0xFFC7C7CC) : const Color(0xFFF2F2F7),
              strokeWidth: isZero ? 1.2 : 0.8,
              dashArray: isZero ? [4, 4] : null,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: 15,
              getTitlesWidget: (val, meta) {
                final intVal = val.toInt();
                final String label;
                if (intVal < 0) {
                  label = '${intVal.abs()}° L';
                } else if (intVal > 0) {
                  label = '$intVal° P';
                } else {
                  label = '0°';
                }
                return Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.appleMutedGray,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: AppTheme.appleBlue,
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.appleBlue.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedChart(List<FusedSample> samples) {
    if (samples.isEmpty) {
      return const Center(
        child: Text(
          'Žádná data grafu',
          style: TextStyle(color: AppTheme.appleMutedGray, fontSize: 13),
        ),
      );
    }

    final step = (samples.length / 100).ceil().clamp(1, 1000);
    final spots = <FlSpot>[];
    for (int i = 0; i < samples.length; i += step) {
      spots.add(FlSpot(i.toDouble(), samples[i].vehicleSpeedKmh.toDouble()));
    }

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 8,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(0)} km/h',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 30,
          getDrawingHorizontalLine: (val) => const FlLine(
            color: Color(0xFFF2F2F7),
            strokeWidth: 0.8,
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 30,
              getTitlesWidget: (val, meta) {
                return Text(
                  '${val.toInt()}',
                  style: const TextStyle(
                    color: AppTheme.appleMutedGray,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: AppTheme.appleOrange,
            barWidth: 2.2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.appleOrange.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportSheet() async {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Exportovat telemetrická data'),
        message: const Text(
            'Vyberte požadovaný formát pro analýzu nebo zobrazení v mapách'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _exportGpx();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.map_outlined, color: AppTheme.appleBlue, size: 20),
                SizedBox(width: 8),
                Text('Exportovat GPX (Strava, Garmin, Mapy)'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _exportCsv();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_chart_outlined,
                    color: AppTheme.appleGreen, size: 20),
                SizedBox(width: 8),
                Text('Exportovat CSV (MoTeC i2, RaceRender)'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _exportZipPackage();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_zip_outlined,
                    color: AppTheme.applePurple, size: 20),
                SizedBox(width: 8),
                Text('Balíček pro MoTeC i2 a RaceRender (.zip)'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Zrušit'),
        ),
      ),
    );
  }

  Future<void> _exportZipPackage() async {
    try {
      final path =
          await widget.dbService.exportSessionPackageToZip(widget.session.id!);
      await Share.shareXFiles([XFile(path)],
          text: 'MotoLogger Analytický balíček: ${widget.session.title}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.appleRed,
            content: Text('Chyba při exportu balíčku: $e'),
          ),
        );
      }
    }
  }

  Future<void> _exportGpx() async {
    try {
      final path =
          await widget.dbService.exportSessionToGpx(widget.session.id!);
      await Share.shareXFiles([XFile(path)],
          text: 'MotoLogger Jízda GPX: ${widget.session.title}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.appleRed,
            content: Text('Chyba při exportu GPX: $e'),
          ),
        );
      }
    }
  }

  Future<void> _exportCsv() async {
    try {
      final path =
          await widget.dbService.exportSessionToCsv(widget.session.id!);
      await Share.shareXFiles([XFile(path)],
          text: 'MotoLogger Jízda CSV: ${widget.session.title}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.appleRed,
            content: Text('Chyba při exportu CSV: $e'),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Smazat jízdu?'),
        content: const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
              'Opravdu si přejete smazat tento záznam jízdy? Tuto akci nelze vzít zpět.'),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zrušit'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Smazat'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.dbService.deleteSession(widget.session.id!);
      if (mounted) Navigator.pop(context);
    }
  }
}

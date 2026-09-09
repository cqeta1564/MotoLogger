import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session.dart';
import '../../models/fused_sample.dart';
import '../../services/database_service.dart';

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
        title: Text(widget.session.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 22),
            tooltip: 'Exportovat CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.appleRed, size: 22),
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
          final samples = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Apple Summary Card
                _buildSummaryCard(samples),
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
      final totalSpeed = samples.map((e) => e.vehicleSpeedKmh).reduce((a, b) => a + b);
      avgSpeedKmh = totalSpeed / samples.length;
    } else if (s.duration.inSeconds > 5) {
      avgSpeedKmh = s.totalDistanceKm / (s.duration.inSeconds / 3600.0);
    } else {
      avgSpeedKmh = 0.0;
    }

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
        children: [
          // Row 1: Key Primary Metrics
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'ŠPIČKA VLEVO',
                  value: '${s.maxLeanLeftDeg.abs().toStringAsFixed(1)}°',
                  color: AppTheme.appleGreen,
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  label: 'ŠPIČKA VPRAVO',
                  value: '${s.maxLeanRightDeg.abs().toStringAsFixed(1)}°',
                  color: AppTheme.appleOrange,
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  label: 'MAX RYCHLOST',
                  value: '${s.topSpeedKmh.toStringAsFixed(0)} km/h',
                  color: AppTheme.appleBlack,
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  label: 'MAXIMÁLNÍ G',
                  value: '${s.maxGForce.toStringAsFixed(2)} G',
                  color: AppTheme.appleRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFE5E5EA), height: 1),
          const SizedBox(height: 14),

          // Row 2: Secondary Ride Stats
          Row(
            children: [
              Expanded(
                child: _buildSecondaryTile(
                  label: 'DOBA JÍZDY',
                  value: '${s.duration.inMinutes} min ${s.duration.inSeconds % 60} s',
                ),
              ),
              Expanded(
                child: _buildSecondaryTile(
                  label: 'PRŮMĚRNÁ RYCHLOST',
                  value: '${avgSpeedKmh.round()} km/h',
                ),
              ),
              Expanded(
                child: _buildSecondaryTile(
                  label: 'VZDÁLENOST',
                  value: '${s.totalDistanceKm.toStringAsFixed(2)} km',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.appleMutedGray,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            fontFamily: '-apple-system',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            fontFamily: '-apple-system',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryTile({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.appleMutedGray,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            fontFamily: '-apple-system',
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.appleBlack,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            fontFamily: '-apple-system',
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
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
              fontFamily: '-apple-system',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.appleMutedGray,
              fontSize: 11,
              letterSpacing: -0.1,
              fontFamily: '-apple-system',
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
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    fontFamily: '-apple-system',
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
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                    fontFamily: '-apple-system',
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
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(0)} km/h',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: '-apple-system',
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
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                    fontFamily: '-apple-system',
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

  Future<void> _exportCsv() async {
    final path = await widget.dbService.exportSessionToCsv(widget.session.id!);
    await Share.shareXFiles([XFile(path)], text: 'MotoLogger Jízda CSV: ${widget.session.title}');
  }

  Future<void> _confirmDelete() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Smazat jízdu?'),
        content: const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Opravdu si přejete smazat tento záznam jízdy? Tuto akci nelze vzít zpět.'),
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

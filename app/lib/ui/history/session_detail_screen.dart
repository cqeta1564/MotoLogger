import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session.dart';
import '../../models/fused_sample.dart';
import '../../services/database_service.dart';

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
      appBar: AppBar(
        title: Text(widget.session.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: AppTheme.danger),
            tooltip: 'Delete Session',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: FutureBuilder<List<FusedSample>>(
        future: _samplesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final samples = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Summary Card
                _buildSummaryCard(),
                const SizedBox(height: 16),

                // Lean Angle Chart
                _buildChartCard(
                  title: 'LEAN ANGLE OVER TIME (°)',
                  subtitle: 'Negative = Left Lean, Positive = Right Lean',
                  chart: _buildLeanChart(samples),
                ),
                const SizedBox(height: 16),

                // Speed Chart
                _buildChartCard(
                  title: 'SPEED OVER TIME (KM/H)',
                  subtitle: 'Derived from high-speed CAN / GPS telemetry',
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

  Widget _buildSummaryCard() {
    final s = widget.session;
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetric('PEAK LEFT', '${s.maxLeanLeftDeg.abs().toStringAsFixed(1)}°', AppTheme.primary),
                _buildMetric('PEAK RIGHT', '${s.maxLeanRightDeg.abs().toStringAsFixed(1)}°', AppTheme.accent),
                _buildMetric('TOP SPEED', '${s.topSpeedKmh.toStringAsFixed(0)} km/h', AppTheme.textPrimary),
                _buildMetric('MAX G', '${s.maxGForce.toStringAsFixed(2)}G', AppTheme.danger),
              ],
            ),
            const Divider(color: AppTheme.surfaceLight, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetric('DURATION', '${s.duration.inMinutes} min', AppTheme.textSecondary),
                _buildMetric('SAMPLES', '${s.sampleCount}', AppTheme.textSecondary),
                _buildMetric('DISTANCE', '${s.totalDistanceKm.toStringAsFixed(2)} km', AppTheme.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String val, Color col) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(color: col, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required Widget chart,
  }) {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 16),
            SizedBox(height: 180, child: chart),
          ],
        ),
      ),
    );
  }

  Widget _buildLeanChart(List<FusedSample> samples) {
    if (samples.isEmpty) return const Center(child: Text('No chart data'));

    final step = (samples.length / 100).ceil().clamp(1, 1000);
    final spots = <FlSpot>[];
    for (int i = 0; i < samples.length; i += step) {
      spots.add(FlSpot(i.toDouble(), samples[i].leanAngleDeg));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (val) => FlLine(color: AppTheme.surfaceLight, strokeWidth: 1),
          getDrawingVerticalLine: (val) => FlLine(color: AppTheme.surfaceLight, strokeWidth: 1),
        ),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.primary,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primary.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedChart(List<FusedSample> samples) {
    if (samples.isEmpty) return const Center(child: Text('No chart data'));

    final step = (samples.length / 100).ceil().clamp(1, 1000);
    final spots = <FlSpot>[];
    for (int i = 0; i < samples.length; i += step) {
      spots.add(FlSpot(i.toDouble(), samples[i].vehicleSpeedKmh.toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (val) => FlLine(color: AppTheme.surfaceLight, strokeWidth: 1),
          getDrawingVerticalLine: (val) => FlLine(color: AppTheme.surfaceLight, strokeWidth: 1),
        ),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.accent.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final path = await widget.dbService.exportSessionToCsv(widget.session.id!);
    await Share.shareXFiles([XFile(path)], text: 'MotoLogger Session CSV: ${widget.session.title}');
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Session?'),
        content: const Text('Are you sure you want to delete this recorded ride? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE', style: TextStyle(color: AppTheme.danger)),
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

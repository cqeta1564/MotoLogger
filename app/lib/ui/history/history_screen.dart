import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session.dart';
import '../../services/database_service.dart';
import 'session_detail_screen.dart';

/// Screen displaying the list of recorded motorcycle ride sessions.
/// Designed according to Apple Human Interface Guidelines (Inset Grouped style).
class HistoryScreen extends StatefulWidget {
  final DatabaseService dbService;

  const HistoryScreen({super.key, required this.dbService});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<RideSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _sessionsFuture = widget.dbService.getAllSessions();
    });
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$day.$month.$year, $hour:$min';
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    if (mins == 0) return '$secs s';
    return '$mins min $secs s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Historie jízd'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Obnovit',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<RideSession>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CupertinoActivityIndicator(radius: 14),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.appleRed),
                    const SizedBox(height: 12),
                    Text(
                      'Chyba načítání historie',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.appleBlack,
                        fontFamily: '-apple-system',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${snapshot.error}',
                      style: const TextStyle(fontSize: 13, color: AppTheme.appleMutedGray),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      onPressed: _refresh,
                      child: const Text('Zkusit znovu', style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            );
          }

          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE5E5EA), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.two_wheeler_rounded,
                        size: 40,
                        color: AppTheme.appleMutedGray,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Žádné zaznamenané jízdy',
                      style: TextStyle(
                        color: AppTheme.appleBlack,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        fontFamily: '-apple-system',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Zahajte nahrávání jízdy na hlavní obrazovce Jízda a zaznamenejte svou první telemetrii.',
                      style: TextStyle(
                        color: AppTheme.appleMutedGray,
                        fontSize: 14,
                        height: 1.4,
                        letterSpacing: -0.2,
                        fontFamily: '-apple-system',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final s = sessions[index];
              return _buildSessionCard(s);
            },
          );
        },
      ),
    );
  }

  Widget _buildSessionCard(RideSession s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => SessionDetailScreen(
                  session: s,
                  dbService: widget.dbService,
                ),
              ),
            );
            _refresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Title + Duration pill + Chevron
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            style: const TextStyle(
                              color: AppTheme.appleBlack,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              fontFamily: '-apple-system',
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDateTime(s.startTime),
                            style: const TextStyle(
                              color: AppTheme.appleMutedGray,
                              fontSize: 12,
                              fontFamily: '-apple-system',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer_outlined, size: 13, color: AppTheme.appleMutedGray),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(s.duration),
                            style: const TextStyle(
                              color: AppTheme.appleBlack,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: '-apple-system',
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Color(0xFFC7C7CC),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFE5E5EA), height: 1),
                const SizedBox(height: 12),

                // Metrics grid
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        label: 'NÁKLON L',
                        value: '${s.maxLeanLeftDeg.abs().toStringAsFixed(1)}°',
                        valueColor: AppTheme.appleGreen,
                      ),
                    ),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'NÁKLON P',
                        value: '${s.maxLeanRightDeg.abs().toStringAsFixed(1)}°',
                        valueColor: AppTheme.appleOrange,
                      ),
                    ),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'RYCHLOST',
                        value: '${s.topSpeedKmh.toStringAsFixed(0)} km/h',
                        valueColor: AppTheme.appleBlack,
                      ),
                    ),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'MAX G',
                        value: '${s.maxGForce.toStringAsFixed(2)} G',
                        valueColor: AppTheme.appleRed,
                      ),
                    ),
                    // Quick share button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.share_outlined, size: 18, color: AppTheme.appleMutedGray),
                      tooltip: 'Exportovat CSV',
                      onPressed: () async {
                        final path = await widget.dbService.exportSessionToCsv(s.id!);
                        await Share.shareXFiles([XFile(path)], text: 'MotoLogger Jízda: ${s.title}');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.appleMutedGray,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            fontFamily: '-apple-system',
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            fontFamily: '-apple-system',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session.dart';
import '../../services/database_service.dart';
import 'session_detail_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RIDE HISTORY & SESSIONS'),
      ),
      body: FutureBuilder<List<RideSession>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading history: ${snapshot.error}'));
          }
          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.two_wheeler, size: 64, color: AppTheme.textMuted),
                  SizedBox(height: 16),
                  Text(
                    'No Recorded Rides Yet',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start a ride session from the Dashboard to record telemetry.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    final durationMins = s.duration.inMinutes;

    return Card(
      color: AppTheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.surfaceLight),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${durationMins}m ${s.duration.inSeconds % 60}s',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                s.startTime.toLocal().toString().substring(0, 16),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const Divider(color: AppTheme.surfaceLight, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStat('MAX LEAN L', '${s.maxLeanLeftDeg.abs().toStringAsFixed(1)}°', AppTheme.primary),
                  _buildStat('MAX LEAN R', '${s.maxLeanRightDeg.abs().toStringAsFixed(1)}°', AppTheme.accent),
                  _buildStat('TOP SPEED', '${s.topSpeedKmh.toStringAsFixed(0)} km/h', AppTheme.textPrimary),
                  _buildStat('MAX G', '${s.maxGForce.toStringAsFixed(2)}G', AppTheme.danger),
                  IconButton(
                    icon: const Icon(Icons.share, size: 20, color: AppTheme.textSecondary),
                    tooltip: 'Export CSV',
                    onPressed: () async {
                      final path = await widget.dbService.exportSessionToCsv(s.id!);
                      await Share.shareXFiles([XFile(path)], text: 'MotoLogger Telemetry: ${s.title}');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

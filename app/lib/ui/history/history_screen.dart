import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session.dart';
import '../../services/database_service.dart';
import '../../services/telemetry_manager.dart';
import '../widgets/season_summary_card.dart';
import 'session_detail_screen.dart';

enum HistorySortOption {
  newest,
  fastest,
  maxLean,
}

/// Screen displaying the list of recorded motorcycle ride sessions.
/// Designed according to Apple Human Interface Guidelines (Inset Grouped style)
/// with Season aggregate stats, sorting options, search filtering, and MicroSD CSV import.
class HistoryScreen extends StatefulWidget {
  final DatabaseService dbService;
  final TelemetryManager? telemetryManager;

  const HistoryScreen({
    super.key,
    required this.dbService,
    this.telemetryManager,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<RideSession>> _sessionsFuture;
  HistorySortOption _sortOption = HistorySortOption.newest;
  String _searchQuery = '';
  bool _isImporting = false;
  bool _isSelectionMode = false;
  final Set<int> _selectedSessionIds = {};
  bool _isExportingBulk = false;
  List<RideSession> _cachedSessions = [];

  bool _wasSyncing = false;
  bool _wasRecording = false;

  @override
  void initState() {
    super.initState();
    _wasSyncing = widget.telemetryManager?.isSyncing ?? false;
    _wasRecording = widget.telemetryManager?.isRecording ?? false;
    _refresh();
    widget.telemetryManager?.addListener(_onTelemetryManagerUpdated);
  }

  @override
  void dispose() {
    widget.telemetryManager?.removeListener(_onTelemetryManagerUpdated);
    super.dispose();
  }

  void _onTelemetryManagerUpdated() {
    final tm = widget.telemetryManager;
    if (tm == null || !mounted) return;

    final isSyncing = tm.isSyncing;
    final isRecording = tm.isRecording;

    // Only refresh the database sessions when sync finishes or when a ride recording finishes
    final syncFinished = _wasSyncing && !isSyncing;
    final recordingStopped = _wasRecording && !isRecording;

    if (syncFinished || recordingStopped) {
      _refresh();
    }

    _wasSyncing = isSyncing;
    _wasRecording = isRecording;
  }

  void _refresh() {
    setState(() {
      _sessionsFuture = widget.dbService.getAllSessions().then((sessions) {
        if (mounted) {
          setState(() {
            _cachedSessions = sessions;
          });
        }
        return sessions;
      });
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

  Future<void> _importFromMicroSd() async {
    if (_isImporting) return;

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: 'Vyberte záznam z MicroSD karty (LOG_XXXX.CSV)',
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      setState(() => _isImporting = true);

      final pickedFile = result.files.single;
      String? csvContent;

      if (pickedFile.bytes != null) {
        csvContent = utf8.decode(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        final file = File(pickedFile.path!);
        csvContent = await file.readAsString();
      }

      if (csvContent == null || csvContent.trim().isEmpty) {
        throw const FormatException('Soubor CSV je prázdný nebo jej nelze přečíst.');
      }

      final rawName = pickedFile.name.replaceAll('.csv', '').replaceAll('.CSV', '');
      final session = await widget.dbService.importRideFromCsv(
        csvContent: csvContent,
        defaultTitle: 'MicroSD: $rawName',
      );

      _refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.appleGreen,
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Jízda „${session.title}“ byla úspěšně importována (${session.sampleCount} vzorků).'),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.appleRed,
            content: Text('Chyba při importu jízdy: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedSessionIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedSessionIds.clear();
    });
  }

  void _toggleSessionSelection(int id) {
    setState(() {
      if (_selectedSessionIds.contains(id)) {
        _selectedSessionIds.remove(id);
      } else {
        _selectedSessionIds.add(id);
      }
    });
  }

  void _toggleSelectAll(List<RideSession> visibleSessions) {
    setState(() {
      if (_selectedSessionIds.length == visibleSessions.length) {
        _selectedSessionIds.clear();
      } else {
        _selectedSessionIds.clear();
        for (final s in visibleSessions) {
          if (s.id != null) _selectedSessionIds.add(s.id!);
        }
      }
    });
  }

  Future<void> _exportSelectedSessionsAsZip() async {
    if (_selectedSessionIds.isEmpty || _isExportingBulk) return;
    setState(() => _isExportingBulk = true);
    try {
      final path = await widget.dbService.exportMultipleSessionsPackageToZip(
        sessionIds: _selectedSessionIds.toList(),
      );
      await Share.shareXFiles(
        [XFile(path)],
        text: 'MotoLogger Export ${_selectedSessionIds.length} jízd (.zip)',
      );
      _exitSelectionMode();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.appleRed, content: Text('Chyba při hromadném exportu: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingBulk = false);
      }
    }
  }

  Future<void> _exportAllSessionsAsZip(List<RideSession> sessions) async {
    final validIds = sessions.map((s) => s.id).whereType<int>().toList();
    if (validIds.isEmpty) return;

    setState(() => _isExportingBulk = true);
    try {
      final path = await widget.dbService.exportMultipleSessionsPackageToZip(
        sessionIds: validIds,
        customTitle: 'MotoLogger_All_Sessions',
      );
      await Share.shareXFiles(
        [XFile(path)],
        text: 'MotoLogger Export všech jízd (${validIds.length})',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.appleRed, content: Text('Chyba při exportu všech jízd: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingBulk = false);
      }
    }
  }

  List<RideSession> _filterAndSortSessions(List<RideSession> sessions) {
    var filtered = sessions.where((s) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final titleMatch = s.title.toLowerCase().contains(q);
      final dateMatch = _formatDateTime(s.startTime).toLowerCase().contains(q);
      return titleMatch || dateMatch;
    }).toList();

    switch (_sortOption) {
      case HistorySortOption.newest:
        filtered.sort((a, b) => b.startTime.compareTo(a.startTime));
        break;
      case HistorySortOption.fastest:
        filtered.sort((a, b) => b.topSpeedKmh.compareTo(a.topSpeedKmh));
        break;
      case HistorySortOption.maxLean:
        filtered.sort((a, b) {
          final maxA = max(a.maxLeanLeftDeg.abs(), a.maxLeanRightDeg.abs());
          final maxB = max(b.maxLeanLeftDeg.abs(), b.maxLeanRightDeg.abs());
          return maxB.compareTo(maxA);
        });
        break;
    }
    return filtered;
  }

  Future<void> _showExportSheet(RideSession s) async {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('Export jízdy: ${s.title}'),
        message: const Text('Vyberte formát pro uložení nebo sdílení'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final path = await widget.dbService.exportSessionToGpx(s.id!);
                await Share.shareXFiles([XFile(path)], text: 'MotoLogger Jízda GPX: ${s.title}');
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: AppTheme.appleRed, content: Text('Chyba při exportu GPX: $e')),
                  );
                }
              }
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
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final path = await widget.dbService.exportSessionToCsv(s.id!);
                await Share.shareXFiles([XFile(path)], text: 'MotoLogger Jízda CSV: ${s.title}');
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: AppTheme.appleRed, content: Text('Chyba při exportu CSV: $e')),
                  );
                }
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_chart_outlined, color: AppTheme.appleGreen, size: 20),
                SizedBox(width: 8),
                Text('Exportovat CSV (MoTeC i2, RaceRender)'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final path = await widget.dbService.exportSessionPackageToZip(s.id!);
                await Share.shareXFiles([XFile(path)], text: 'MotoLogger Analytický balíček: ${s.title}');
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: AppTheme.appleRed, content: Text('Chyba při exportu balíčku: $e')),
                  );
                }
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_zip_outlined, color: AppTheme.applePurple, size: 20),
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

  Widget _buildSyncStatusBar() {
    final tm = widget.telemetryManager;
    if (tm == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: tm,
      builder: (context, _) {
        final isSyncing = tm.isSyncing;
        final msg = tm.syncStatusMessage;
        if (!isSyncing && msg == null) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSyncing
                ? AppTheme.appleBlue.withValues(alpha: 0.08)
                : AppTheme.appleGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSyncing
                  ? AppTheme.appleBlue.withValues(alpha: 0.25)
                  : AppTheme.appleGreen.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              if (isSyncing)
                const CupertinoActivityIndicator(radius: 8)
              else
                const Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.appleGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg ?? 'Synchronizace s motocyklem...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSyncing ? AppTheme.appleBlue : AppTheme.appleGreen,
                    fontFamily: '-apple-system',
                  ),
                ),
              ),
              if (isSyncing)
                Text(
                  '${(tm.syncProgress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.appleBlue,
                    fontFamily: '-apple-system',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cachedFiltered = _filterAndSortSessions(_cachedSessions);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        leading: _isSelectionMode
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _exitSelectionMode,
                child: const Text(
                  'Hotovo',
                  style: TextStyle(
                    color: AppTheme.appleBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              )
            : null,
        title: Text(_isSelectionMode ? 'Vybráno: ${_selectedSessionIds.length}' : 'Historie jízd'),
        actions: _isSelectionMode
            ? [
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onPressed: () => _toggleSelectAll(cachedFiltered),
                  child: Text(
                    _selectedSessionIds.length == cachedFiltered.length && cachedFiltered.isNotEmpty
                        ? 'Odznačit'
                        : 'Vybrat vše',
                    style: const TextStyle(
                      color: AppTheme.appleBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ]
            : [
                IconButton(
                  icon: _isImporting
                      ? const CupertinoActivityIndicator(radius: 10)
                      : const Icon(Icons.sd_card_outlined, size: 22),
                  tooltip: 'Importovat z MicroSD',
                  onPressed: _isImporting ? null : _importFromMicroSd,
                ),
                if (_cachedSessions.isNotEmpty) ...[
                  IconButton(
                    icon: _isExportingBulk
                        ? const CupertinoActivityIndicator(radius: 10)
                        : const Icon(Icons.archive_outlined, size: 22),
                    tooltip: 'Exportovat vše do ZIP',
                    onPressed: _isExportingBulk ? null : () => _exportAllSessionsAsZip(cachedFiltered),
                  ),
                  IconButton(
                    icon: const Icon(Icons.checklist_rounded, size: 22),
                    tooltip: 'Vybrat jízdy',
                    onPressed: _enterSelectionMode,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 22),
                  tooltip: 'Obnovit',
                  onPressed: _refresh,
                ),
              ],
      ),
      bottomNavigationBar: _isSelectionMode
          ? Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 12 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE5E5EA), width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                height: 54,
                child: CupertinoButton(
                  color: AppTheme.appleBlue,
                  disabledColor: AppTheme.appleBlue.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  padding: EdgeInsets.zero,
                  onPressed: (_selectedSessionIds.isEmpty || _isExportingBulk)
                      ? null
                      : _exportSelectedSessionsAsZip,
                  child: _isExportingBulk
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_zip_outlined, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Exportovat balíček (${_selectedSessionIds.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFamily: '-apple-system',
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            )
          : null,
      body: FutureBuilder<List<RideSession>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _cachedSessions.isEmpty) {
            return const Center(
              child: CupertinoActivityIndicator(radius: 14),
            );
          }
          if (snapshot.hasError && _cachedSessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.appleRed),
                    const SizedBox(height: 12),
                    const Text(
                      'Chyba načítání historie',
                      style: TextStyle(
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

          final sessions = snapshot.data ?? _cachedSessions;
          _cachedSessions = sessions;
          final seasonStats = SeasonStats.fromSessions(sessions);

          if (sessions.isEmpty) {
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                _buildSyncStatusBar(),
                SeasonSummaryCard(stats: seasonStats),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F7),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE5E5EA), width: 1.2),
                        ),
                        child: const Icon(
                          Icons.two_wheeler_rounded,
                          size: 36,
                          color: AppTheme.appleMutedGray,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Žádné zaznamenané jízdy',
                        style: TextStyle(
                          color: AppTheme.appleBlack,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          fontFamily: '-apple-system',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Zaznamenejte jízdu v aplikaci nebo importujte záznam z MicroSD karty motocyklu.',
                        style: TextStyle(
                          color: AppTheme.appleMutedGray,
                          fontSize: 13,
                          height: 1.4,
                          letterSpacing: -0.2,
                          fontFamily: '-apple-system',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.appleBlue, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _importFromMicroSd,
                          icon: const Icon(Icons.sd_card_outlined, color: AppTheme.appleBlue, size: 20),
                          label: const Text(
                            'Importovat z MicroSD',
                            style: TextStyle(color: AppTheme.appleBlue, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final filteredSessions = _filterAndSortSessions(sessions);

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // 1. Auto-sync status bar
              _buildSyncStatusBar(),

              // 2. Season Summary Card
              SeasonSummaryCard(stats: seasonStats),

              // 3. Search Bar
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: CupertinoSearchTextField(
                  placeholder: 'Hledat v jízdách podle názvu či data...',
                  style: const TextStyle(fontFamily: '-apple-system', fontSize: 14),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
              ),

              // 4. Sorting Cupertino Segmented Control
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<HistorySortOption>(
                  groupValue: _sortOption,
                  children: const {
                    HistorySortOption.newest: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text('Nejnovější', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    HistorySortOption.fastest: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text('Nejrychlejší', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    HistorySortOption.maxLean: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text('Největší náklon', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  },
                  onValueChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _sortOption = val;
                      });
                    }
                  },
                ),
              ),

              // 5. Session List or Empty Filter Notice
              if (filteredSessions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                  ),
                  child: const Center(
                    child: Text(
                      'Žádné jízdy neodpovídají zadanému filtru.',
                      style: TextStyle(
                        color: AppTheme.appleMutedGray,
                        fontSize: 14,
                        fontFamily: '-apple-system',
                      ),
                    ),
                  ),
                )
              else
                ...filteredSessions.map((s) => _buildSessionCard(s)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSessionCard(RideSession s) {
    final isSelected = s.id != null && _selectedSessionIds.contains(s.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppTheme.appleBlue : const Color(0xFFE5E5EA),
          width: isSelected ? 1.8 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? AppTheme.appleBlue.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.03),
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
            if (_isSelectionMode) {
              if (s.id != null) _toggleSessionSelection(s.id!);
              return;
            }
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
          onLongPress: () {
            if (!_isSelectionMode && s.id != null) {
              _enterSelectionMode();
              _toggleSessionSelection(s.id!);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: (Selection indicator) + Title + Duration pill + Chevron/Checkmark
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_isSelectionMode) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? AppTheme.appleBlue : Colors.white,
                          border: Border.all(
                            color: isSelected ? AppTheme.appleBlue : const Color(0xFFC7C7CC),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                    ],
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
                    Icon(
                      _isSelectionMode
                          ? (isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked)
                          : Icons.chevron_right_rounded,
                      size: 20,
                      color: _isSelectionMode
                          ? (isSelected ? AppTheme.appleBlue : const Color(0xFFC7C7CC))
                          : const Color(0xFFC7C7CC),
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
                    if (!_isSelectionMode)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.share_outlined, size: 18, color: AppTheme.appleMutedGray),
                        tooltip: 'Exportovat data',
                        onPressed: () => _showExportSheet(s),
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

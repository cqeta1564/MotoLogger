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
import '../widgets/glass_surface.dart';
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
  final _searchController = TextEditingController();
  int _refreshGeneration = 0;
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
    _searchController.dispose();
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
    final generation = ++_refreshGeneration;
    setState(() {
      _sessionsFuture = widget.dbService.getAllSessions().then((sessions) {
        if (mounted && generation == _refreshGeneration) {
          setState(() => _cachedSessions = sessions);
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
        throw const FormatException(
            'Soubor CSV je prázdný nebo jej nelze přečíst.');
      }

      final rawName =
          pickedFile.name.replaceAll('.csv', '').replaceAll('.CSV', '');
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
                const Icon(Icons.check_circle_outline_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'Jízda „${session.title}“ byla úspěšně importována (${session.sampleCount} vzorků).'),
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
          SnackBar(
              backgroundColor: AppTheme.appleRed,
              content: Text('Chyba při hromadném exportu: $e')),
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
          SnackBar(
              backgroundColor: AppTheme.appleRed,
              content: Text('Chyba při exportu všech jízd: $e')),
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
                await Share.shareXFiles([XFile(path)],
                    text: 'MotoLogger Jízda GPX: ${s.title}');
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        backgroundColor: AppTheme.appleRed,
                        content: Text('Chyba při exportu GPX: $e')),
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
                await Share.shareXFiles([XFile(path)],
                    text: 'MotoLogger Jízda CSV: ${s.title}');
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        backgroundColor: AppTheme.appleRed,
                        content: Text('Chyba při exportu CSV: $e')),
                  );
                }
              }
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
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final path =
                    await widget.dbService.exportSessionPackageToZip(s.id!);
                await Share.shareXFiles([XFile(path)],
                    text: 'MotoLogger Analytický balíček: ${s.title}');
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        backgroundColor: AppTheme.appleRed,
                        content: Text('Chyba při exportu balíčku: $e')),
                  );
                }
              }
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
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: AppTheme.appleGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg ?? 'Synchronizace s motocyklem...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSyncing ? AppTheme.appleBlue : AppTheme.appleGreen,
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
    final inset = AppTheme.navigationInset(context) +
        12 +
        MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppTheme.surfaceSecondary,
      appBar: AppBar(
        toolbarHeight: 80,
        centerTitle: false,
        automaticallyImplyLeading: false,
        title: Text(
            _isSelectionMode
                ? 'Vybráno: ${_selectedSessionIds.length}'
                : 'Historie',
            style: TextStyle(
                fontSize: _isSelectionMode ? 22 : 34,
                letterSpacing: -1,
                fontWeight: FontWeight.w700)),
        actions: [
          if (_isSelectionMode)
            TextButton(
                onPressed: _exitSelectionMode, child: const Text('Hotovo'))
          else
            Padding(
                padding: const EdgeInsets.only(right: 20),
                child: GlassSurface(
                    radius: 26,
                    child: Row(children: [
                      if (_cachedSessions.isNotEmpty)
                        IconButton(
                            tooltip: 'Vybrat jízdy',
                            icon: const Icon(CupertinoIcons.checkmark_circle),
                            onPressed: _enterSelectionMode),
                      PopupMenuButton<String>(
                          tooltip: 'Možnosti historie',
                          icon: const Icon(CupertinoIcons.ellipsis),
                          onSelected: (action) {
                            if (action == 'import') _importFromMicroSd();
                            if (action == 'export') {
                              _exportAllSessionsAsZip(cachedFiltered);
                            }
                            if (action == 'refresh') _refresh();
                          },
                          itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: 'import',
                                    enabled: !_isImporting,
                                    child: const Text('Importovat z MicroSD')),
                                if (_cachedSessions.isNotEmpty)
                                  PopupMenuItem(
                                      value: 'export',
                                      enabled: !_isExportingBulk,
                                      child:
                                          const Text('Exportovat vše do ZIP')),
                                const PopupMenuItem(
                                    value: 'refresh', child: Text('Obnovit')),
                              ]),
                    ]))),
        ],
      ),
      bottomNavigationBar: _isSelectionMode
          ? Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, inset),
              child: PrimaryAction(
                  label: 'Exportovat balíček (${_selectedSessionIds.length})',
                  icon: CupertinoIcons.share,
                  busy: _isExportingBulk,
                  onPressed: _selectedSessionIds.isEmpty
                      ? null
                      : _exportSelectedSessionsAsZip),
            )
          : null,
      body: FutureBuilder<List<RideSession>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _cachedSessions.isEmpty) {
            return const Center(child: CupertinoActivityIndicator(radius: 14));
          }
          if (snapshot.hasError && _cachedSessions.isEmpty) {
            return ListView(
                padding: EdgeInsets.fromLTRB(24, 32, 24, inset),
                children: [
                  const Icon(CupertinoIcons.exclamationmark_circle,
                      size: 48, color: AppTheme.danger),
                  const SizedBox(height: 16),
                  const Text('Historii se nepodařilo načíst',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text(
                      'Záznamy zůstávají v telefonu. Zkuste načtení znovu.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  PrimaryAction(label: 'Zkusit znovu', onPressed: _refresh),
                ]);
          }
          final sessions = snapshot.data ?? _cachedSessions;
          final filtered = _filterAndSortSessions(sessions);
          return CustomScrollView(
              key: const PageStorageKey('history-scroll'),
              slivers: [
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSyncStatusBar(),
                            if (_isImporting || _isExportingBulk)
                              const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        CupertinoActivityIndicator(),
                                        SizedBox(width: 12),
                                        Text('Zpracovávám soubor…'),
                                      ])),
                            if (snapshot.hasError)
                              const Text(
                                  'Obnovení se nezdařilo. Zobrazuji dříve načtené jízdy.'),
                            if (sessions.isEmpty)
                              ContentGroup(
                                  padding: const EdgeInsets.all(28),
                                  child: Column(children: [
                                    const Icon(CupertinoIcons.map,
                                        size: 52, color: AppTheme.appleBlue),
                                    const SizedBox(height: 24),
                                    const Text('Každá jízda má svůj příběh',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -.5)),
                                    const SizedBox(height: 12),
                                    const Text(
                                        'Zatím tu není žádná jízda. Zahajte záznam na záložce Jízda nebo načtěte soubor z motorky.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 17,
                                            height: 1.45,
                                            color: AppTheme.textMuted)),
                                    const SizedBox(height: 28),
                                    PrimaryAction(
                                        label: 'Importovat z MicroSD',
                                        icon: CupertinoIcons.folder,
                                        busy: _isImporting,
                                        onPressed: _importFromMicroSd),
                                  ]))
                            else ...[
                              SeasonSummaryCard(
                                  stats: SeasonStats.fromSessions(sessions)),
                              const SizedBox(height: 8),
                              CupertinoSearchTextField(
                                  controller: _searchController,
                                  placeholder: 'Název nebo datum jízdy',
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                  style: const TextStyle(fontSize: 17),
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value)),
                              const SizedBox(height: 16),
                              if (_isSelectionMode)
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                        onPressed: () =>
                                            _toggleSelectAll(filtered),
                                        child: Text(
                                            _selectedSessionIds.length ==
                                                        filtered.length &&
                                                    filtered.isNotEmpty
                                                ? 'Odznačit'
                                                : 'Vybrat vše')))
                              else
                                _sortControls(),
                              const SizedBox(height: 20),
                              if (filtered.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                        'Žádné jízdy neodpovídají hledání.',
                                        textAlign: TextAlign.center)),
                            ],
                          ]),
                    )),
                SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) =>
                            _buildSessionCard(filtered[index]))),
                SliverToBoxAdapter(
                    child: SizedBox(height: _isSelectionMode ? 24 : inset)),
              ]);
        },
      ),
    );
  }

  Widget _sortControls() {
    const labels = {
      HistorySortOption.newest: 'Nejnovější',
      HistorySortOption.fastest: 'Nejrychlejší',
      HistorySortOption.maxLean: 'Největší náklon',
    };
    if (MediaQuery.textScalerOf(context).scale(17) > 22) {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final entry in labels.entries)
          ChoiceChip(
              label: Text(entry.value),
              selected: _sortOption == entry.key,
              onSelected: (_) => setState(() => _sortOption = entry.key)),
      ]);
    }
    return CupertinoSlidingSegmentedControl<HistorySortOption>(
      groupValue: _sortOption,
      children: {
        for (final entry in labels.entries)
          entry.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
              child: Text(entry.value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13)))
      },
      onValueChanged: (value) {
        if (value != null) setState(() => _sortOption = value);
      },
    );
  }

  Widget _buildSessionCard(RideSession session) {
    final selected = _selectedSessionIds.contains(session.id);
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          selected: selected,
          child: ContentGroup(
              child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () async {
                if (_isSelectionMode) {
                  if (session.id != null) _toggleSessionSelection(session.id!);
                  return;
                }
                await Navigator.push(
                    context,
                    CupertinoPageRoute<void>(
                        builder: (_) => SessionDetailScreen(
                            session: session, dbService: widget.dbService)));
                if (mounted) _refresh();
              },
              onLongPress: () {
                _enterSelectionMode();
                if (session.id != null) _toggleSessionSelection(session.id!);
              },
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(session.title,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600))),
                          const SizedBox(width: 12),
                          Icon(
                              _isSelectionMode
                                  ? (selected
                                      ? CupertinoIcons.checkmark_circle_fill
                                      : CupertinoIcons.circle)
                                  : CupertinoIcons.chevron_right,
                              color: selected
                                  ? AppTheme.appleBlue
                                  : AppTheme.textMuted,
                              size: 20),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                            '${_formatDateTime(session.startTime)} · ${_formatDuration(session.duration)}',
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textMuted)),
                        const SizedBox(height: 18),
                        Wrap(spacing: 24, runSpacing: 12, children: [
                          _metric('Vzdálenost',
                              '${session.totalDistanceKm.toStringAsFixed(1)} km'),
                          _metric('Max. rychlost',
                              '${session.topSpeedKmh.round()} km/h'),
                          _metric('Náklon L / P',
                              '${session.maxLeanLeftDeg.abs().round()}° / ${session.maxLeanRightDeg.abs().round()}°'),
                        ]),
                        if (!_isSelectionMode)
                          Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                  onPressed: () => _showExportSheet(session),
                                  icon: const Icon(CupertinoIcons.share,
                                      size: 18),
                                  label: const Text('Exportovat'))),
                      ])),
            ),
          )),
        ));
  }

  Widget _metric(String label, String value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ]);
}

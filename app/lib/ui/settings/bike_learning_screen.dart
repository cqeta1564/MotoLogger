import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/can_learning_service.dart';
import '../../services/telemetry_manager.dart';
import 'import_bike_profile_screen.dart';

/// Screen for recording a motorcycle calibration ride and exporting
/// synchronized CAN bus telemetry along with an optimized AI prompt.
class BikeLearningScreen extends StatefulWidget {
  final TelemetryManager telemetryManager;

  const BikeLearningScreen({
    super.key,
    required this.telemetryManager,
  });

  @override
  State<BikeLearningScreen> createState() => _BikeLearningScreenState();
}

class _BikeLearningScreenState extends State<BikeLearningScreen> {
  late final CanLearningService _learningService;
  int _currentStep = 0; // 0: Preparation, 1: Recording, 2: Completed / Export
  bool _promptCopied = false;

  @override
  void initState() {
    super.initState();
    _learningService = CanLearningService(
      bleService: widget.telemetryManager.bleService,
      gpsService: widget.telemetryManager.gpsService,
    );
    _learningService.addListener(_onLearningStateChanged);
  }

  void _onLearningStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _learningService.removeListener(_onLearningStateChanged);
    _learningService.dispose();
    super.dispose();
  }

  void _startRecording() {
    HapticFeedback.mediumImpact();
    _learningService.startRecording();
    setState(() {
      _currentStep = 1;
      _promptCopied = false;
    });
  }

  void _stopRecording() {
    HapticFeedback.heavyImpact();
    _learningService.stopRecording();
    setState(() {
      _currentStep = 2;
    });
  }

  Future<void> _copyPrompt() async {
    final prompt = _learningService.generateAiPrompt();
    await Clipboard.setData(ClipboardData(text: prompt));
    HapticFeedback.mediumImpact();

    setState(() => _promptCopied = true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: const Color(0xFF1C1C1E),
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Prompt pro AI byl zkopírován do schránky.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: '-apple-system',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareDatasetFile() async {
    HapticFeedback.lightImpact();
    try {
      await _learningService.shareDatasetFile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chyba při sdílení souboru: $e'),
          backgroundColor: AppTheme.appleRed,
        ),
      );
    }
  }

  void _openImportScreen() {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => ImportBikeProfileScreen(
          canProfileService: widget.telemetryManager.canProfileService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F7),
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.xmark_circle_fill, color: Color(0xFF8E8E93), size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Naučit se motorku',
          style: TextStyle(
            fontFamily: '.SF Pro Display',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: _buildStepContent(),
              ),
            ),
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildRecordingView();
      case 2:
        return _buildCompletedView();
      case 0:
      default:
        return _buildPreparationView();
    }
  }

  Widget _buildPreparationView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header card with explanation
        Container(
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.appleBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppTheme.appleBlue, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Automatické mapování CAN sběrnice',
                          style: TextStyle(
                            color: AppTheme.appleBlack,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            fontFamily: '-apple-system',
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Pomocí AI asistence (ChatGPT / Claude / Gemini)',
                          style: TextStyle(
                            color: AppTheme.appleMutedGray,
                            fontSize: 12.5,
                            fontFamily: '-apple-system',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'MotoLogger zaznamená provoz na sběrnici motocyklu a spáruje jej s GPS rychlostí. Získáte datový balíček a prompt, který pošlete AI. Ta identifikuje otáčky, rychlost, plyn i převod.',
                style: TextStyle(
                  color: Color(0xFF3A3A3C),
                  fontSize: 14,
                  height: 1.45,
                  letterSpacing: -0.2,
                  fontFamily: '-apple-system',
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 3 Simple steps instruction card
        const Padding(
          padding: EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            'DOPORUČENÝ POSTUP JÍZDY',
            style: TextStyle(
              color: AppTheme.appleMutedGray,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              fontFamily: '-apple-system',
            ),
          ),
        ),

        _buildInstructionCard(
          stepNumber: '1',
          title: 'Volnoběh (~10 sekund)',
          subtitle: 'Nastartujte a nechte motor běžet na neutrálu bez přidávání plynu.',
          icon: Icons.timer_outlined,
        ),
        const SizedBox(height: 10),
        _buildInstructionCard(
          stepNumber: '2',
          title: 'Túrování na místě (~10 sekund)',
          subtitle: 'Na neutrálu 2–3x krátce přidejte plyn. AI tak bezpečně pozná otáčky i při nulové rychlosti.',
          icon: Icons.speed_rounded,
        ),
        const SizedBox(height: 10),
        _buildInstructionCard(
          stepNumber: '3',
          title: 'Krátká jízda s řazením (~30 sekund)',
          subtitle: 'Rozjeďte se, zařaďte 1., 2. a 3. stupeň, chvíli jeďte plynule a poté bezpečně zastavte.',
          icon: Icons.two_wheeler_rounded,
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildInstructionCard({
    required String stepNumber,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              stepNumber,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: '-apple-system',
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.appleBlack,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    fontFamily: '-apple-system',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.appleMutedGray,
                    fontSize: 13,
                    height: 1.35,
                    fontFamily: '-apple-system',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingView() {
    final minutes = (_learningService.elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_learningService.elapsedSeconds % 60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),

        // Live Pulsing Indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppTheme.appleRed,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'PROBÍHÁ ZÁZNAM JÍZDY',
              style: TextStyle(
                color: AppTheme.appleRed,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                fontFamily: '-apple-system',
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Large Stopwatch Timer
        Text(
          '$minutes:$seconds',
          style: const TextStyle(
            color: AppTheme.appleBlack,
            fontSize: 64,
            fontWeight: FontWeight.w200,
            letterSpacing: -1.5,
            fontFamily: '-apple-system',
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),

        const SizedBox(height: 28),

        // Status Metrics Cards
        Container(
          padding: const EdgeInsets.all(18),
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
          child: Column(
            children: [
              _buildLiveMetricRow(
                'Zachycené CAN zprávy',
                '${_learningService.capturedFrameCount}',
                Icons.analytics_outlined,
                AppTheme.appleBlue,
              ),
              const Divider(color: Color(0xFFE5E5EA), height: 20),
              _buildLiveMetricRow(
                'Unikátní CAN ID sběrnice',
                '${_learningService.uniqueCanIdCount}',
                Icons.alt_route_rounded,
                AppTheme.appleGreen,
              ),
              const Divider(color: Color(0xFFE5E5EA), height: 20),
              _buildLiveMetricRow(
                'GPS spojení',
                'Aktivní (10 Hz)',
                Icons.gps_fixed_rounded,
                AppTheme.appleOrange,
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text(
          'Projeďte se podle doporučených kroků a poté klepněte na tlačítko Dokončit záznam níže.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.appleMutedGray,
            fontSize: 13,
            height: 1.4,
            fontFamily: '-apple-system',
          ),
        ),
      ],
    );
  }

  Widget _buildLiveMetricRow(String label, String value, IconData icon, Color iconColor) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.appleBlack,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              fontFamily: '-apple-system',
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.appleBlack,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: '-apple-system',
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success Header Card
        Container(
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.appleGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: AppTheme.appleGreen, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Podklady pro AI jsou připraveny',
                          style: TextStyle(
                            color: AppTheme.appleBlack,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            fontFamily: '-apple-system',
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Data a prompt můžete odeslat jakékoliv AI',
                          style: TextStyle(
                            color: AppTheme.appleMutedGray,
                            fontSize: 12.5,
                            fontFamily: '-apple-system',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryPill('Čas záznamu', '${_learningService.elapsedSeconds} s'),
                  _buildSummaryPill('Zpráv CAN', '${_learningService.capturedFrameCount}'),
                  _buildSummaryPill('Unikátních ID', '${_learningService.uniqueCanIdCount}'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Action 1: Copy Prompt Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.appleBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.copy_rounded, color: AppTheme.appleBlue, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1. Krok: Zkopírovat prompt pro AI',
                          style: TextStyle(
                            color: AppTheme.appleBlack,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: '-apple-system',
                          ),
                        ),
                        Text(
                          'Přesně definuje schéma výstupního JSON profilu',
                          style: TextStyle(
                            color: AppTheme.appleMutedGray,
                            fontSize: 12,
                            fontFamily: '-apple-system',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  color: _promptCopied ? AppTheme.appleGreen : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: _copyPrompt,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _promptCopied ? Icons.check_rounded : Icons.copy_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _promptCopied ? 'PROMPT ZKOPÍROVÁN' : 'KOPÍROVAT PROMPT DO SCHRÁNKY',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: '-apple-system',
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Action 2: Share Dataset File Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.appleOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.share_rounded, color: AppTheme.appleOrange, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '2. Krok: Sdílet / uložit soubor pro AI',
                          style: TextStyle(
                            color: AppTheme.appleBlack,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: '-apple-system',
                          ),
                        ),
                        Text(
                          'motologger_can_dataset.json (analýza změn)',
                          style: TextStyle(
                            color: AppTheme.appleMutedGray,
                            fontSize: 12,
                            fontFamily: '-apple-system',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  color: const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: _shareDatasetFile,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.ios_share_rounded, color: AppTheme.appleBlack, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'SDÍLET SOUBOR S DATY PRO AI',
                        style: TextStyle(
                          color: AppTheme.appleBlack,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: '-apple-system',
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSummaryPill(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.appleBlack,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: '-apple-system',
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.appleMutedGray,
            fontSize: 12,
            fontFamily: '-apple-system',
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final buttonHeight = isLandscape
        ? AppTheme.primaryButtonHeightLandscape
        : AppTheme.primaryButtonHeight;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: buttonHeight,
        child: _buildCurrentActionButton(),
      ),
    );
  }

  Widget _buildCurrentActionButton() {
    if (_currentStep == 0) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
        color: const Color(0xFF1C1C1E),
        onPressed: _startRecording,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'SPUSTIT ZÁZNAM JÍZDY',
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    } else if (_currentStep == 1) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
        color: AppTheme.appleRed,
        onPressed: _stopRecording,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stop_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'DOKONČIT A VYGENEROVAT PRO AI',
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    } else {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
        color: const Color(0xFF1C1C1E),
        onPressed: _openImportScreen,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.paste_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'VLOŽIT ODPOVĚĎ OD AI',
              style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }
  }
}

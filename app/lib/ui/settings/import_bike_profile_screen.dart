import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../models/can_profile.dart';
import '../../services/can_profile_service.dart';
import '../../services/telemetry_manager.dart';

/// Screen for pasting, validating, and activating an AI-generated CAN mapping profile.
class ImportBikeProfileScreen extends StatefulWidget {
  final CanProfileService canProfileService;
  final TelemetryManager? telemetryManager;

  const ImportBikeProfileScreen({
    super.key,
    required this.canProfileService,
    this.telemetryManager,
  });

  @override
  State<ImportBikeProfileScreen> createState() => _ImportBikeProfileScreenState();
}

class _ImportBikeProfileScreenState extends State<ImportBikeProfileScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  BikeProfile? _parsedProfile;
  String? _parseError;
  bool _isSaving = false;

  @override
  void dispose() {
    _textController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _parseInput(String input) {
    if (input.trim().isEmpty) {
      setState(() {
        _parsedProfile = null;
        _parseError = null;
      });
      return;
    }

    try {
      final profile = BikeProfile.fromAiJson(input);
      setState(() {
        _parsedProfile = profile;
        _nameController.text = profile.name;
        _parseError = null;
      });
    } catch (e) {
      setState(() {
        _parsedProfile = null;
        _parseError = e.toString().replaceAll('FormatException: ', '');
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _textController.text = data.text!;
      _parseInput(data.text!);
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _saveAndActivate() async {
    if (_parsedProfile == null || _isSaving) return;

    setState(() => _isSaving = true);
    HapticFeedback.heavyImpact();

    final finalName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : _parsedProfile!.name;

    final updatedProfile = BikeProfile(
      id: _parsedProfile!.id,
      name: finalName,
      createdAt: _parsedProfile!.createdAt,
      canBaudrate: _parsedProfile!.canBaudrate,
      signals: _parsedProfile!.signals,
      rawAiJson: _parsedProfile!.rawAiJson,
    );

    await widget.canProfileService.saveAndActivateProfile(updatedProfile);
    if (widget.telemetryManager != null) {
      await widget.telemetryManager!.syncActiveProfileToEsp();
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: const Color(0xFF1C1C1E),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.appleGreen, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Profil "$finalName" byl uložen a aktivován.',
                style: const TextStyle(
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

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _parsedProfile != null;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final buttonHeight = isLandscape
        ? AppTheme.primaryButtonHeightLandscape
        : AppTheme.primaryButtonHeight;

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
          'Vložit profil od AI',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Input Card
                    Container(
                      padding: const EdgeInsets.all(16),
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'ODPOVĚĎ JAZYKOVÉHO MODELU',
                                style: TextStyle(
                                  color: AppTheme.appleMutedGray,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.6,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _pasteFromClipboard,
                                child: const Row(
                                  children: [
                                    Icon(Icons.paste_rounded, size: 15, color: AppTheme.appleBlue),
                                    SizedBox(width: 4),
                                    Text(
                                      'Vložit ze schránky',
                                      style: TextStyle(
                                        color: AppTheme.appleBlue,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: '-apple-system',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _textController,
                            maxLines: 7,
                            onChanged: _parseInput,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontFamily: 'Courier',
                              color: AppTheme.appleBlack,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Sem vložte JSON text vygenerovaný ChatGPT, Claude nebo Gemini...',
                              hintStyle: const TextStyle(
                                color: Color(0xFFC7C7CC),
                                fontFamily: '-apple-system',
                                fontSize: 13,
                              ),
                              contentPadding: const EdgeInsets.all(12),
                              filled: true,
                              fillColor: const Color(0xFFF9F9FB),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE5E5EA)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE5E5EA)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppTheme.appleBlue),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_parseError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.appleRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.appleRed.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppTheme.appleRed, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _parseError!,
                                style: const TextStyle(
                                  color: AppTheme.appleRed,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: '-apple-system',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_parsedProfile != null) ...[
                      const SizedBox(height: 20),

                      // Profile Name Customizer
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'NÁZEV MOTOCYKLU',
                              style: TextStyle(
                                color: AppTheme.appleMutedGray,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                                fontFamily: '-apple-system',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nameController,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.appleBlack,
                                fontFamily: '-apple-system',
                              ),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                filled: true,
                                fillColor: const Color(0xFFF9F9FB),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFFE5E5EA)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Identified Signals Summary Card
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 8),
                        child: Text(
                          'DETEKOVANÉ SIGNÁLY CAN SBĚRNICE',
                          style: TextStyle(
                            color: AppTheme.appleMutedGray,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            fontFamily: '-apple-system',
                          ),
                        ),
                      ),

                      _buildSignalTile(
                        title: 'Otáčky motoru (RPM)',
                        signal: _parsedProfile!.rpmSignal,
                        icon: Icons.speed_rounded,
                        color: AppTheme.appleOrange,
                      ),
                      const SizedBox(height: 8),
                      _buildSignalTile(
                        title: 'Rychlost motocyklu (Speed)',
                        signal: _parsedProfile!.speedSignal,
                        icon: Icons.navigation_rounded,
                        color: AppTheme.appleBlue,
                      ),
                      const SizedBox(height: 8),
                      _buildSignalTile(
                        title: 'Poloha plynu (Throttle)',
                        signal: _parsedProfile!.throttleSignal,
                        icon: Icons.linear_scale_rounded,
                        color: AppTheme.appleGreen,
                      ),
                      const SizedBox(height: 8),
                      _buildSignalTile(
                        title: 'Zařazený stupeň (Gear)',
                        signal: _parsedProfile!.gearSignal,
                        icon: Icons.tune_rounded,
                        color: AppTheme.applePurple,
                      ),
                      const SizedBox(height: 8),
                      _buildSignalTile(
                        title: 'Teplota chlazení (Coolant)',
                        signal: _parsedProfile!.coolantSignal,
                        icon: Icons.thermostat_rounded,
                        color: AppTheme.appleRed,
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom Action Button
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: buttonHeight,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(AppTheme.primaryButtonRadius),
                  color: isReady ? const Color(0xFF1C1C1E) : const Color(0xFFAEAEC2),
                  onPressed: isReady ? _saveAndActivate : null,
                  child: _isSaving
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'ULOŽIT A AKTIVOVAT PROFIL',
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalTile({
    required String title,
    required CanSignalMapping? signal,
    required IconData icon,
    required Color color,
  }) {
    final exists = signal != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: exists ? color.withValues(alpha: 0.12) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: exists ? color : AppTheme.appleMutedGray,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.appleBlack,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: '-apple-system',
                  ),
                ),
                Text(
                  exists
                      ? 'ID: ${signal.canId} | Bajt ${signal.startByte}..${signal.startByte + signal.lengthBytes - 1} | ×${signal.multiplier}'
                      : 'Nenalezeno v JSONu (zůstane výchozí)',
                  style: TextStyle(
                    color: exists ? AppTheme.appleMutedGray : AppTheme.appleMutedGray.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontFamily: '-apple-system',
                  ),
                ),
              ],
            ),
          ),
          Icon(
            exists ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
            color: exists ? AppTheme.appleGreen : const Color(0xFFC7C7CC),
            size: 20,
          ),
        ],
      ),
    );
  }
}

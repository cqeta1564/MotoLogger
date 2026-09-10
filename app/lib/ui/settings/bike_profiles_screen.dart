import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/can_profile_service.dart';
import '../../services/telemetry_manager.dart';
import 'import_bike_profile_screen.dart';

/// Screen listing all saved motorcycle CAN mapping profiles with options to switch,
/// add new ones, or delete.
class BikeProfilesScreen extends StatelessWidget {
  final CanProfileService canProfileService;
  final TelemetryManager? telemetryManager;

  const BikeProfilesScreen({
    super.key,
    required this.canProfileService,
    this.telemetryManager,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: canProfileService,
      builder: (context, _) {
        final active = canProfileService.activeProfile;
        final saved = canProfileService.savedProfiles;

        return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            backgroundColor: const Color(0xFFF2F2F7),
            elevation: 0,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.chevron_back, color: AppTheme.appleBlack, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Profily motocyklů',
              style: TextStyle(
                fontFamily: '.SF Pro Display',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                letterSpacing: -0.3,
              ),
            ),
            centerTitle: true,
            actions: [
              CupertinoButton(
                padding: const EdgeInsets.only(right: 16),
                onPressed: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (ctx) => ImportBikeProfileScreen(
                        canProfileService: canProfileService,
                        telemetryManager: telemetryManager,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Přidat',
                  style: TextStyle(
                    color: AppTheme.appleBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: '-apple-system',
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  'VÝCHOZÍ STANDARD',
                  style: TextStyle(
                    color: AppTheme.appleMutedGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    fontFamily: '-apple-system',
                  ),
                ),
              ),

              // Standard OBD-II Profile Card
              _buildProfileCard(
                context: context,
                name: 'Standardní OBD-II',
                subtitle: 'Standardní diagnostické dotazy (PID 0x0C, 0x0D)',
                isActive: active.id == 'standard_obd2',
                canDelete: false,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await canProfileService.setStandardObdActive();
                  if (telemetryManager != null) {
                    await telemetryManager!.syncActiveProfileToEsp();
                  }
                },
              ),

              const SizedBox(height: 24),

              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  'NAUČENÉ PROFILY CAN SBĚRNICE',
                  style: TextStyle(
                    color: AppTheme.appleMutedGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    fontFamily: '-apple-system',
                  ),
                ),
              ),

              if (saved.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.two_wheeler_rounded, size: 40, color: Color(0xFFC7C7CC)),
                      const SizedBox(height: 12),
                      const Text(
                        'Zatím nemáte naučenou žádnou motorku',
                        style: TextStyle(
                          color: AppTheme.appleBlack,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: '-apple-system',
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Vraťte se do Nastavení a spusťte "Naučit se motorku".',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.appleMutedGray,
                          fontSize: 13,
                          fontFamily: '-apple-system',
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...saved.map((profile) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildProfileCard(
                      context: context,
                      name: profile.name,
                      subtitle: '${profile.signals.length} mapovaných signálů | ${profile.canBaudrate ~/ 1000} kbps',
                      isActive: active.id == profile.id,
                      canDelete: true,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await canProfileService.setActiveProfile(profile);
                        if (telemetryManager != null) {
                          await telemetryManager!.syncActiveProfileToEsp();
                        }
                      },
                      onDelete: () async {
                        HapticFeedback.mediumImpact();
                        final confirmed = await showCupertinoDialog<bool>(
                          context: context,
                          builder: (ctx) => CupertinoAlertDialog(
                            title: Text('Smazat profil "${profile.name}"?'),
                            content: const Text('Tuto akci nelze vzít zpět.'),
                            actions: [
                              CupertinoDialogAction(
                                isDefaultAction: true,
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Zrušit'),
                              ),
                              CupertinoDialogAction(
                                isDestructiveAction: true,
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Smazat'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true) {
                          await canProfileService.deleteProfile(profile.id);
                        }
                      },
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileCard({
    required BuildContext context,
    required String name,
    required String subtitle,
    required bool isActive,
    required bool canDelete,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AppTheme.appleBlack : const Color(0xFFE5E5EA),
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.appleBlack
                        : const Color(0xFFF2F2F7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.two_wheeler_rounded,
                    color: isActive ? Colors.white : AppTheme.appleBlack,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppTheme.appleBlack,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          fontFamily: '-apple-system',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.appleMutedGray,
                          fontSize: 12.5,
                          fontFamily: '-apple-system',
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.appleBlack,
                    size: 22,
                  )
                else if (canDelete)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onDelete,
                    child: const Icon(
                      CupertinoIcons.trash,
                      color: Color(0xFFC7C7CC),
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import 'apple_scale_button.dart';

/// An action item displayed inside an [AppleModalSheet].
class AppleSheetAction {
  const AppleSheetAction({
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.icon,
    this.isDestructive = false,
    this.isDefaultAction = false,
  });

  final String title;
  final VoidCallback onPressed;
  final String? subtitle;
  final IconData? icon;
  final bool isDestructive;
  final bool isDefaultAction;
}

/// Native Apple iOS 18 modal bottom sheet with continuous 24 pt squircle top corners,
/// tactile grabber pill (36×5 pt), hairline dividers, and Apple typography.
class AppleModalSheet extends StatelessWidget {
  const AppleModalSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.actions,
    this.cancelLabel = 'Zrušit',
    this.showCancel = true,
  });

  final String title;
  final String? subtitle;
  final List<AppleSheetAction> actions;
  final String cancelLabel;
  final bool showCancel;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isOpaque =
        (AppPreferencesScope.maybeOf(context)?.reduceTransparency ?? false) ||
            media.highContrast;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, media.padding.bottom > 0 ? 8 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Main sheet container
            Container(
              decoration: BoxDecoration(
                color: isOpaque ? Colors.white : const Color(0xFAFFFFFF),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFE5E5EA),
                  width: 0.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x180C2340),
                    blurRadius: 32,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top grabber pill
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC7C7CC),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.4,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Hairline divider under header
                    const Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: Color(0xFFE5E5EA),
                    ),

                    // Actions list
                    for (int i = 0; i < actions.length; i++) ...[
                      _buildActionRow(context, actions[i]),
                      if (i < actions.length - 1)
                        const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: 52,
                          endIndent: 0,
                          color: Color(0xFFE5E5EA),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            // Separate Cancel Button (Apple iOS style)
            if (showCancel) ...[
              const SizedBox(height: 10),
              AppleScaleButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFE5E5EA),
                      width: 0.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C0C2340),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    cancelLabel,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.appleBlue,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, AppleSheetAction action) {
    final color = action.isDestructive
        ? AppTheme.appleRed
        : action.isDefaultAction
            ? AppTheme.appleBlue
            : AppTheme.textPrimary;

    return AppleScaleButton(
      onPressed: () {
        Navigator.of(context).pop();
        action.onPressed();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        constraints: const BoxConstraints(minHeight: 52),
        color: Colors.transparent,
        child: Row(
          children: [
            if (action.icon != null) ...[
              Icon(action.icon, size: 22, color: color),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: action.isDefaultAction
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: color,
                    ),
                  ),
                  if (action.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: Color(0xFFC7C7CC),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper to show an [AppleModalSheet] as a bottom sheet.
Future<T?> showAppleModalSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<AppleSheetAction> actions,
  String cancelLabel = 'Zrušit',
  bool showCancel = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000), // 35% black backdrop
    isScrollControlled: true,
    builder: (ctx) => AppleModalSheet(
      title: title,
      subtitle: subtitle,
      actions: actions,
      cancelLabel: cancelLabel,
      showCancel: showCancel,
    ),
  );
}

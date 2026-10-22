import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import 'apple_scale_button.dart';

/// A bounded Flutter material approximation, not native Apple Liquid Glass.
/// Strictly restricted to floating capsules (AppleTabBar) and floating action docks.
class GlassSurface extends StatelessWidget {
  const GlassSurface(
      {super.key,
      required this.child,
      this.radius = 28,
      this.padding = EdgeInsets.zero});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final opaque =
        (AppPreferencesScope.maybeOf(context)?.reduceTransparency ?? false) ||
            media.highContrast ||
            media.accessibleNavigation;
    final borderRadius = BorderRadius.circular(radius);

    if (opaque) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius,
          border: Border.all(color: AppTheme.surfaceBorder, width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C0C2340),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(padding: padding, child: child),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
              color: Color(0x140C2340), blurRadius: 24, offset: Offset(0, 8)),
          BoxShadow(
              color: Color(0x060C2340), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xDCFFFFFF),
              borderRadius: borderRadius,
              border: Border.all(
                color: const Color(0xE0FFFFFF),
                width: 0.5,
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFE5E5EA),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: label,
                onPressed: onPressed,
                icon: Icon(icon, size: 18, color: AppTheme.textPrimary),
              ),
            ),
          ),
        ),
      );
}

class AppPageTitle extends StatelessWidget {
  const AppPageTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (subtitle != null) ...[
                  Text(subtitle!,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                ],
                Semantics(
                    header: true,
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 34,
                            height: 1.1,
                            letterSpacing: -1.1,
                            fontWeight: FontWeight.w700))),
              ])),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ]),
      );
}

class ContentGroup extends StatelessWidget {
  const ContentGroup(
      {super.key,
      required this.child,
      this.padding = EdgeInsets.zero,
      this.radius = 16});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5)),
        child: child,
      );
}

/// A hairline divider (0.5 pt) indented to align with text in Inset Grouped lists.
class AppleGroupDivider extends StatelessWidget {
  const AppleGroupDivider({super.key, this.indent = 56, this.endIndent = 0});
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) => Divider(
        height: 0.5,
        thickness: 0.5,
        indent: indent,
        endIndent: endIndent,
        color: const Color(0xFFE5E5EA),
      );
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction(
      {super.key,
      required this.label,
      required this.onPressed,
      this.icon,
      this.busy = false,
      this.destructive = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) => AppleScaleButton(
        onPressed: busy ? null : onPressed,
        child: Semantics(
          button: true,
          enabled: onPressed != null && !busy,
          label: label,
          child: Container(
            height: AppTheme.primaryButtonHeight,
            decoration: BoxDecoration(
              color: destructive
                  ? AppTheme.danger
                  : (onPressed == null && !busy
                      ? const Color(0xFFAEAEB2)
                      : AppTheme.appleBlue),
              borderRadius:
                  BorderRadius.circular(AppTheme.primaryButtonRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (busy)
                const CupertinoActivityIndicator(color: Colors.white)
              else if (icon != null)
                Icon(icon, size: 20, color: Colors.white),
              if (busy || icon != null) const SizedBox(width: 10),
              Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white))),
            ]),
          ),
        ),
      );
}

class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Zpět',
        icon: const Icon(CupertinoIcons.chevron_left, size: 22),
        onPressed: () => Navigator.of(context).maybePop(),
      );
}

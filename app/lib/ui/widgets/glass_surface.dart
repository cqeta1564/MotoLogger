import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/theme/app_theme.dart';

/// A bounded Flutter material approximation, not native Apple Liquid Glass.
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
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: opaque ? Colors.white : const Color(0xDCF9FAFC),
        borderRadius: borderRadius,
        border: Border.all(
            color: opaque ? AppTheme.surfaceBorder : const Color(0xF0FFFFFF),
            width: 1),
      ),
      child: Padding(padding: padding, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
              color: Color(0x120C2340), blurRadius: 24, offset: Offset(0, 8)),
          BoxShadow(color: Color(0x090C2340), blurRadius: 2, spreadRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: opaque
            ? surface
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: surface,
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
  Widget build(BuildContext context) => GlassSurface(
        radius: 24,
        child: IconButton(
            tooltip: label,
            onPressed: onPressed,
            icon: Icon(icon),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
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
      {super.key, required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: child,
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
  Widget build(BuildContext context) => ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: AppTheme.primaryButtonHeight),
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor:
                destructive ? AppTheme.danger : AppTheme.textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppTheme.primaryButtonRadius)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy)
              const CupertinoActivityIndicator(color: Colors.white)
            else if (icon != null)
              Icon(icon, size: 20),
            if (busy || icon != null) const SizedBox(width: 10),
            Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600))),
          ]),
        ),
      );
}

class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4),
        child: GlassIconButton(
            icon: CupertinoIcons.chevron_left,
            label: 'Zpět',
            onPressed: () => Navigator.of(context).maybePop()),
      );
}

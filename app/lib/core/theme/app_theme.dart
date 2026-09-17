import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static String get systemFont => defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS
      ? 'CupertinoSystemText'
      : 'Roboto';
  // Apple System Palette
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFF2F2F7);
  static const Color surfaceBorder = Color(0xFFE5E5EA);
  static const Color surfaceLight = Color(0xFFE5E5EA);

  // Apple Typography Colors
  static const Color textPrimary = Color(0xFF1C1C1E);
  static const Color textSecondary = Color(0xFF1C1C1E);
  static const Color textMuted = Color(0xFF63636B);
  static const Color textSubtle = Color(0xFFAEAEB2);

  // Apple Functional Accents & System Colors
  static const Color primary = Color(0xFF1C1C1E);
  static const Color appleBlack = Color(0xFF1C1C1E);
  static const Color appleBlue = Color(0xFF0066CC);
  static const Color accent = Color(0xFFFF9500);
  static const Color appleOrange = Color(0xFFFF9500);
  static const Color success = Color(0xFF34C759);
  static const Color appleGreen = Color(0xFF34C759);
  static const Color danger = Color(0xFFFF3B30);
  static const Color appleRed = Color(0xFFFF3B30);
  static const Color warning = Color(0xFFFFCC00);
  static const Color appleYellow = Color(0xFFFFCC00);
  static const Color purple = Color(0xFFAF52DE);
  static const Color applePurple = Color(0xFFAF52DE);
  static const Color appleMutedGray = Color(0xFF63636B);
  static const Color appleBorder = Color(0xFFE5E5EA);
  static const Color appleGroupedBg = Color(0xFFF2F2F7);

  // Apple Primary Button Metrics (Unified across whole app)
  static const double primaryButtonHeight = 54.0;
  static const double primaryButtonHeightLandscape = 54.0;
  static const double primaryButtonRadius = 14.0;

  static double navigationInset(BuildContext context) =>
      100 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 48) * 3;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: appleBlue,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 17, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 17, color: textPrimary),
        titleLarge: TextStyle(
            fontSize: 22, color: textPrimary, fontWeight: FontWeight.w600),
      ),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
              minimumSize: const Size(48, 48), foregroundColor: textPrimary)),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              minimumSize: const Size(48, 48), foregroundColor: appleBlue)),
      fontFamily: systemFont,
      scaffoldBackgroundColor: surfaceSecondary,
      primaryColor: primary,
      cardColor: surfaceSecondary,
      appBarTheme: AppBarTheme(
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          fontFamily: systemFont,
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceSecondary,
        selectedItemColor: textPrimary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceSecondary,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: surfaceBorder, width: 0.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: const DividerThemeData(
        color: surfaceBorder,
        thickness: 0.8,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1C1C1E),
        contentTextStyle: TextStyle(
          fontFamily: systemFont,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 112),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      colorScheme: const ColorScheme.light(
        primary: appleBlue,
        secondary: accent,
        surface: surface,
        error: danger,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class AppTheme {
  // Apple System Palette
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFF2F2F7);
  static const Color surfaceBorder = Color(0xFFE5E5EA);
  static const Color surfaceLight = Color(0xFFE5E5EA);

  // Apple Typography Colors
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF1C1C1E);
  static const Color textMuted = Color(0xFF8E8E93);
  static const Color textSubtle = Color(0xFFAEAEB2);

  // Apple Functional Accents & System Colors
  static const Color primary = Color(0xFF000000);
  static const Color appleBlack = Color(0xFF000000);
  static const Color appleBlue = Color(0xFF007AFF);
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
  static const Color appleMutedGray = Color(0xFF8E8E93);
  static const Color appleBorder = Color(0xFFE5E5EA);
  static const Color appleGroupedBg = Color(0xFFF2F2F7);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      cardColor: surfaceSecondary,
      fontFamily: '-apple-system',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          fontFamily: '-apple-system',
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
          fontFamily: '-apple-system',
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          fontFamily: '-apple-system',
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
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: '-apple-system',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: danger,
      ),
    );
  }
}

import 'package:flutter/material.dart';

class AppTheme {
  // Pure White Apple-style Light Theme Palette
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFF2F2F7);
  static const Color surfaceBorder = Color(0xFFE5E5EA);
  static const Color surfaceLight = Color(0xFFE5E5EA);

  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF1C1C1E);
  static const Color textMuted = Color(0xFF8E8E93);
  static const Color textSubtle = Color(0xFFAEAEB2);

  static const Color primary = Color(0xFF000000);
  static const Color accent = Color(0xFFFF9500);       // Apple Orange / Amber
  static const Color success = Color(0xFF34C759);      // Apple Green
  static const Color danger = Color(0xFFFF3B30);       // Apple Red
  static const Color warning = Color(0xFFFFCC00);      // Apple Yellow

  // Legacy Dark Theme Palette (for reference / optional mode)
  static const Color darkBackground = Color(0xFF0A0C10);
  static const Color darkSurface = Color(0xFF141820);
  static const Color darkSurfaceLight = Color(0xFF1E2430);

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      cardColor: surfaceSecondary,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
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
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: danger,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: const Color(0xFF00E5FF),
      cardColor: darkSurface,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Color(0xFFF0F4F8),
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: Color(0xFF00E5FF),
        unselectedItemColor: Color(0xFF536074),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00E5FF),
        secondary: accent,
        surface: darkSurface,
        error: danger,
      ),
    );
  }
}

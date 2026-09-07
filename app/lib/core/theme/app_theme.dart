import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF0A0C10);
  static const Color surface = Color(0xFF141820);
  static const Color surfaceLight = Color(0xFF1E2430);
  
  static const Color primary = Color(0xFF00E5FF);       // Electric Cyan
  static const Color accent = Color(0xFFFF9100);        // Racing Amber
  static const Color success = Color(0xFF00E676);       // Emerald Green
  static const Color danger = Color(0xFFFF1744);        // Shift Light Red
  static const Color warning = Color(0xFFFFD600);       // Warning Yellow

  static const Color textPrimary = Color(0xFFF0F4F8);
  static const Color textSecondary = Color(0xFF8A99AD);
  static const Color textMuted = Color(0xFF536074);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      cardColor: surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: danger,
      ),
    );
  }
}

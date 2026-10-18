import 'package:flutter/material.dart';

class AppTheme {
  // Brand colors
  static const Color brandNavy = Color(0xFF07284C);
  static const Color brandNavyLight = Color(0xFF13467D);
  static const Color brandBlue = Color(0xFF086EDB);
  static const Color brandBlueLight = Color(0xFFE8F2FC);
  static const Color brandBlueAccent = Color(0xFF38BDF8);

  // Status & Risk colors
  static const Color riskRed = Color(0xFFEF4444);
  static const Color riskRedBg = Color(0xFFFEE2E2);
  static const Color riskRedText = Color(0xFFB91C1C);

  static const Color successGreen = Color(0xFF10B981);
  static const Color successGreenBg = Color(0xFFECFDF5);
  static const Color successGreenText = Color(0xFF047857);

  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color warningAmberBg = Color(0xFFFEF3C7);
  static const Color warningAmberText = Color(0xFFB45309);

  static const Color simulationPurple = Color(0xFF8B5CF6);
  static const Color simulationPurpleBg = Color(0xFFEDE9FE);
  static const Color simulationPurpleText = Color(0xFF6D28D9);

  // Neutral & Surface
  static const Color background = Color(0xFFF8FAFC);
  static const Color cardBg = Colors.white;
  static const Color borderSubtle = Color(0xFFE2E8F0);
  static const Color borderMedium = Color(0xFFCBD5E1);

  // Typography colors
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      primaryColor: brandBlue,
      colorScheme: const ColorScheme.light(
        primary: brandBlue,
        secondary: brandNavy,
        surface: cardBg,
        error: riskRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: brandNavy),
        titleTextStyle: TextStyle(
          color: brandNavy,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: 'Plus Jakarta Sans',
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderSubtle),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF93C5FD),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brandNavy,
          side: const BorderSide(color: borderSubtle, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brandBlue, width: 1.8),
        ),
      ),
    );
  }
}

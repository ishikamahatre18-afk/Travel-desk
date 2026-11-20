import 'package:flutter/material.dart';

class AppTheme {
  static const teal = Color(0xFF1F8A8A);
  static const bg = Color(0xFFF5FAFA);
  static const sun = Color(0xFFFFB27A);
  static const ink = Color(0xFF16313A);
  static const line = Color(0xFFDCE9E9);

  /// A very soft lift for cards and the input bar.
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF0E4A4F).withValues(alpha: 0.07),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ];

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.light,
    ).copyWith(primary: teal, secondary: sun, surface: Colors.white);

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ink,
        centerTitle: false,
        titleTextStyle:
            TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: border(line),
        enabledBorder: border(line),
        focusedBorder: border(teal, 1.6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: teal,
          side: const BorderSide(color: teal),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: teal.withValues(alpha: 0.14),
      ),
    );
  }
}

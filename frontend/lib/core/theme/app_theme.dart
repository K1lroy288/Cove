import 'package:flutter/material.dart';

class AppTheme {
  static const Color darkBg = Color(0xFF12121A);
  static const Color surface = Color(0xFF1E1E26);
  static const Color accentIndigo = Color(0xFF6366F1);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: accentIndigo,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: accentIndigo,
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBg,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(color: Colors.white10),
    );
  }
}

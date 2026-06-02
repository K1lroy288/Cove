import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
  });

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
  }) =>
      AppColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        divider: divider ?? this.divider,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

class AppTheme {
  static const Color darkBg = Color(0xFF12121A);
  static const Color surface = Color(0xFF1E1E26);
  static const Color accentIndigo = Color(0xFF6366F1);

  static const Color lightBg = Color(0xFFF4F4F8);
  static const Color lightSurface = Color(0xFFFFFFFF);

  static const AppColors _darkColors = AppColors(
    bg: darkBg,
    surface: surface,
    textPrimary: Colors.white,
    textSecondary: Color(0x61FFFFFF), // white38
    divider: Color(0x1AFFFFFF),       // white10
  );

  static const AppColors _lightColors = AppColors(
    bg: lightBg,
    surface: lightSurface,
    textPrimary: Color(0xDE000000),   // black87
    textSecondary: Color(0xFF757575), // gray600 — достаточный контраст на белом
    divider: Color(0xFFBDBDBD),       // gray400 — видимые границы
  );

  static Config emojiPickerConfig(AppColors colors, {double height = 256}) {
    return Config(
      height: height,
      emojiTextStyle: DefaultEmojiTextStyle,
      emojiViewConfig: EmojiViewConfig(
        backgroundColor: colors.surface,
        noRecents: Text(
          'Нет недавних',
          style: TextStyle(fontSize: 16, color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
      categoryViewConfig: CategoryViewConfig(
        backgroundColor: colors.surface,
        indicatorColor: accentIndigo,
        iconColor: colors.textSecondary,
        iconColorSelected: accentIndigo,
        backspaceColor: accentIndigo,
        dividerColor: colors.divider,
      ),
      bottomActionBarConfig: BottomActionBarConfig(
        backgroundColor: colors.surface,
        buttonColor: colors.surface,
        buttonIconColor: accentIndigo,
      ),
      searchViewConfig: SearchViewConfig(
        backgroundColor: colors.surface,
        buttonIconColor: colors.textSecondary,
        inputTextStyle: TextStyle(color: colors.textPrimary),
        hintTextStyle: TextStyle(color: colors.textSecondary),
      ),
    );
  }

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
      extensions: const [_darkColors],
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: accentIndigo,
      colorScheme: const ColorScheme.light(
        surface: lightSurface,
        primary: accentIndigo,
        onSurface: Colors.black87,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBg,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
        titleTextStyle: TextStyle(color: Colors.black87, fontSize: 20),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE0E0E0)),
      extensions: const [_lightColors],
    );
  }
}

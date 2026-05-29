import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const background = Color(0xFF070A12);
  static const surface = Color(0xFF101521);
  static const elevated = Color(0xFF151C2B);
  static const line = Color(0xFF263145);
  static const cyan = Color(0xFF63D8FF);
  static const indigo = Color(0xFF8EA7FF);
  static const mint = Color(0xFF5FF0B5);
  static const rose = Color(0xFFFF7AAE);
  static const amber = Color(0xFFFFD166);
  static const text = Color(0xFFF3F7FF);
  static const muted = Color(0xFFAAB6CC);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
    ).copyWith(
      primary: cyan,
      secondary: mint,
      tertiary: rose,
      surface: surface,
      surfaceContainerHighest: elevated,
      outline: line,
      onSurface: text,
      onSurfaceVariant: muted,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      fontFamily: 'SF Pro Display',
    );

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          color: text,
          fontWeight: FontWeight.w800,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: text,
          fontWeight: FontWeight.w800,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: text,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: text,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: text,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: text.withValues(alpha: .9),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: elevated.withValues(alpha: .76),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 42),
          shape: rounded,
          backgroundColor: cyan,
          foregroundColor: const Color(0xFF061019),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 42),
          shape: rounded,
          foregroundColor: text,
          side: BorderSide(color: line.withValues(alpha: .9)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cyan,
          shape: rounded,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text.withValues(alpha: .86),
          hoverColor: cyan.withValues(alpha: .12),
          shape: rounded,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .055),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: line.withValues(alpha: .9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: line.withValues(alpha: .9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: cyan, width: 1.4),
        ),
        labelStyle: const TextStyle(color: muted),
        prefixIconColor: muted,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white.withValues(alpha: .07),
        selectedColor: cyan.withValues(alpha: .18),
        side: BorderSide(color: line.withValues(alpha: .65)),
        labelStyle: const TextStyle(color: text, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface.withValues(alpha: .96),
        surfaceTintColor: Colors.transparent,
        shape: rounded,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevated,
        contentTextStyle: const TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
        shape: rounded,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: cyan,
        unselectedLabelColor: muted,
        indicatorColor: cyan,
        dividerColor: line,
      ),
      dividerTheme: DividerThemeData(color: line.withValues(alpha: .7)),
    );
  }
}

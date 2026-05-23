import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  // ── Typography (generous sizes for older family members) ──────────────────
  static const _textTheme = TextTheme(
    bodySmall:      TextStyle(fontSize: 13),
    bodyMedium:     TextStyle(fontSize: 15),
    bodyLarge:      TextStyle(fontSize: 17),
    titleSmall:     TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    titleMedium:    TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    titleLarge:     TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    headlineSmall:  TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
    headlineLarge:  TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
  );

  // ── Shared input decoration (18 px radius, floating label) ────────────────
  static InputDecorationTheme _inputTheme(Color fill) => InputDecorationTheme(
        filled: true,
        fillColor: fill,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              const BorderSide(color: AppColors.danger, width: 2),
        ),
        labelStyle: const TextStyle(fontSize: 15),
        errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12),
      );

  // ── Pill button (56 px tall, stadium shape) ───────────────────────────────
  static final _elevatedButton = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      minimumSize: const Size(double.infinity, 56),
      shape: const StadiumBorder(),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.primary.withAlpha(100),
      textStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      elevation: 0,
    ),
  );

  // ── Light theme ───────────────────────────────────────────────────────────
  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.lightSurface,
    ),
    scaffoldBackgroundColor: AppColors.lightBg,
    textTheme: _textTheme,
    elevatedButtonTheme: _elevatedButton,
    inputDecorationTheme: _inputTheme(AppColors.lightSurfaceLo),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightSurface,
      foregroundColor: AppColors.lightFg1,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.lightFg1,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerColor: AppColors.lightHairline,
    iconTheme: const IconThemeData(color: AppColors.lightFg2),
  );

  // ── Dark theme ────────────────────────────────────────────────────────────
  static final dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
    ),
    scaffoldBackgroundColor: AppColors.darkBg,
    textTheme: _textTheme,
    elevatedButtonTheme: _elevatedButton,
    inputDecorationTheme: _inputTheme(AppColors.darkSurfaceLo),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.darkFg1,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.darkFg1,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerColor: AppColors.darkHairline,
    iconTheme: const IconThemeData(color: AppColors.darkFg2),
  );
}

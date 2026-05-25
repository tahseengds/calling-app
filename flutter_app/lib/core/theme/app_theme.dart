import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Extension to easily access custom Lumio design system colors from BuildContext
extension LumioThemeX on BuildContext {
  LumioColors get lumioColors => Theme.of(this).extension<LumioColors>()!;
  TextTheme get textTheme => Theme.of(this).textTheme;
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}

/// Custom ThemeExtension to hold Lumio-specific semantic colors
class LumioColors extends ThemeExtension<LumioColors> {
  final Color surfaceHi;
  final Color surfaceLo;
  final Color hairline;
  final Color hairlineStrong;
  final Color fg1;
  final Color fg2;
  final Color fg3;
  final Color scrim;

  const LumioColors({
    required this.surfaceHi,
    required this.surfaceLo,
    required this.hairline,
    required this.hairlineStrong,
    required this.fg1,
    required this.fg2,
    required this.fg3,
    required this.scrim,
  });

  @override
  LumioColors copyWith({
    Color? surfaceHi,
    Color? surfaceLo,
    Color? hairline,
    Color? hairlineStrong,
    Color? fg1,
    Color? fg2,
    Color? fg3,
    Color? scrim,
  }) {
    return LumioColors(
      surfaceHi: surfaceHi ?? this.surfaceHi,
      surfaceLo: surfaceLo ?? this.surfaceLo,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      fg1: fg1 ?? this.fg1,
      fg2: fg2 ?? this.fg2,
      fg3: fg3 ?? this.fg3,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  LumioColors lerp(ThemeExtension<LumioColors>? other, double t) {
    if (other is! LumioColors) return this;
    return LumioColors(
      surfaceHi: Color.lerp(surfaceHi, other.surfaceHi, t)!,
      surfaceLo: Color.lerp(surfaceLo, other.surfaceLo, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      fg1: Color.lerp(fg1, other.fg1, t)!,
      fg2: Color.lerp(fg2, other.fg2, t)!,
      fg3: Color.lerp(fg3, other.fg3, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return _buildTheme(
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      backgroundColor: AppColors.darkBg,
      surfaceColor: AppColors.darkSurface,
      hairlineColor: AppColors.darkHairline,
      fg1: AppColors.darkFg1,
      fg2: AppColors.darkFg2,
      customColors: const LumioColors(
        surfaceHi: AppColors.darkSurfaceHi,
        surfaceLo: AppColors.darkSurfaceLo,
        hairline: AppColors.darkHairline,
        hairlineStrong: AppColors.darkHairlineStrong,
        fg1: AppColors.darkFg1,
        fg2: AppColors.darkFg2,
        fg3: AppColors.darkFg3,
        scrim: AppColors.darkScrim,
      ),
    );
  }

  static ThemeData get lightTheme {
    return _buildTheme(
      brightness: Brightness.light,
      primaryColor: AppColors.primary,
      backgroundColor: AppColors.lightBg,
      surfaceColor: AppColors.lightSurface,
      hairlineColor: AppColors.lightHairline,
      fg1: AppColors.lightFg1,
      fg2: AppColors.lightFg2,
      customColors: const LumioColors(
        surfaceHi: AppColors.lightSurfaceHi,
        surfaceLo: AppColors.lightSurfaceLo,
        hairline: AppColors.lightHairline,
        hairlineStrong: AppColors.lightHairlineStrong,
        fg1: AppColors.lightFg1,
        fg2: AppColors.lightFg2,
        fg3: AppColors.lightFg3,
        scrim: AppColors.lightScrim,
      ),
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color primaryColor,
    required Color backgroundColor,
    required Color surfaceColor,
    required Color hairlineColor,
    required Color fg1,
    required Color fg2,
    required LumioColors customColors,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primaryColor,
        onPrimary: Colors.white,
        secondary: AppColors.primaryHi,
        onSecondary: Colors.white,
        error: AppColors.danger,
        onError: Colors.white,
        surface: surfaceColor,
        onSurface: fg1,
        outline: hairlineColor,
      ),

      textTheme: TextTheme(
        displayLarge: AppTextStyles.display(color: fg1),
        displayMedium: AppTextStyles.display(color: fg1),
        headlineLarge: AppTextStyles.h1(color: fg1),
        headlineMedium: AppTextStyles.h1(color: fg1),
        titleLarge: AppTextStyles.h2(color: fg1),
        bodyLarge: AppTextStyles.body(color: fg1),
        bodyMedium: AppTextStyles.secondary(color: fg2),
        labelLarge: AppTextStyles.caption(color: fg2),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: fg1, size: 22),
        actionsIconTheme: IconThemeData(color: fg1, size: 22),
        titleTextStyle: AppTextStyles.h1(color: fg1),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: backgroundColor,
        elevation: 0,
        selectedItemColor: primaryColor,
        unselectedItemColor: fg2,
        selectedLabelStyle: AppTextStyles.caption(color: primaryColor).copyWith(fontWeight: AppTextStyles.weightSemibold),
        unselectedLabelStyle: AppTextStyles.caption(color: fg2).copyWith(fontWeight: AppTextStyles.weightMedium),
        type: BottomNavigationBarType.fixed,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: hairlineColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: hairlineColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        labelStyle: AppTextStyles.body(color: fg2),
        floatingLabelStyle: AppTextStyles.caption(color: AppColors.primary),
        alignLabelWithHint: true,
      ),

      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          side: BorderSide(color: hairlineColor),
        ),
      ),

      extensions: [
        customColors,
      ],
    );
  }
}

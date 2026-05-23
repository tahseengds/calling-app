import 'package:flutter/material.dart';

/// FamilyLink design-system colour tokens extracted from colors_and_type.css
/// and Atoms.jsx. Use these instead of raw hex values throughout the app.
abstract final class AppColors {
  // ── Accent palette ──────────────────────────────────────────────────────
  static const primary      = Color(0xFF5B7CFA);
  static const danger       = Color(0xFFFF6B6B);
  static const success      = Color(0xFF34C77B);
  /// 25 % opaque primary — used for pill button shadows.
  static const primaryShadow = Color(0x405B7CFA);
  /// 12 % opaque primary — used for active bottom-nav pill.
  static const primaryPill   = Color(0x1F5B7CFA);

  // ── Dark theme surfaces ──────────────────────────────────────────────────
  static const darkBg             = Color(0xFF1A2235);
  static const darkSurface        = Color(0xFF222B42);
  static const darkSurfaceLo      = Color(0xFF1F273C);
  static const darkSurfaceHi      = Color(0xFF2A344E);
  static const darkHairline       = Color(0xFF37425E);
  static const darkHairlineStrong = Color(0xFF4A5878);
  static const darkFg1            = Color(0xFFF2F4F8);
  static const darkFg2            = Color(0xFF9AA3B8);
  static const darkFg3            = Color(0xFF6E7895);

  // ── Light theme surfaces ─────────────────────────────────────────────────
  static const lightBg        = Color(0xFFF4F6FB);
  static const lightSurface   = Color(0xFFFFFFFF);
  static const lightSurfaceLo = Color(0xFFF8FAFE);
  static const lightSurfaceHi = Color(0xFFF0F3FA);
  static const lightHairline  = Color(0xFFE3E7F0);
  static const lightFg1 = Color(0xFF1A2235);
  static const lightFg2 = Color(0xFF6B7488);

  // ── Avatar tints — deterministic, from Atoms.jsx tintFor() ───────────────
  static const _avatarTints = [
    Color(0xFF6A7AA8),
    Color(0xFF8B7AA8),
    Color(0xFFA87A8B),
    Color(0xFF7AA89E),
    Color(0xFFA89B7A),
  ];

  /// Returns a stable background tint for an avatar based on the user's name.
  static Color avatarTintFor(String name) {
    final hash = name.codeUnits.fold(0, (h, c) => h + c);
    return _avatarTints[hash % _avatarTints.length];
  }
}

/// Convenience extension — resolves the right colour for the current brightness.
extension AppColorsX on ThemeData {
  bool get isDark => brightness == Brightness.dark;
  Color get fg1 => isDark ? AppColors.darkFg1 : AppColors.lightFg1;
  Color get fg2 => isDark ? AppColors.darkFg2 : AppColors.lightFg2;
  Color get fg3 => isDark ? AppColors.darkFg3 : AppColors.lightFg2;
  Color get appSurface => isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get appSurfaceLo => isDark ? AppColors.darkSurfaceLo : AppColors.lightSurfaceLo;
  Color get hairline => isDark ? AppColors.darkHairline : AppColors.lightHairline;
}

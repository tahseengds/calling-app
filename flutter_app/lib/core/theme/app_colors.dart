import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Shared Accents
  static const Color primary = Color(0xFF5B7CFA);
  static const Color primaryHi = Color(0xFF7A93FB);
  static const Color primaryLo = Color(0xFF4566D8);
  static const Color primaryPill = Color(0x1F5B7CFA); // 12% opaque primary for nav/icon buttons

  static const Color danger = Color(0xFFFF6B6B);
  static const Color dangerHi = Color(0xFFFF8888);
  static const Color dangerLo = Color(0xFFE55757);

  static const Color success = Color(0xFF34C77B);
  static const Color successHi = Color(0xFF4DD68F);
  static const Color successLo = Color(0xFF2BAA68);

  // Avatar backgrounds
  static const List<Color> avatarTints = [
    Color(0xFF6A7AA8),
    Color(0xFF8B7AA8),
    Color(0xFFA87A8B),
    Color(0xFF7AA89E),
    Color(0xFFA89B7A),
  ];

  static Color avatarTintFor(String name) {
    final hash = name.codeUnits.fold(0, (h, c) => h + c);
    return avatarTints[hash % avatarTints.length];
  }

  // Dark Theme
  static const Color darkBg = Color(0xFF1A2235);
  static const Color darkSurface = Color(0xFF222B42);
  static const Color darkSurfaceHi = Color(0xFF2A344E);
  static const Color darkSurfaceLo = Color(0xFF1F273C);
  static const Color darkHairline = Color(0xFF37425E);
  static const Color darkHairlineStrong = Color(0xFF4A5878);
  static const Color darkFg1 = Color(0xFFF2F4F8);
  static const Color darkFg2 = Color(0xFF9AA3B8);
  static const Color darkFg3 = Color(0xFF6E7895);
  static const Color darkScrim = Color(0x8C0A101E); // rgba(10, 16, 30, .55)
  
  // Light Theme
  static const Color lightBg = Color(0xFFF4F6FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHi = Color(0xFFF0F3FA);
  static const Color lightSurfaceLo = Color(0xFFF8FAFE);
  static const Color lightHairline = Color(0xFFE3E7F0);
  static const Color lightHairlineStrong = Color(0xFFCDD4E1);
  static const Color lightFg1 = Color(0xFF1A2235);
  static const Color lightFg2 = Color(0xFF6B7488);
  static const Color lightFg3 = Color(0xFF9098A8);
  static const Color lightScrim = Color(0x591A2235); // rgba(26, 34, 53, .35)
}

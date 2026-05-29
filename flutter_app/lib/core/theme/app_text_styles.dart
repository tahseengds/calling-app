import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  AppTextStyles._();

  static const double sizeDisplay = 28.0;
  static const double sizeH1 = 24.0;
  static const double sizeH2 = 22.0;
  static const double sizeBody = 16.0;
  static const double sizeSecondary = 14.0;
  static const double sizeCaption = 13.0;

  static const double leadingTight = 1.25;
  static const double leadingBody = 1.4;

  static const FontWeight weightRegular = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightSemibold = FontWeight.w600;
  static const FontWeight weightBold = FontWeight.w700;

  static const double trackingTight = -0.01;
  static const double trackingBody = 0.0;

  /// Emoji glyph fallback. Inter has no emoji, and many devices' system fonts
  /// lack the newest Unicode emoji (they render as ▯ "no glyph"). Bundling
  /// Noto Color Emoji and listing it as a fallback makes ALL emoji render
  /// consistently. Requires assets/fonts/NotoColorEmoji.ttf (declared in
  /// pubspec). Applied to every style below via copyWith.
  static const List<String> emojiFallback = ['NotoColorEmoji'];

  // Base Inter style builder
  static TextStyle display({required Color color}) => GoogleFonts.inter(
        fontSize: sizeDisplay,
        fontWeight: weightSemibold,
        height: leadingTight,
        letterSpacing: trackingTight,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle h1({required Color color}) => GoogleFonts.inter(
        fontSize: sizeH1,
        fontWeight: weightSemibold,
        height: leadingTight,
        letterSpacing: trackingTight,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle h2({required Color color}) => GoogleFonts.inter(
        fontSize: sizeH2,
        fontWeight: weightSemibold,
        height: leadingTight,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle body({required Color color}) => GoogleFonts.inter(
        fontSize: sizeBody,
        fontWeight: weightRegular,
        height: leadingBody,
        letterSpacing: trackingBody,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle bodyMedium({required Color color}) => GoogleFonts.inter(
        fontSize: sizeBody,
        fontWeight: weightMedium,
        height: leadingBody,
        letterSpacing: trackingBody,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle bodySemibold({required Color color}) => GoogleFonts.inter(
        fontSize: sizeBody,
        fontWeight: weightSemibold,
        height: leadingBody,
        letterSpacing: trackingBody,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle secondary({required Color color}) => GoogleFonts.inter(
        fontSize: sizeSecondary,
        fontWeight: weightRegular,
        height: leadingBody,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle secondaryMedium({required Color color}) => GoogleFonts.inter(
        fontSize: sizeSecondary,
        fontWeight: weightMedium,
        height: leadingBody,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle secondarySemibold({required Color color}) => GoogleFonts.inter(
        fontSize: sizeSecondary,
        fontWeight: weightSemibold,
        height: leadingBody,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle caption({required Color color}) => GoogleFonts.inter(
        fontSize: sizeCaption,
        fontWeight: weightMedium,
        height: leadingTight,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle captionSemibold({required Color color}) => GoogleFonts.inter(
        fontSize: sizeCaption,
        fontWeight: weightSemibold,
        height: leadingTight,
        color: color,
      ).copyWith(fontFamilyFallback: emojiFallback);
}

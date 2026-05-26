import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';

/// Small pill badge showing call quality level ('good' | 'medium' | 'poor').
class CallQualityBadge extends StatelessWidget {
  final String quality;
  final bool darkBackground;

  const CallQualityBadge({
    super.key,
    required this.quality,
    this.darkBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final lumioColors = context.lumioColors;
    final isDark = darkBackground ||
        Theme.of(context).brightness == Brightness.dark;

    final (Color dot, String label) = switch (quality) {
      'poor' => (AppColors.danger, 'Poor connection'),
      'medium' => (const Color(0xFFF0A93B), 'Choppy connection'),
      _ => (AppColors.success, 'Good connection'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        border: Border.all(
            color: isDark ? Colors.white12 : lumioColors.hairline),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTextStyles.caption(
              color: darkBackground ? Colors.white70 : lumioColors.fg2,
            ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Compact inline quality dot + label for the video call header.
class CallQualityDot extends StatelessWidget {
  final String quality;

  const CallQualityDot({super.key, required this.quality});

  @override
  Widget build(BuildContext context) {
    final (Color dot, String label) = switch (quality) {
      'poor' => (AppColors.danger, 'Poor'),
      'medium' => (const Color(0xFFF0A93B), 'Choppy'),
      _ => (AppColors.success, 'Good'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'lumio_icons.dart';

/// 48×48 circular back control from the Lumio design system.
class LumioBackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const LumioBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? AppColors.darkSurfaceLo : AppColors.lightSurfaceLo,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed ?? () => Navigator.maybePop(context),
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(LumioIcons.back, size: 22),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Path to the Lumio brand logo. Same asset the native splash screen
/// uses (declared in pubspec's flutter_native_splash → image), so the
/// in-app branding matches the cold-start splash pixel-for-pixel.
const String _kLumioLogoAsset = 'assets/lumin-logo-splash.png';

/// The Lumio brand mark — renders the asset logo at the requested size.
///
/// [color] optionally tints the image (useful when the logo sits on a
/// colored background and needs to be re-coloured for contrast — e.g.
/// the white-on-primary variant inside [LumioSplashHero]). Pass `null`
/// to render the asset in its native colours.
class LumioMark extends StatelessWidget {
  final double size;
  final Color? color;

  const LumioMark({super.key, this.size = 40, this.color});

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      _kLumioLogoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Use mediumQuality scaling so the small (~36 px) logo bar still
      // looks crisp without paying the bandwidth cost of high-quality
      // resampling for every frame.
      filterQuality: FilterQuality.medium,
    );

    if (color != null) {
      image = ColorFiltered(
        colorFilter: ColorFilter.mode(color!, BlendMode.srcIn),
        child: image,
      );
    }

    return SizedBox(width: size, height: size, child: image);
  }
}

/// Small horizontal bar with the Lumio mark — used as a header logo on
/// auth screens (login, register).
class LumioLogoBar extends StatelessWidget {
  const LumioLogoBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 56,
      child: Center(child: LumioMark(size: 36)),
    );
  }
}

/// Big "hero" presentation of the logo for the splash screen — a soft
/// radial halo around a rounded-square pedestal containing the mark.
///
/// The pedestal is drawn in the brand primary so the logo reads as
/// "Lumio" the moment the app appears, before any text loads.
class LumioSplashHero extends StatelessWidget {
  const LumioSplashHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Soft halo behind the pedestal.
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.primary.withAlpha(55),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Rounded-square pedestal with the logo inside.
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(70),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          // Tint to white so the logo contrasts the primary pedestal.
          // If your logo asset already includes its own colour scheme
          // and you'd rather show it untinted, pass `color: null`.
          child: const Center(
            child: LumioMark(size: 64, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

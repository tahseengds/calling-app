import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Lumio wordmark + linked-circles mark from lumio-screens-design.html.
class LumioMark extends StatelessWidget {
  final double size;
  final Color? color;

  const LumioMark({super.key, this.size = 40, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return CustomPaint(
      size: Size(size, size * 0.55),
      painter: _LumioMarkPainter(c),
    );
  }
}

class _LumioMarkPainter extends CustomPainter {
  final Color color;
  _LumioMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.14
      ..strokeCap = StrokeCap.round;

    final r = size.height * 0.42;
    final left = Offset(r + size.height * 0.08, size.height / 2);
    final right = Offset(size.width - r - size.height * 0.08, size.height / 2);
    canvas.drawCircle(left, r, paint);
    canvas.drawCircle(right, r, paint);
  }

  @override
  bool shouldRepaint(covariant _LumioMarkPainter old) => old.color != color;
}

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

class LumioSplashHero extends StatelessWidget {
  const LumioSplashHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
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
          child: const Center(
            child: LumioMark(size: 52, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

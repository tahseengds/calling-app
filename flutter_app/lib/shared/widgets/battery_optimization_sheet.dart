import 'package:flutter/material.dart';
import '../../core/services/battery_optimization_service.dart';
import '../../core/theme/app_colors.dart';

/// Show the "Don't miss calls" battery optimization bottom sheet.
Future<void> showBatteryOptimizationSheet(
  BuildContext context,
  BatteryOptimizationService svc,
  OemHints oem,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: false,
    builder: (_) => _BatterySheet(svc: svc, oem: oem),
  );
}

class _BatterySheet extends StatefulWidget {
  final BatteryOptimizationService svc;
  final OemHints oem;
  const _BatterySheet({required this.svc, required this.oem});

  @override
  State<_BatterySheet> createState() => _BatterySheetState();
}

class _BatterySheetState extends State<_BatterySheet> {
  bool _busy = false;

  Future<void> _onOpenSettings() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (widget.oem.isAggressive) {
        final opened = await widget.svc.openOemAutoStartSettings();
        if (!opened) await widget.svc.openAppSettings();
      } else {
        await widget.svc.requestIgnoreBatteryOptimizations();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sheetBg =
        isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final handleColor =
        isDark ? AppColors.darkHairlineStrong : AppColors.lightHairlineStrong;
    final borderColor =
        isDark ? AppColors.darkHairline : AppColors.lightHairline;
    final fg1 = isDark ? AppColors.darkFg1 : AppColors.lightFg1;
    final fg2 = isDark ? AppColors.darkFg2 : AppColors.lightFg2;
    final secFg = isDark ? AppColors.darkFg2 : AppColors.lightFg2;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: borderColor),
          left: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x52000000), blurRadius: 32, offset: Offset(0, -8)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Illustration
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _BatteryIllustration(isDark: isDark),
            ),

            // Title
            Text(
              "Don't miss calls",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: fg1,
                letterSpacing: -0.22,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // Body
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                "When your phone sleeps, Lumio might stop receiving calls. Turn off battery optimization so your calls and chats come through.",
                style: TextStyle(fontSize: 15, color: fg2, height: 1.55),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // Open settings button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : _onOpenSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  elevation: 0,
                  shadowColor:
                      AppColors.primary.withValues(alpha: 0.28),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Open settings',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: 10),

            // Skip
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: secFg,
                  side: BorderSide(color: borderColor),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Skip for now',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple phone + zzz illustration drawn with Canvas.
class _BatteryIllustration extends StatelessWidget {
  final bool isDark;
  const _BatteryIllustration({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 120,
      child: CustomPaint(painter: _BatteryPainter(isDark: isDark)),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final bool isDark;
  const _BatteryPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Glow circle
    final glowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 56, glowPaint);

    // Phone body
    final phonePaint = Paint()
      ..color = isDark ? AppColors.darkSurface : AppColors.lightSurfaceLo
      ..style = PaintingStyle.fill;
    final phoneBorderPaint = Paint()
      ..color = isDark ? AppColors.darkFg1 : AppColors.lightFg1
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 30, cy - 46, 60, 86),
      const Radius.circular(12),
    );
    canvas.drawRRect(phoneRect, phonePaint);
    canvas.drawRRect(phoneRect, phoneBorderPaint);

    // Screen circle
    final screenPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(cx, cy + 8), 16, screenPaint);

    // Status bar
    final barPaint = Paint()
      ..color = isDark ? AppColors.darkHairline : AppColors.lightHairline
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 11, cy + 33, 22, 4), const Radius.circular(2)),
      barPaint,
    );

    // Battery in corner (red = low)
    final batteryBorderPaint = Paint()
      ..color = isDark ? AppColors.darkFg1 : AppColors.lightFg1
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final batteryFillPaint = Paint()
      ..color = AppColors.danger
      ..style = PaintingStyle.fill;
    final batteryTipPaint = Paint()
      ..color = isDark ? AppColors.darkFg1 : AppColors.lightFg1
      ..style = PaintingStyle.fill;

    final bx = cx + 26.0;
    final by = cy - 36.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, 30, 14),
          const Radius.circular(3)),
      batteryBorderPaint,
    );
    canvas.drawRect(Rect.fromLTWH(bx + 2, by + 2, 14, 10), batteryFillPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(bx + 30, by + 4, 3, 7), const Radius.circular(1)),
      batteryTipPaint,
    );

    // zzz text (drawn as simple circles/arcs approximation via TextPainter)
    final zStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppColors.primary.withValues(alpha: 0.6),
    );
    final zStyleMd = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AppColors.primary.withValues(alpha: 0.8),
    );
    final zStyleLg = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AppColors.primary,
    );

    void drawZ(String z, TextStyle style, double x, double y) {
      final tp = TextPainter(
        text: TextSpan(text: z, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }

    drawZ('z', zStyle, cx + 36, cy - 6);
    drawZ('z', zStyleMd, cx + 44, cy - 14);
    drawZ('z', zStyleLg, cx + 54, cy - 26);
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter old) => old.isDark != isDark;
}

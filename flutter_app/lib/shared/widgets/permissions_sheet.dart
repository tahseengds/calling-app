import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';

/// Show the one-time permissions onboarding sheet.
/// Requests notifications + microphone + camera.
Future<void> showPermissionsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: false,
    builder: (_) => const _PermissionsSheet(),
  );
}

class _PermissionsSheet extends StatefulWidget {
  const _PermissionsSheet();

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  bool _notifGranted = false;
  bool _micGranted = false;
  bool _camGranted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final results = await Future.wait([
      Permission.notification.status,
      Permission.microphone.status,
      Permission.camera.status,
    ]);
    if (!mounted) return;
    setState(() {
      _notifGranted = results[0].isGranted;
      _micGranted = results[1].isGranted;
      _camGranted = results[2].isGranted;
    });
  }

  Future<void> _requestAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final map = await [
        Permission.notification,
        Permission.microphone,
        Permission.camera,
      ].request();
      if (!mounted) return;
      setState(() {
        _notifGranted = map[Permission.notification]?.isGranted ?? false;
        _micGranted = map[Permission.microphone]?.isGranted ?? false;
        _camGranted = map[Permission.camera]?.isGranted ?? false;
      });
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final rowBg =
        isDark ? AppColors.darkSurfaceLo : AppColors.lightSurfaceLo;
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

            // Icon row
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PermIcon(
                    color: AppColors.primary,
                    icon: LucideIcons.bell,
                    borderColor: borderColor,
                  ),
                  const SizedBox(width: 12),
                  _PermIcon(
                    color: AppColors.success,
                    icon: LucideIcons.mic,
                    borderColor: borderColor,
                  ),
                  const SizedBox(width: 12),
                  _PermIcon(
                    color: const Color(0xFFF0A93B),
                    icon: LucideIcons.video,
                    borderColor: borderColor,
                  ),
                ],
              ),
            ),

            // Title
            Text(
              'A few permissions, please',
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
            SizedBox(
              width: 280,
              child: Text(
                "Lumio needs these so calls reach you. We only use them when you're on a call or expecting one.",
                style: TextStyle(fontSize: 15, color: fg2, height: 1.55),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            // Permission rows
            _PermRow(
              granted: _notifGranted,
              label: 'Notifications',
              desc: 'So you know someone is calling.',
              rowBg: rowBg,
              borderColor: borderColor,
              fg1: fg1,
              fg2: fg2,
            ),
            const SizedBox(height: 8),
            _PermRow(
              granted: _micGranted,
              label: 'Microphone',
              desc: 'For voice and video calls.',
              rowBg: rowBg,
              borderColor: borderColor,
              fg1: fg1,
              fg2: fg2,
            ),
            const SizedBox(height: 8),
            _PermRow(
              granted: _camGranted,
              label: 'Camera',
              desc: 'For video calls.',
              rowBg: rowBg,
              borderColor: borderColor,
              fg1: fg1,
              fg2: fg2,
            ),
            const SizedBox(height: 16),

            // Allow button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : _requestAll,
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
                        'Allow',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: 10),

            // Not now
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
                  'Not now',
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

class _PermIcon extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Color borderColor;

  const _PermIcon({
    required this.color,
    required this.icon,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Center(child: Icon(icon, color: color, size: 28)),
      );
}

class _PermRow extends StatelessWidget {
  final bool granted;
  final String label;
  final String desc;
  final Color rowBg;
  final Color borderColor;
  final Color fg1;
  final Color fg2;

  const _PermRow({
    required this.granted,
    required this.label,
    required this.desc,
    required this.rowBg,
    required this.borderColor,
    required this.fg1,
    required this.fg2,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: granted
                    ? AppColors.success
                    : borderColor,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(LucideIcons.check, size: 14, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: fg1)),
                  const SizedBox(height: 1),
                  Text(desc,
                      style: TextStyle(fontSize: 12, color: fg2)),
                ],
              ),
            ),
          ],
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/theme/app_colors.dart';

enum PermissionDeniedType { microphone, camera }

/// Full-screen "permanently denied" gate. Push as a fullscreen dialog route.
///
/// Pops `true` automatically once the relevant permission becomes granted —
/// e.g. the user taps "Open settings", flips the toggle, and returns: the
/// app resumes, we re-check, and the caller (which awaited the route result)
/// can retry the call without a second tap.
class PermissionDeniedScreen extends StatefulWidget {
  final PermissionDeniedType type;
  const PermissionDeniedScreen({super.key, required this.type});

  @override
  State<PermissionDeniedScreen> createState() => _PermissionDeniedScreenState();
}

class _PermissionDeniedScreenState extends State<PermissionDeniedScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheck();
    }
  }

  Future<void> _recheck() async {
    final perm = widget.type == PermissionDeniedType.microphone
        ? Permission.microphone
        : Permission.camera;
    final status = await perm.status;
    if (status.isGranted && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMic = widget.type == PermissionDeniedType.microphone;

    final fg1 = isDark ? AppColors.darkFg1 : AppColors.lightFg1;
    final fg2 = isDark ? AppColors.darkFg2 : AppColors.lightFg2;
    final cardBg = isDark ? AppColors.darkSurfaceLo : AppColors.lightSurfaceLo;
    final cardBorder = isDark ? AppColors.darkHairline : AppColors.lightHairline;
    final secBorder =
        isDark ? AppColors.darkHairlineStrong : AppColors.lightHairlineStrong;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [
                    Color(0xFF1F2A47),
                    Color(0xFF1A2235),
                    Color(0xFF161D2D),
                  ]
                : const [Color(0xFFF4F6FB), Color(0xFFFFFFFF)],
            stops: isDark ? const [0.0, 0.6, 1.0] : const [0.0, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Close button ─────────────────────────────────────────
              SizedBox(
                height: 56,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close, color: fg1, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shape: const CircleBorder(),
                    ),
                  ),
                ),
              ),

              // ── Main content ─────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Red icon circle
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.32),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            isMic
                                ? Icons.mic_off_rounded
                                : Icons.videocam_off_rounded,
                            size: 52,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Title
                      Text(
                        isMic
                            ? 'Microphone access needed'
                            : 'Camera access needed',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: fg1,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),

                      // Body
                      SizedBox(
                        width: 280,
                        child: Text(
                          isMic
                              ? "Lumio can't connect a call without it. Open settings and allow microphone for Lumio."
                              : "Lumio can't connect video without it. Open settings and allow camera for Lumio — you can still take an audio call.",
                          style: TextStyle(
                            fontSize: 15,
                            color: fg2,
                            height: 1.55,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Steps card
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TO ALLOW IT',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: fg2,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Settings › Apps › Lumio › Permissions'
                                ' › ${isMic ? 'Microphone' : 'Camera'}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: fg1,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Buttons ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: openAppSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          elevation: 0,
                          shadowColor: AppColors.primary.withValues(alpha: 0.28),
                        ),
                        child: const Text(
                          'Open settings',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: fg1,
                          side: BorderSide(color: secBorder),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Not now',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

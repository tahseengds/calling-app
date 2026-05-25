import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/lumio_icons.dart';

class OutgoingCallScreen extends StatefulWidget {
  final String name;
  final String kind; // 'voice' or 'video'

  const OutgoingCallScreen({
    super.key,
    required this.name,
    required this.kind,
  });

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> with TickerProviderStateMixin {
  late AnimationController _ringController1;
  late AnimationController _ringController2;
  late AnimationController _dotController;
  Timer? _autoAnswerTimer;

  @override
  void initState() {
    super.initState();

    // Pulse animations
    _ringController1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _ringController2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _ringController2.repeat();
    });

    // Dot loading animation
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    // Simulating call connect after 4 seconds
    _autoAnswerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        context.pushReplacement('/call/active?kind=${widget.kind}&name=${Uri.encodeComponent(widget.name)}');
      }
    });
  }

  @override
  void dispose() {
    _ringController1.dispose();
    _ringController2.dispose();
    _dotController.dispose();
    _autoAnswerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final lumioColors = context.lumioColors;
    final isVideo = widget.kind == 'video';
    final subColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      body: Stack(
        children: [
          // ── Radial Gradient Backdrop ────────────────────────────────────
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: isDark
                      ? [
                          const Color(0x4C5B7CFA),
                          const Color(0x2E5B7CFA),
                          const Color(0xFF161D2D),
                        ]
                      : [
                          const Color(0x2E5B7CFA),
                          const Color(0x1F5B7CFA),
                          const Color(0xFFFFFFFF),
                        ],
                  center: const Alignment(0, -1.0),
                  radius: 1.2,
                ),
              ),
            ),
          ),

          // ── Status Pill at Top ──────────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                    border: Border.all(color: lumioColors.hairline),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVideo ? LumioIcons.video : LumioIcons.phone,
                        size: 14,
                        color: lumioColors.fg2,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'OUTGOING ${widget.kind.toUpperCase()} CALL',
                        style: AppTextStyles.caption(color: lumioColors.fg2).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Local Video PIP Preview (Video mode only) ───────────────────
          if (isVideo)
            Positioned(
              right: 16,
              top: 76,
              child: Container(
                width: 96,
                height: 132,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      // Silhouette Custom Painter PIP
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _CameraPipPainter(),
                        ),
                      ),
                      // Camera flip icon
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                          child: Icon(Icons.flip_camera_ios_outlined, size: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Avatar + Dialing ripples ───────────────────────────────────
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Ripple 1
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1.15).animate(_ringController1),
                        child: FadeTransition(
                          opacity: Tween<double>(begin: 0.55, end: 0.0).animate(_ringController1),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      // Ripple 2
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1.15).animate(_ringController2),
                        child: FadeTransition(
                          opacity: Tween<double>(begin: 0.55, end: 0.0).animate(_ringController2),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      // Avatar
                      UserAvatar(
                        displayName: widget.name,
                        radius: 80,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.name,
                  style: AppTextStyles.display(color: lumioColors.fg1).copyWith(fontSize: 30),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Ringing',
                      style: TextStyle(fontSize: 15, color: subColor),
                    ),
                    const SizedBox(width: 4),
                    _buildLoadingDots(subColor),
                  ],
                ),
              ],
            ),
          ),

          // ── End Call Hangup Actions ────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    // Cancel timer & go back
                    _autoAnswerTimer?.cancel();
                    context.pop();
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x6BFF6B6B),
                          blurRadius: 32,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationZ(2.356),
                        child: const Icon(LumioIcons.phone, size: 30, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingDots(Color color) {
    return AnimatedBuilder(
      animation: _dotController,
      builder: (context, child) {
        final val = _dotController.value;
        return Row(
          children: List.generate(3, (i) {
            final double offset = i * 0.33;
            double opacity = (val - offset) % 1.0;
            if (opacity < 0.2) {
              opacity = 0.35 + (opacity / 0.2) * 0.65;
            } else {
              opacity = 1.0 - ((opacity - 0.2) / 0.8) * 0.65;
            }
            return Opacity(
              opacity: opacity.clamp(0.35, 1.0),
              child: Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _CameraPipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fill Gradient
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3D4C72), Color(0xFF0F1525)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // Silhouette head
    final headPaint = Paint()..color = const Color(0xFF0B0F1A).withValues(alpha: 0.85);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.44), 20, headPaint);

    // Shoulder curve
    final path = Path()
      ..moveTo(size.width * 0.16, size.height)
      ..quadraticBezierTo(size.width * 0.16, size.height * 0.7, size.width * 0.5, size.height * 0.7)
      ..quadraticBezierTo(size.width * 0.84, size.height * 0.7, size.width * 0.84, size.height)
      ..close();
    canvas.drawPath(path, headPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

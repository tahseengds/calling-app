import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/lumio_icons.dart';

class IncomingCallScreen extends StatefulWidget {
  final String name;
  final String kind; // 'voice' or 'video'

  const IncomingCallScreen({
    super.key,
    this.name = 'Grandma Rose',
    this.kind = 'video',
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with TickerProviderStateMixin {
  late AnimationController _ringController1;
  late AnimationController _ringController2;
  late AnimationController _bobController;
  
  late String _currentTime;

  @override
  void initState() {
    super.initState();
    _currentTime = _formatTime(DateTime.now());
    
    // Periodically update clock
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = _formatTime(DateTime.now());
        });
      }
    });

    // Pulsing rings animations
    _ringController1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _ringController2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _ringController2.repeat();
      }
    });

    // Bobbing accept icon animation
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ringController1.dispose();
    _ringController2.dispose();
    _bobController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final lumioColors = context.lumioColors;
    final isVideo = widget.kind == 'video';
    final muted = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: isDark
                ? [const Color(0x525B7CFA), const Color(0xFF161D2D)]
                : [const Color(0x2E5B7CFA), const Color(0xFFFFFFFF)],
            center: const Alignment(0, -1.0),
            radius: 1.2,
          ),
        ),
        child: Column(
          children: [
            // ── Lock Screen Clock ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 64, left: 24, right: 24),
              child: Column(
                children: [
                  Text(
                    'INCOMING ${widget.kind.toUpperCase()} CALL',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: muted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _currentTime,
                    style: TextStyle(
                      fontSize: 60,
                      fontWeight: FontWeight.w300,
                      color: lumioColors.fg1,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sunday, March 15', // Mock static date
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ],
              ),
            ),

            // ── Pulsing Avatar ─────────────────────────────────────────────
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 260,
                      height: 260,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulsing Ring 1
                          ScaleTransition(
                            scale: Tween<double>(begin: 0.75, end: 1.15).animate(_ringController1),
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
                          // Pulsing Ring 2
                          ScaleTransition(
                            scale: Tween<double>(begin: 0.75, end: 1.15).animate(_ringController2),
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
                          // Static Avatar
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
                      style: AppTextStyles.display(color: lumioColors.fg1).copyWith(fontSize: 32),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Lumio · ${isVideo ? 'video' : 'voice'} call',
                      style: TextStyle(fontSize: 15, color: muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            // ── Quick Reply Chips ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: ["I'll call back", "On my way", "Can't talk now"].map((s) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                      border: Border.all(color: lumioColors.hairline),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      s,
                      style: AppTextStyles.secondaryMedium(color: lumioColors.fg1).copyWith(fontSize: 13),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ── Decline / Accept Buttons ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 32, right: 32, bottom: 56),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Decline
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          // Go back
                          context.pop();
                        },
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x73FF6B6B),
                                blurRadius: 36,
                                offset: Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.rotationZ(2.356), // rotate 135 deg to make phone look declined
                              child: const Icon(LumioIcons.phone, size: 32, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Decline',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: lumioColors.fg1,
                        ),
                      ),
                    ],
                  ),
                  // Accept
                  Column(
                    children: [
                      SlideTransition(
                        position: Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.05)).animate(_bobController),
                        child: GestureDetector(
                          onTap: () {
                            // Go to active call screen
                            context.pushReplacement('/call/active?kind=${widget.kind}&name=${Uri.encodeComponent(widget.name)}');
                          },
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x7334C77B),
                                  blurRadius: 36,
                                  offset: Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                isVideo ? LumioIcons.video : LumioIcons.phone,
                                size: 32,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Accept',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: lumioColors.fg1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

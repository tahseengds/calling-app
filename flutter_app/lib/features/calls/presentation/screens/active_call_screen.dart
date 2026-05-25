import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/lumio_icons.dart';

class ActiveCallScreen extends StatefulWidget {
  final String name;
  final String kind; // 'voice' or 'video'

  const ActiveCallScreen({
    super.key,
    this.name = 'Grandma Rose',
    this.kind = 'video',
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> with TickerProviderStateMixin {
  late String _currentKind;
  int _secondsElapsed = 228; // Start at 03:48 (228 seconds)
  Timer? _timer;

  // Active call states
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _showControls = true;
  String _quality = 'good'; // 'good', 'medium', 'poor'
  bool _isReconnecting = false;

  late AnimationController _breathController;

  @override
  void initState() {
    super.initState();
    _currentKind = widget.kind;

    // Call duration timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsElapsed++;
          
          // Randomly simulate connection changes for demonstration
          if (_secondsElapsed % 20 == 0) {
            _quality = 'medium';
          } else if (_secondsElapsed % 20 == 5) {
            _quality = 'poor';
          } else if (_secondsElapsed % 20 == 8) {
            _isReconnecting = true;
          } else if (_secondsElapsed % 20 == 12) {
            _isReconnecting = false;
            _quality = 'good';
          }
        });
      }
    });

    // Breathing pulse ring animation (Audio call)
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breathController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _currentKind == 'video';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final lumioColors = context.lumioColors;
    final formattedTime = _formatDuration(_secondsElapsed);
    final otherName = widget.name;

    if (isVideo) {
      return _buildVideoCallLayout(otherName, formattedTime, lumioColors, isDark);
    } else {
      return _buildAudioCallLayout(otherName, formattedTime, lumioColors, isDark);
    }
  }

  // ── Video Call Layout ───────────────────────────────────────────────────
  Widget _buildVideoCallLayout(String name, String duration, LumioColors colors, bool isDark) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: Stack(
        children: [
          // Remote Video Feed Placeholder
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showControls = !_showControls;
                });
              },
              child: CustomPaint(
                painter: _RemoteVideoFeedPainter(),
              ),
            ),
          ),

          // PIP - Local Camera Preview
          AnimatedPositioned(
            duration: const Duration(milliseconds: 2400),
            curve: Curves.fastOutSlowIn,
            right: 16,
            top: _showControls ? 80 : 44,
            child: Container(
              width: 100,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24, width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CustomPaint(
                  painter: _LocalVideoFeedPainter(),
                ),
              ),
            ),
          ),

          // Top Info Bar (autohides)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 44, 16, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                duration,
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                              const SizedBox(width: 8),
                              _buildVideoQualityIndicator(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Control Overlay (autohides)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            left: 16,
            right: 16,
            bottom: _showControls ? 32 : -100,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xE60F1525), // rgba(15,21,37,0.7)
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildVideoControlBtn(
                      icon: _isMuted ? LumioIcons.micOff : LumioIcons.mic,
                      active: _isMuted,
                      onTap: () => setState(() => _isMuted = !_isMuted),
                    ),
                    _buildVideoControlBtn(
                      icon: LumioIcons.video,
                      active: true,
                      onTap: () {
                        setState(() {
                          _currentKind = 'voice';
                        });
                      },
                    ),
                    _buildVideoControlBtn(
                      icon: LumioIcons.history,
                      onTap: () {},
                    ),
                    _buildVideoControlBtn(
                      icon: LumioIcons.speaker,
                      active: _isSpeakerOn,
                      onTap: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                    ),
                    // Hangup red button
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 56,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x6BFF6B6B),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationZ(2.356),
                            child: const Icon(LumioIcons.phone, size: 22, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tap to show controls hint
          if (!_showControls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: Center(
                child: Text(
                  'Tap to show controls',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.55),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),

          // Reconnecting Overlay
          if (_isReconnecting) _buildReconnectingOverlay(),
        ],
      ),
    );
  }

  Widget _buildVideoControlBtn({
    required IconData icon,
    bool active = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 24,
        backgroundColor: active ? Colors.white : Colors.white.withValues(alpha: 0.10),
        foregroundColor: active ? const Color(0xFF1A2235) : Colors.white,
        child: Icon(icon, size: 22),
      ),
    );
  }

  Widget _buildVideoQualityIndicator() {
    Color qColor;
    String qText;
    if (_quality == 'good') {
      qColor = AppColors.success;
      qText = 'Good';
    } else if (_quality == 'medium') {
      qColor = const Color(0xFFF0A93B);
      qText = 'Choppy';
    } else {
      qColor = AppColors.danger;
      qText = 'Poor';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: qColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          qText,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  // ── Audio Call Layout ───────────────────────────────────────────────────
  Widget _buildAudioCallLayout(String name, String duration, LumioColors colors, bool isDark) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: isDark
                ? [const Color(0x335B7CFA), const Color(0xFF161D2D)]
                : [const Color(0x1A5B7CFA), const Color(0xFFFFFFFF)],
            center: const Alignment(0, -1.0),
            radius: 1.2,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Top Info
                Padding(
                  padding: const EdgeInsets.only(top: 64, left: 24, right: 24),
                  child: Column(
                    children: [
                      Text(
                        'AUDIO CALL · $duration',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black54,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildQualityBadge(colors, isDark),
                    ],
                  ),
                ),

                // Pulsing Avatar
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 220,
                          height: 220,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ScaleTransition(
                                scale: Tween<double>(begin: 0.96, end: 1.08).animate(_breathController),
                                child: FadeTransition(
                                  opacity: Tween<double>(begin: 0.18, end: 0.28).animate(_breathController),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.primary, width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                              UserAvatar(
                                displayName: name,
                                radius: 92,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          name,
                          style: AppTextStyles.display(color: colors.fg1).copyWith(fontSize: 30),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          duration,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                // Controls
                Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, bottom: 56),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildAudioControlBtn(
                        icon: _isMuted ? LumioIcons.micOff : LumioIcons.mic,
                        label: _isMuted ? 'Mic off' : 'Mic',
                        active: _isMuted,
                        onTap: () => setState(() => _isMuted = !_isMuted),
                        colors: colors,
                        isDark: isDark,
                      ),
                      _buildAudioControlBtn(
                        icon: LumioIcons.speaker,
                        label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                        active: _isSpeakerOn,
                        onTap: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                        colors: colors,
                        isDark: isDark,
                      ),
                      // End call hangup
                      _buildAudioControlBtn(
                        icon: LumioIcons.phone,
                        label: 'End',
                        danger: true,
                        onTap: () => context.pop(),
                        colors: colors,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Reconnecting Overlay
            if (_isReconnecting) _buildReconnectingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioControlBtn({
    required IconData icon,
    required String label,
    bool active = false,
    bool danger = false,
    required VoidCallback onTap,
    required LumioColors colors,
    required bool isDark,
  }) {
    Color bg = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
    Color fg = colors.fg1;
    Border border = Border.all(color: colors.hairline);

    if (active) {
      bg = Colors.white;
      fg = const Color(0xFF1A2235);
      border = Border.all(color: Colors.transparent);
    }
    if (danger) {
      bg = AppColors.danger;
      fg = Colors.white;
      border = Border.all(color: Colors.transparent);
    }

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: bg,
              border: border,
              shape: BoxShape.circle,
              boxShadow: danger
                  ? const [
                      BoxShadow(
                        color: Color(0x6BFF6B6B),
                        blurRadius: 28,
                        offset: Offset(0, 10),
                      ),
                    ]
                  : (active
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null),
            ),
            child: Center(
              child: Transform(
                alignment: Alignment.center,
                transform: danger ? Matrix4.rotationZ(2.356) : Matrix4.identity(),
                child: Icon(icon, size: 24, color: fg),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          danger ? 'End' : label,
          style: TextStyle(fontSize: 12, color: colors.fg2, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildQualityBadge(LumioColors colors, bool isDark) {
    Color qColor;
    String qText;
    if (_quality == 'good') {
      qColor = AppColors.success;
      qText = 'Good connection';
    } else if (_quality == 'medium') {
      qColor = const Color(0xFFF0A93B);
      qText = 'Choppy connection';
    } else {
      qColor = AppColors.danger;
      qText = 'Poor connection';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: qColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            qText,
            style: AppTextStyles.caption(color: colors.fg2).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Reconnecting Overlay ─────────────────────────────────────────────────
  Widget _buildReconnectingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Reconnecting…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.01,
                ),
              ),
              SizedBox(height: 4),
              Text(
                "We'll keep your call going.",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteVideoFeedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fill Radial Gradient (Martinez Dad Mike remote feed mockup)
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF5B7CFA), Color(0xFF222B42), Color(0xFF0B0F1A)],
        center: Alignment(0, -0.32),
        radius: 0.7,
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // Head silhouette
    final silhouettePaint = Paint()..color = const Color(0xFF1A2235).withValues(alpha: 0.65);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.43), 120, silhouettePaint);

    // Shoulders silhouette
    final shoulderPaint = Paint()..color = const Color(0xFF0F1525).withValues(alpha: 0.85);
    final path = Path()
      ..moveTo(size.width * 0.1, size.height)
      ..quadraticBezierTo(size.width * 0.1, size.height * 0.73, size.width * 0.5, size.height * 0.73)
      ..quadraticBezierTo(size.width * 0.9, size.height * 0.73, size.width * 0.9, size.height)
      ..close();
    canvas.drawPath(path, shoulderPaint);

    // Skin highlight
    final facePaint = Paint()..color = const Color(0xFF3D4C72).withValues(alpha: 0.55);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.44, size.height * 0.39),
        width: 120,
        height: 156,
      ),
      facePaint,
    );

    // Eyes
    final featurePaint = Paint()..color = const Color(0xFF0B0F1A);
    canvas.drawCircle(Offset(size.width * 0.46, size.height * 0.41), 3, featurePaint);
    canvas.drawCircle(Offset(size.width * 0.54, size.height * 0.42), 3, featurePaint);

    // Smile
    final linePaint = Paint()
      ..color = const Color(0xFF0B0F1A)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.48, size.height * 0.47)
        ..quadraticBezierTo(size.width * 0.51, size.height * 0.49, size.width * 0.54, size.height * 0.48),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LocalVideoFeedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fill Gradient
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF7AA89E), Color(0xFF0F1525)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // Head silhouette
    final silhouettePaint = Paint()..color = const Color(0xFF0B0F1A).withValues(alpha: 0.7);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.43), 22, silhouettePaint);

    // Shoulder curve
    final shoulderPaint = Paint()..color = const Color(0xFF0B0F1A).withValues(alpha: 0.8);
    final path = Path()
      ..moveTo(size.width * 0.14, size.height)
      ..quadraticBezierTo(size.width * 0.14, size.height * 0.69, size.width * 0.5, size.height * 0.69)
      ..quadraticBezierTo(size.width * 0.86, size.height * 0.69, size.width * 0.86, size.height)
      ..close();
    canvas.drawPath(path, shoulderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

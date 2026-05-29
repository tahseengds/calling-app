import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lumio_icons.dart';

// ── Reusable control button ───────────────────────────────────────────────────

/// A circular icon button used in call UIs.
class CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool danger;
  final VoidCallback? onTap;
  final double size;

  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
    this.danger = false,
    this.onTap,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lumioColors = context.lumioColors;

    Color bg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    Color fg = lumioColors.fg1;
    Border border = Border.all(color: lumioColors.hairline);

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
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
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
                transform: danger
                    ? Matrix4.rotationZ(2.356)
                    : Matrix4.identity(),
                child: Icon(icon, size: size * 0.4, color: fg),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTextStyles.caption(color: lumioColors.fg2)
              .copyWith(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ── Audio call control bar ────────────────────────────────────────────────────

class AudioCallControls extends StatelessWidget {
  final bool isMuted;
  final bool isSpeakerOn;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onHangUp;

  const AudioCallControls({
    super.key,
    required this.isMuted,
    required this.isSpeakerOn,
    required this.onToggleMic,
    required this.onToggleSpeaker,
    required this.onHangUp,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        CallControlButton(
          icon: isMuted ? LumioIcons.micOff : LumioIcons.mic,
          label: isMuted ? 'Mic off' : 'Mic',
          active: isMuted,
          onTap: onToggleMic,
        ),
        CallControlButton(
          icon: LumioIcons.speaker,
          label: isSpeakerOn ? 'Speaker' : 'Earpiece',
          active: isSpeakerOn,
          onTap: onToggleSpeaker,
        ),
        CallControlButton(
          icon: LumioIcons.phone,
          label: 'End',
          danger: true,
          onTap: onHangUp,
        ),
      ],
    );
  }
}

// ── Video call control bar ────────────────────────────────────────────────────

class VideoCallControls extends StatelessWidget {
  final bool isMuted;
  final bool isCameraOff;
  final bool isSpeakerOn;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onFlipCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onHangUp;

  const VideoCallControls({
    super.key,
    required this.isMuted,
    required this.isCameraOff,
    required this.isSpeakerOn,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onFlipCamera,
    required this.onToggleSpeaker,
    required this.onHangUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xE60F1525),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _VideoCtrlBtn(
            icon: isMuted ? LumioIcons.micOff : LumioIcons.mic,
            active: isMuted,
            onTap: onToggleMic,
          ),
          _VideoCtrlBtn(
            icon: isCameraOff ? LucideIcons.videoOff : LumioIcons.video,
            active: isCameraOff,
            onTap: onToggleCamera,
          ),
          _VideoCtrlBtn(
            icon: LucideIcons.switchCamera,
            onTap: onFlipCamera,
          ),
          _VideoCtrlBtn(
            icon: LumioIcons.speaker,
            active: isSpeakerOn,
            onTap: onToggleSpeaker,
          ),
          // Hang-up red pill
          GestureDetector(
            onTap: onHangUp,
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
                  child: const Icon(LumioIcons.phone,
                      size: 22, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoCtrlBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  const _VideoCtrlBtn({required this.icon, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 24,
        backgroundColor:
            active ? Colors.white : Colors.white.withValues(alpha: 0.10),
        foregroundColor: active ? const Color(0xFF1A2235) : Colors.white,
        child: Icon(icon, size: 22),
      ),
    );
  }
}

// ── Reconnecting overlay ──────────────────────────────────────────────────────

class ReconnectingOverlay extends StatelessWidget {
  const ReconnectingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
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
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Reconnecting…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                "We'll keep your call going.",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

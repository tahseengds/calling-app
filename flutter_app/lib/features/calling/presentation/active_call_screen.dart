import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/call_utils.dart';
import '../../../shared/widgets/avatar.dart';
import '../domain/call_notifier.dart';
import '../domain/call_state.dart';
import 'widgets/call_controls.dart';
import 'widgets/call_quality_badge.dart';

/// Audio call UI — wired to the live [callSessionProvider].
class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callSessionProvider);
    final lumioColors = context.lumioColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pop when the call ends
    ref.listen<CallSession?>(callSessionProvider, (_, next) {
      if (!context.mounted) {
        return;
      }
      if (next == null ||
          next.phase == CallPhase.ended ||
          next.phase == CallPhase.failed) {
        if (context.canPop()) {
          context.pop();
        }
      }
    });

    if (session == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final notifier = ref.read(callSessionProvider.notifier);
    final duration = formatDuration(session.durationSeconds);
    final subColor = isDark ? Colors.white70 : Colors.black54;

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
                // ── Top info ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(
                      top: 64, left: 24, right: 24),
                  child: Column(
                    children: [
                      Text(
                        'AUDIO CALL · $duration',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      CallQualityBadge(quality: session.quality),
                    ],
                  ),
                ),

                // ── Pulsing avatar ────────────────────────────────────
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
                                scale:
                                    Tween<double>(begin: 0.96, end: 1.08)
                                        .animate(_breath),
                                child: FadeTransition(
                                  opacity: Tween<double>(
                                          begin: 0.18, end: 0.28)
                                      .animate(_breath),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: AppColors.primary,
                                          width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                              UserAvatar(
                                displayName: session.peerUser.name,
                                imageUrl: session.peerUser.avatarUrl,
                                radius: 92,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          session.peerUser.name,
                          style: AppTextStyles.display(
                                  color: lumioColors.fg1)
                              .copyWith(fontSize: 30),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          duration,
                          style: TextStyle(
                            fontSize: 16,
                            color: subColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Controls ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(
                      left: 24, right: 24, bottom: 56),
                  child: AudioCallControls(
                    isMuted: session.isMuted,
                    isSpeakerOn: session.isSpeakerOn,
                    onToggleMic: notifier.toggleMic,
                    onToggleSpeaker: notifier.toggleSpeaker,
                    onHangUp: notifier.endCall,
                  ),
                ),
              ],
            ),

            // ── Reconnecting overlay ──────────────────────────────────
            if (session.phase == CallPhase.reconnecting)
              const ReconnectingOverlay(),

            // ── Switch to audio prompt ────────────────────────────────
            if (session.showSwitchToAudioPrompt)
              _SwitchToAudioPrompt(
                onSwitch: notifier.switchToAudioOnly,
                onDismiss: notifier.dismissSwitchToAudioPrompt,
              ),
          ],
        ),
      ),
    );
  }
}

class _SwitchToAudioPrompt extends StatelessWidget {
  final VoidCallback onSwitch;
  final VoidCallback onDismiss;

  const _SwitchToAudioPrompt(
      {required this.onSwitch, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 120,
      left: 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF222B42),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Colors.black38, blurRadius: 24, offset: Offset(0, 8))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Poor video quality',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Switch to audio only to improve the call?',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('Not now',
                      style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onSwitch,
                  child: const Text('Switch',
                      style: TextStyle(color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

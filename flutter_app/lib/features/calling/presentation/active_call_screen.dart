import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/native_call_bridge.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/call_utils.dart';
import '../../../shared/widgets/avatar.dart';
import '../domain/call_notifier.dart';
import '../domain/call_state.dart';
import 'widgets/call_controls.dart';
import 'widgets/call_quality_badge.dart';
import 'widgets/speaking_indicator.dart';
import 'video_call_screen.dart' show WeakConnectionBanner;

/// Audio call UI — wired to the live [callSessionProvider].
class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _breath;

  // Cached in initState so dispose() never touches `ref` — reading a provider
  // through `ref` once the widget is deactivated throws (BuildContext is
  // unsafe to use after unmount).
  late final NativeCallBridge _bridge;
  late final StateController<bool> _callScreenVisible;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);
    _bridge = ref.read(nativeCallBridgeProvider);
    _callScreenVisible = ref.read(callScreenVisibleProvider.notifier);
    // Allow auto-PiP when the user backgrounds the app during a voice call.
    _bridge.setPipActive(true);
    // Tell the global "return to call" overlay we're on the call screen, so it
    // hides while this screen is visible and reappears once we leave.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _callScreenVisible.state = true;
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    _bridge.setPipActive(false);
    _callScreenVisible.state = false;
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
                              // Glow ring that reacts to the peer's voice —
                              // a live "they're speaking" cue.
                              SpeakingPulse(
                                level: session.remoteAudioLevel,
                                size: 184,
                                child: UserAvatar(
                                  displayName: session.peerUser.name,
                                  imageUrl: session.peerUser.avatarUrl,
                                  radius: 92,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            session.peerUser.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.display(
                                    color: lumioColors.fg1)
                                .copyWith(fontSize: 30),
                            textAlign: TextAlign.center,
                          ),
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

            // ── Weak connection prompt ────────────────────────────────
            if (session.showSwitchToAudioPrompt)
              WeakConnectionBanner(
                onSwitch: notifier.switchToAudioOnly,
                onKeep: notifier.dismissSwitchToAudioPrompt,
              ),
          ],
        ),
      ),
    );
  }
}


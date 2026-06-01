import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);
    _bridge = ref.read(nativeCallBridgeProvider);
    // Allow auto-PiP when the user backgrounds the app during a voice call.
    _bridge.setPipActive(true);
    // The "return to call" overlay's visibility is derived from the current
    // route in LuminApp, so this screen no longer toggles it directly.
  }

  @override
  void dispose() {
    _breath.dispose();
    _bridge.setPipActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lumioColors = context.lumioColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pop when the call ends. `listen` (not `watch`) + a `phase` selector means
    // this never rebuilds the screen and only fires on real phase changes.
    ref.listen<CallPhase?>(
      callSessionProvider.select((s) => s?.phase),
      (_, phase) {
        if (!context.mounted) {
          return;
        }
        if (phase == null ||
            phase == CallPhase.ended ||
            phase == CallPhase.failed) {
          if (context.canPop()) {
            context.pop();
          }
        }
      },
    );

    final hasSession =
        ref.watch(callSessionProvider.select((s) => s != null));
    if (!hasSession) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final notifier = ref.read(callSessionProvider.notifier);
    final subColor = isDark ? Colors.white70 : Colors.black54;

    // Structural fields only — the live duration / quality / speaking-level are
    // each watched inside their own small Consumer below, so the 500ms quality
    // tick and 1s duration tick don't rebuild the whole avatar + gradient tree.
    final peerName =
        ref.watch(callSessionProvider.select((s) => s?.peerUser.name ?? ''));
    final peerAvatar = ref
        .watch(callSessionProvider.select((s) => s?.peerUser.avatarUrl));
    final isMuted =
        ref.watch(callSessionProvider.select((s) => s?.isMuted ?? false));
    final isSpeakerOn =
        ref.watch(callSessionProvider.select((s) => s?.isSpeakerOn ?? false));
    final isReconnecting = ref.watch(callSessionProvider
        .select((s) => s?.phase == CallPhase.reconnecting));
    final showSwitchPrompt = ref.watch(callSessionProvider
        .select((s) => s?.showSwitchToAudioPrompt ?? false));

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
                      Consumer(
                        builder: (context, ref, _) {
                          final seconds = ref.watch(callSessionProvider
                              .select((s) => s?.durationSeconds ?? 0));
                          return Text(
                            'AUDIO CALL · ${formatDuration(seconds)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: subColor,
                              letterSpacing: 0.8,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Consumer(
                        builder: (context, ref, _) {
                          final quality = ref.watch(callSessionProvider
                              .select((s) => s?.quality ?? 'good'));
                          return CallQualityBadge(quality: quality);
                        },
                      ),
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
                              // a live "they're speaking" cue. Only the pulse
                              // watches remoteAudioLevel; the avatar is passed as
                              // the Consumer's `child` so it isn't rebuilt on
                              // every level sample.
                              Consumer(
                                child: UserAvatar(
                                  displayName: peerName,
                                  imageUrl: peerAvatar,
                                  radius: 92,
                                ),
                                builder: (context, ref, child) {
                                  final level = ref.watch(callSessionProvider
                                      .select(
                                          (s) => s?.remoteAudioLevel ?? 0.0));
                                  return SpeakingPulse(
                                    level: level,
                                    size: 184,
                                    child: child!,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            peerName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.display(
                                    color: lumioColors.fg1)
                                .copyWith(fontSize: 30),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Consumer(
                          builder: (context, ref, _) {
                            final seconds = ref.watch(callSessionProvider
                                .select((s) => s?.durationSeconds ?? 0));
                            return Text(
                              formatDuration(seconds),
                              style: TextStyle(
                                fontSize: 16,
                                color: subColor,
                              ),
                              textAlign: TextAlign.center,
                            );
                          },
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
                    isMuted: isMuted,
                    isSpeakerOn: isSpeakerOn,
                    onToggleMic: notifier.toggleMic,
                    onToggleSpeaker: notifier.toggleSpeaker,
                    onHangUp: notifier.endCall,
                  ),
                ),
              ],
            ),

            // ── Reconnecting overlay ──────────────────────────────────
            if (isReconnecting)
              const ReconnectingOverlay(),

            // ── Weak connection prompt ────────────────────────────────
            if (showSwitchPrompt)
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


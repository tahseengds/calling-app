import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/error_snackbar.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../domain/call_notifier.dart';
import '../domain/call_state.dart';

class OutgoingCallScreen extends ConsumerStatefulWidget {
  const OutgoingCallScreen({super.key});

  @override
  ConsumerState<OutgoingCallScreen> createState() =>
      _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends ConsumerState<OutgoingCallScreen>
    with TickerProviderStateMixin {
  late AnimationController _ring1;
  late AnimationController _ring2;
  late AnimationController _dot;

  @override
  void initState() {
    super.initState();
    _ring1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _ring2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        _ring2.repeat();
      }
    });

    _dot = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ring1.dispose();
    _ring2.dispose();
    _dot.dispose();
    super.dispose();
  }

  /// Map a structural [EndReason] to a short user-facing line. Returns null
  /// for the cases where saying anything would be noise (the user knows they
  /// hung up; nothing useful to tell them).
  String? _humanizedEndReason(EndReason? reason) => switch (reason) {
        EndReason.declined => "They declined the call.",
        EndReason.busy => "They're on another call.",
        EndReason.timeout => "No answer.",
        EndReason.failed => "Call failed. Please try again.",
        EndReason.missed => "No answer.",
        EndReason.interrupted => "Call ended — phone audio was interrupted.",
        EndReason.blocked => "Call ended — contact is blocked.",
        // forceKilled only appears after reconciliation on next launch, so
        // the user is never looking at this screen for it. Stays silent.
        EndReason.hungUp ||
        EndReason.rejected ||
        EndReason.forceKilled ||
        null =>
          null,
      };

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callSessionProvider);
    final lumioColors = context.lumioColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    // Navigate when call is answered or ended
    ref.listen<CallSession?>(callSessionProvider, (prev, next) {
      if (!context.mounted) {
        return;
      }
      if (next == null ||
          next.phase == CallPhase.ended ||
          next.phase == CallPhase.failed) {
        // Surface a backend-provided error (e.g. "You can only call your
        // contacts.") to the user before the screen pops — without this the
        // call just silently vanishes and the user has no idea why.
        final msg = next?.errorMessage ??
            _humanizedEndReason(prev?.endReason ?? next?.endReason);
        if (msg != null) {
          showErrorSnackbar(context, msg);
        }
        if (context.canPop()) {
          context.pop();
        }
        return;
      }
      if (next.phase == CallPhase.connected) {
        final route = next.callType == CallType.video
            ? '/call/video'
            : '/call/active';
        context.pushReplacement(route);
      }
    });

    if (session == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final isVideo = session.callType == CallType.video;

    return Scaffold(
      body: Stack(
        children: [
          // ── Radial gradient backdrop ─────────────────────────────────
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

          // ── Status pill ───────────────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    border:
                        Border.all(color: lumioColors.hairline),
                    borderRadius:
                        BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVideo
                            ? LumioIcons.video
                            : LumioIcons.phone,
                        size: 14,
                        color: lumioColors.fg2,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'OUTGOING ${isVideo ? 'VIDEO' : 'VOICE'} CALL',
                        style: AppTextStyles.caption(
                                color: lumioColors.fg2)
                            .copyWith(
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

          // ── Avatar + ripples ──────────────────────────────────────────
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
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1.15)
                            .animate(_ring1),
                        child: FadeTransition(
                          opacity:
                              Tween<double>(begin: 0.55, end: 0.0)
                                  .animate(_ring1),
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
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1.15)
                            .animate(_ring2),
                        child: FadeTransition(
                          opacity:
                              Tween<double>(begin: 0.55, end: 0.0)
                                  .animate(_ring2),
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
                        radius: 80,
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
                    style: AppTextStyles.display(color: lumioColors.fg1)
                        .copyWith(fontSize: 30),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      // Status label tracks what's actually happening:
                      //   "Calling…"    — local emit done, no backend ack yet
                      //   "Ringing…"    — backend confirmed the offer reached
                      //                   the callee (their phone is ringing)
                      //   "Connecting…" — callee answered, ICE handshake in
                      //                   progress (about to push to active)
                      switch (session.phase) {
                        CallPhase.outgoingRinging =>
                          session.peerRinging ? 'Ringing' : 'Calling',
                        CallPhase.connecting => 'Connecting',
                        _ => 'Calling',
                      },
                      style:
                          TextStyle(fontSize: 15, color: subColor),
                    ),
                    const SizedBox(width: 4),
                    _LoadingDots(controller: _dot, color: subColor),
                  ],
                ),
              ],
            ),
          ),

          // ── Cancel button ─────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    ref.read(callSessionProvider.notifier).endCall();
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
                        child: const Icon(LumioIcons.phone,
                            size: 30, color: Colors.white),
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
}

class _LoadingDots extends StatelessWidget {
  final AnimationController controller;
  final Color color;

  const _LoadingDots({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final val = controller.value;
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
                margin:
                    const EdgeInsets.symmetric(horizontal: 1.5),
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

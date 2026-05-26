import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../domain/call_notifier.dart';
import '../domain/call_state.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() =>
      _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with TickerProviderStateMixin {
  late AnimationController _ring1;
  late AnimationController _ring2;
  late AnimationController _bob;

  @override
  void initState() {
    super.initState();
    _ring1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _ring2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _ring2.repeat();
      }
    });

    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Vibrate pattern for ringtone
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _ring1.dispose();
    _ring2.dispose();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callSessionProvider);
    final lumioColors = context.lumioColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : Colors.black54;

    // Navigate away when the call phase changes out of incomingRinging
    ref.listen<CallSession?>(callSessionProvider, (prev, next) {
      if (!context.mounted) {
        return;
      }
      if (next == null ||
          next.phase == CallPhase.ended ||
          next.phase == CallPhase.failed) {
        if (context.canPop()) {
          context.pop();
        }
        return;
      }
      if (next.phase == CallPhase.connecting ||
          next.phase == CallPhase.connected) {
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
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 64, left: 24, right: 24),
              child: Column(
                children: [
                  Text(
                    'INCOMING ${isVideo ? 'VIDEO' : 'VOICE'} CALL',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: muted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),

            // ── Pulsing avatar ───────────────────────────────────────────
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
                          ScaleTransition(
                            scale: Tween<double>(begin: 0.75, end: 1.15)
                                .animate(_ring1),
                            child: FadeTransition(
                              opacity: Tween<double>(begin: 0.55, end: 0.0)
                                  .animate(_ring1),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.primary, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                          ScaleTransition(
                            scale: Tween<double>(begin: 0.75, end: 1.15)
                                .animate(_ring2),
                            child: FadeTransition(
                              opacity: Tween<double>(begin: 0.55, end: 0.0)
                                  .animate(_ring2),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.primary, width: 1.5),
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
                    Text(
                      session.peerUser.name,
                      style: AppTextStyles.display(color: lumioColors.fg1)
                          .copyWith(fontSize: 32),
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

            // ── Quick-reply chips ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: ["I'll call back", "On my way", "Can't talk now"]
                    .map((s) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      border: Border.all(color: lumioColors.hairline),
                      borderRadius:
                          BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      s,
                      style: AppTextStyles.secondaryMedium(
                              color: lumioColors.fg1)
                          .copyWith(fontSize: 13),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ── Decline / Accept ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(
                  left: 32, right: 32, bottom: 56),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Decline
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          ref
                              .read(callSessionProvider.notifier)
                              .declineCall();
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
                              transform: Matrix4.rotationZ(2.356),
                              child: const Icon(LumioIcons.phone,
                                  size: 32, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Decline',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: lumioColors.fg1)),
                    ],
                  ),

                  // Accept
                  Column(
                    children: [
                      SlideTransition(
                        position: Tween<Offset>(
                                begin: Offset.zero,
                                end: const Offset(0, -0.05))
                            .animate(_bob),
                        child: GestureDetector(
                          onTap: () {
                            ref
                                .read(callSessionProvider.notifier)
                                .acceptCall();
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
                                isVideo
                                    ? LumioIcons.video
                                    : LumioIcons.phone,
                                size: 32,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Accept',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: lumioColors.fg1)),
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

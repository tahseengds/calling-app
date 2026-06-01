import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/native_call_bridge.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/call_utils.dart';
import '../domain/call_notifier.dart';
import '../domain/call_state.dart';
import 'widgets/call_controls.dart';
import 'widgets/call_quality_badge.dart';

/// Full-screen video call — remote feed fills the screen, draggable local PiP.
class VideoCallScreen extends ConsumerStatefulWidget {
  const VideoCallScreen({super.key});

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> {
  bool _showControls = true;
  Offset _pipOffset = const Offset(double.infinity, 80); // top-right initially

  /// True while the OS has the app in a Picture-in-Picture window — we strip
  /// the chrome down to just the remote video then.
  bool _inPip = false;
  late final NativeCallBridge _bridge;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(nativeCallBridgeProvider);
    // Allow auto-PiP when the user backgrounds the app mid-call.
    _bridge.setPipActive(true);
    _bridge.isInPip.addListener(_onPipChanged);
    // The "return to call" overlay's visibility is derived from the current
    // route in LuminApp, so this screen no longer toggles it directly.
  }

  void _onPipChanged() {
    if (!mounted) return;
    setState(() => _inPip = _bridge.isInPip.value);
  }

  @override
  void dispose() {
    _bridge.isInPip.removeListener(_onPipChanged);
    _bridge.setPipActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pop when the call ends. Use `listen` (not `watch`) so the pop logic never
    // rebuilds this screen, and select `phase` so the callback only fires on
    // phase transitions — not on every 500ms quality / 1s duration tick.
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
      return const Scaffold(
          backgroundColor: Color(0xFF0B0F1A),
          body: SizedBox.shrink());
    }

    final notifier = ref.read(callSessionProvider.notifier);
    final webrtc = notifier.webrtcService;

    // ── Picture-in-Picture ─────────────────────────────────────────────────
    // In the small system PiP window (entered from the minimize button or by
    // backgrounding the app mid-call) show ONLY the remote feed — the person
    // being called — filling the window. No self-view, no controls, no chrome:
    // the window is exactly "the other person", whether the app is in the
    // background or returning to the foreground.
    if (_inPip) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0F1A),
        body: webrtc != null
            ? RTCVideoView(
                webrtc.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : const _VideoPlaceholder(),
      );
    }

    // ── Structural fields only ──────────────────────────────────────────────
    // The whole call screen previously did `ref.watch(callSessionProvider)`, so
    // the 500ms quality/audio sample and the 1s duration tick rebuilt the ENTIRE
    // tree — both RTCVideoView surfaces included — a few times a second (the
    // "screen keeps re-rendering" bug). These fields only change on user actions
    // and phase transitions, so watching them via `select` keeps the heavy video
    // subtrees stable. The live duration, quality dot and speaking-glow each
    // watch their own field inside a small leaf widget, so a tick rebuilds only
    // that leaf.
    final isCameraOff =
        ref.watch(callSessionProvider.select((s) => s?.isCameraOff ?? false));
    final isMuted =
        ref.watch(callSessionProvider.select((s) => s?.isMuted ?? false));
    final isSpeakerOn =
        ref.watch(callSessionProvider.select((s) => s?.isSpeakerOn ?? false));
    final peerName =
        ref.watch(callSessionProvider.select((s) => s?.peerUser.name ?? ''));
    final isReconnecting = ref.watch(callSessionProvider
        .select((s) => s?.phase == CallPhase.reconnecting));
    final showSwitchPrompt = ref.watch(callSessionProvider
        .select((s) => s?.showSwitchToAudioPrompt ?? false));

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: Stack(
        children: [
          // ── Remote video ────────────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: webrtc != null
                  ? RTCVideoView(
                      webrtc.remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : const _VideoPlaceholder(),
            ),
          ),

          // ── Draggable local PiP ─────────────────────────────────────
          if (webrtc != null && !isCameraOff && !_inPip)
            _DraggablePip(
              offset: _pipOffset,
              onOffsetChanged: (o) => setState(() => _pipOffset = o),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 100,
                  height: 140,
                  child: RTCVideoView(
                    webrtc.localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit
                        .RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),

          // ── "Camera off" chip — shown where the self-view would be, so the
          // user knows their own camera is disabled (not just frozen). ────────
          if (isCameraOff && !_inPip)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.videoOff,
                        color: Colors.white70, size: 16),
                    SizedBox(width: 6),
                    Text('Your camera is off',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // ── Top info bar (auto-hides) ────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: (_showControls && !_inPip) ? 1.0 : 0.0,
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
                    Material(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        // Enter system Picture-in-Picture; if the device can't,
                        // fall back to the in-app return-to-call overlay.
                        onTap: () async {
                          // Strip the chrome BEFORE the system snapshots the
                          // window so the PiP shows only the remote video from
                          // the very first frame (no controls/self-view flash).
                          setState(() => _inPip = true);
                          final entered = await _bridge.enterPip();
                          if (!entered && context.mounted) {
                            setState(() => _inPip = false);
                            context.pop();
                          }
                        },
                        child: Semantics(
                          button: true,
                          label: 'Minimize call',
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(LucideIcons.minimize,
                                color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Row(
                            children: [
                              _CallDurationText(),
                              SizedBox(width: 8),
                              _CallQualityDot(),
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

          // ── Bottom control bar (auto-hides) ─────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            left: 16,
            right: 16,
            bottom: (_showControls && !_inPip) ? 32 : -120,
            child: AnimatedOpacity(
              opacity: (_showControls && !_inPip) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: VideoCallControls(
                isMuted: isMuted,
                isCameraOff: isCameraOff,
                isSpeakerOn: isSpeakerOn,
                onToggleMic: notifier.toggleMic,
                onToggleCamera: notifier.toggleCamera,
                onFlipCamera: notifier.switchCamera,
                onToggleSpeaker: notifier.toggleSpeaker,
                onHangUp: notifier.endCall,
              ),
            ),
          ),

          // ── Tap hint ─────────────────────────────────────────────────
          if (!_showControls && !_inPip)
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

          // ── Reconnecting overlay ──────────────────────────────────────
          if (isReconnecting)
            const ReconnectingOverlay(),

          // ── Weak connection prompt ───────────────────────────────────
          if (showSwitchPrompt)
            WeakConnectionBanner(
              onSwitch: notifier.switchToAudioOnly,
              onKeep: notifier.dismissSwitchToAudioPrompt,
            ),
        ],
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _DraggablePip extends ConsumerStatefulWidget {
  final Widget child;
  final Offset offset;
  final void Function(Offset) onOffsetChanged;

  const _DraggablePip({
    required this.child,
    required this.offset,
    required this.onOffsetChanged,
  });

  @override
  ConsumerState<_DraggablePip> createState() => _DraggablePipState();
}

class _DraggablePipState extends ConsumerState<_DraggablePip> {
  late Offset _pos;
  static const double _w = 100;
  static const double _h = 140;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    // Default: top-right
    if (widget.offset.dx == double.infinity) {
      _pos = Offset(size.width - _w - 16, 80);
    } else {
      _pos = widget.offset;
    }
  }

  @override
  void didUpdateWidget(_DraggablePip old) {
    super.didUpdateWidget(old);
    // Adopt an externally-changed offset. (The sentinel infinity means "use the
    // default top-right", which didChangeDependencies handles — don't apply it
    // here or the PiP would jump off-screen.)
    if (widget.offset != old.offset && widget.offset.dx != double.infinity) {
      _pos = widget.offset;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _pos = Offset(
        (_pos.dx + d.delta.dx).clamp(0, size.width - _w),
        (_pos.dy + d.delta.dy).clamp(0, size.height - _h),
      );
    });
    widget.onOffsetChanged(_pos);
  }

  @override
  Widget build(BuildContext context) {
    // Watch ONLY the local mic level here. The 500ms audio-level samples then
    // rebuild just this glow border — the local video, handed to
    // TweenAnimationBuilder's `child`, is built once and reused — instead of
    // rebuilding the whole call screen (and its RTCVideoView surfaces).
    final level = ref
        .watch(callSessionProvider.select((s) => s?.localAudioLevel ?? 0.0));
    // Amplify the (typically small) mic level so ordinary speech glows clearly.
    final norm = (level * 3.0).clamp(0.0, 1.0);
    const glow = Color(0xFF34C77B);

    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanUpdate: _onPanUpdate,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: norm),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: widget.child,
          ),
          builder: (_, v, child) {
            return Container(
              width: _w,
              height: _h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Color.lerp(Colors.white24, glow, v)!,
                  width: 1 + 1.5 * v,
                ),
                boxShadow: [
                  const BoxShadow(
                      color: Colors.black38,
                      blurRadius: 24,
                      offset: Offset(0, 8)),
                  if (v > 0.02)
                    BoxShadow(
                      color: glow.withValues(alpha: 0.6 * v),
                      blurRadius: 18 * v,
                      spreadRadius: 2 * v,
                    ),
                ],
              ),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

/// Live call-duration label. Watches only `durationSeconds`, so the 1-second
/// duration tick rebuilds just this text — not the whole call screen (which
/// would needlessly rebuild the video surfaces every second).
class _CallDurationText extends ConsumerWidget {
  const _CallDurationText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref
        .watch(callSessionProvider.select((s) => s?.durationSeconds ?? 0));
    return Text(
      formatDuration(seconds),
      style: const TextStyle(fontSize: 12, color: Colors.white70),
    );
  }
}

/// Connection-quality dot for the header. Watches only `quality`, so the 500ms
/// quality sample rebuilds just this dot rather than the whole call screen.
class _CallQualityDot extends ConsumerWidget {
  const _CallQualityDot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality =
        ref.watch(callSessionProvider.select((s) => s?.quality ?? 'good'));
    return CallQualityDot(quality: quality);
  }
}

/// Placeholder while remote video hasn't connected yet.
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0F1A),
      child: Center(
        child: Icon(
          LucideIcons.videoOff,
          size: 64,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

/// Bottom-anchored blurred card shown when connection quality drops to poor.
class WeakConnectionBanner extends StatelessWidget {
  final VoidCallback onSwitch;
  final VoidCallback onKeep;

  const WeakConnectionBanner({
    super.key,
    required this.onSwitch,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 32,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: BoxDecoration(
              color: const Color(0x140F1525).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Amber wifi icon box
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0A93B)
                            .withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Icon(LucideIcons.wifi,
                            color: Color(0xFFF0A93B), size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Weak connection',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Switching off video may improve the call.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: onSwitch,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Switch to audio',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: onKeep,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.10),
                            side: BorderSide(
                                color: Colors.white
                                    .withValues(alpha: 0.18)),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Keep video',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

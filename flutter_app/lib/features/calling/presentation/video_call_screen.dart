import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callSessionProvider);

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
      return const Scaffold(
          backgroundColor: Color(0xFF0B0F1A),
          body: SizedBox.shrink());
    }

    final notifier = ref.read(callSessionProvider.notifier);
    final webrtc = notifier.webrtcService;
    final duration = formatDuration(session.durationSeconds);

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
          if (webrtc != null && !session.isCameraOff)
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

          // ── Top info bar (auto-hides) ────────────────────────────────
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
                    Material(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => context.pop(),
                        child: Semantics(
                          button: true,
                          label: 'Minimize call',
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.fullscreen_exit,
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
                            session.peerUser.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70),
                              ),
                              const SizedBox(width: 8),
                              CallQualityDot(quality: session.quality),
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
            bottom: _showControls ? 32 : -120,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: VideoCallControls(
                isMuted: session.isMuted,
                isCameraOff: session.isCameraOff,
                isSpeakerOn: session.isSpeakerOn,
                onToggleMic: notifier.toggleMic,
                onToggleCamera: notifier.toggleCamera,
                onFlipCamera: notifier.switchCamera,
                onToggleSpeaker: notifier.toggleSpeaker,
                onHangUp: notifier.endCall,
              ),
            ),
          ),

          // ── Tap hint ─────────────────────────────────────────────────
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

          // ── Reconnecting overlay ──────────────────────────────────────
          if (session.phase == CallPhase.reconnecting)
            const ReconnectingOverlay(),

          // ── Weak connection prompt ───────────────────────────────────
          if (session.showSwitchToAudioPrompt)
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

class _DraggablePip extends StatefulWidget {
  final Widget child;
  final Offset offset;
  final void Function(Offset) onOffsetChanged;

  const _DraggablePip({
    required this.child,
    required this.offset,
    required this.onOffsetChanged,
  });

  @override
  State<_DraggablePip> createState() => _DraggablePipState();
}

class _DraggablePipState extends State<_DraggablePip> {
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
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanUpdate: _onPanUpdate,
        child: Container(
          width: _w,
          height: _h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24, width: 1),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black38,
                  blurRadius: 24,
                  offset: Offset(0, 8))
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: widget.child,
          ),
        ),
      ),
    );
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
          Icons.videocam_off_rounded,
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
                        child: Icon(Icons.wifi_rounded,
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

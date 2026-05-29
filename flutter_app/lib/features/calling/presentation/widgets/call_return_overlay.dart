import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/call_utils.dart';
import '../../domain/call_notifier.dart';
import '../../domain/call_state.dart';

/// Global floating affordance that lets the user get back to an in-progress
/// call after they've navigated away from the call screen:
///   • video calls  → a small draggable thumbnail of the other person's video
///   • audio calls  → a slim "tap to return to call" bar with a live timer
///
/// It only appears when a call is connected AND the full call screen isn't on
/// top (tracked via [callScreenVisibleProvider]). Mounted once, above the app's
/// navigator, by [LuminApp]. Tapping it restores the relevant call screen.
class CallReturnOverlay extends ConsumerStatefulWidget {
  /// Restore the call screen. [isVideo] picks /call/video vs /call/active.
  final void Function(bool isVideo) onReturn;

  const CallReturnOverlay({super.key, required this.onReturn});

  @override
  ConsumerState<CallReturnOverlay> createState() => _CallReturnOverlayState();
}

class _CallReturnOverlayState extends ConsumerState<CallReturnOverlay> {
  Offset? _pos; // null until first drag — defaults to top-right.
  static const double _miniW = 108;
  static const double _miniH = 150;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callSessionProvider);
    final onCallScreen = ref.watch(callScreenVisibleProvider);

    // Show only while a call is live and the user is elsewhere in the app.
    if (session == null || !session.isActive || onCallScreen) {
      return const SizedBox.shrink();
    }

    return session.callType == CallType.video
        ? _buildVideoMini(context, session)
        : _buildAudioBar(context, session);
  }

  Widget _buildAudioBar(BuildContext context, CallSession session) {
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () => widget.onReturn(false),
          child: Container(
            padding: EdgeInsets.fromLTRB(16, topInset + 6, 16, 8),
            color: AppColors.success,
            child: Row(
              children: [
                const Icon(Icons.phone_in_talk_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Tap to return to call',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  formatDuration(session.durationSeconds),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoMini(BuildContext context, CallSession session) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final pos = _pos ??
        Offset(size.width - _miniW - 12, media.padding.top + 12);
    final webrtc = ref.read(callSessionProvider.notifier).webrtcService;

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onTap: () => widget.onReturn(true),
        onPanUpdate: (d) {
          final base = _pos ??
              Offset(size.width - _miniW - 12, media.padding.top + 12);
          setState(() {
            _pos = Offset(
              (base.dx + d.delta.dx).clamp(0.0, size.width - _miniW),
              (base.dy + d.delta.dy)
                  .clamp(media.padding.top, size.height - _miniH - 12),
            );
          });
        },
        child: Container(
          width: _miniW,
          height: _miniH,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54, blurRadius: 18, offset: Offset(0, 6)),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (webrtc != null)
                RTCVideoView(
                  webrtc.remoteRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                const ColoredBox(color: Colors.black),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: const Text(
                    'Tap to return',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

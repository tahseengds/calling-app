import 'package:flutter/material.dart';

/// A soft glow ring that grows and brightens with a voice level (0.0–1.0),
/// wrapped behind [child] (typically the peer avatar). Driven by the live
/// audio level sampled from WebRTC stats, it gives a visible "they're
/// speaking" cue on the audio-call screen. The ring eases between samples so
/// the coarse (~500ms) stats cadence still looks alive.
class SpeakingPulse extends StatelessWidget {
  /// Normalised audio level (0.0–1.0). Speech typically sits low (~0.0–0.3),
  /// so we amplify it before mapping to the ring.
  final double level;

  /// Diameter of the [child] (e.g. avatar) the ring sits behind.
  final double size;

  final Color color;
  final Widget child;

  const SpeakingPulse({
    super.key,
    required this.level,
    required this.size,
    required this.child,
    this.color = const Color(0xFF34C77B),
  });

  @override
  Widget build(BuildContext context) {
    // Amplify so ordinary speech produces an obvious response, then clamp.
    final norm = (level * 3.0).clamp(0.0, 1.0);
    final box = size * 1.18;

    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: norm),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (_, v, __) {
              final ringSize = size + (size * 0.16 * v);
              return Container(
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.05 + 0.22 * v),
                  boxShadow: v > 0.02
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35 * v),
                            blurRadius: 28 * v,
                            spreadRadius: 4 * v,
                          ),
                        ]
                      : null,
                ),
              );
            },
          ),
          child,
        ],
      ),
    );
  }
}

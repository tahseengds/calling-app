import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';

// ── SplashScreen ──────────────────────────────────────────────────────────────

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // Logo: spring pop-in
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  // Bloom: radial light expands from center
  late final AnimationController _bloomCtrl;
  late final Animation<double> _bloomProgress;

  // Text: slide up + fade
  late final AnimationController _textCtrl;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _subOpacity;

  // Glow ring: continuous breathing pulse
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;

  // Loader arc: continuous sweep
  late final AnimationController _arcCtrl;

  // Particles: slow ambient drift
  late final AnimationController _particleCtrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();

    final rng = math.Random(7);
    _particles = List.generate(8, (i) => _Particle(
          x: 0.08 + rng.nextDouble() * 0.84,
          yBase: 0.20 + rng.nextDouble() * 0.65,
          radius: 2.0 + rng.nextDouble() * 3.0,
          phaseOffset: rng.nextDouble(),
          driftSpeed: 0.25 + rng.nextDouble() * 0.35,
        ));

    // ── Logo (750 ms, elastic overshoot) ─────────────────────────
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));
    _logoScale = Tween<double>(begin: 0.25, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoCtrl,
            curve: const Interval(0.0, 0.35, curve: Curves.easeOut)));

    // ── Bloom (900 ms, ease-out) ──────────────────────────────────
    _bloomCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _bloomProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _bloomCtrl, curve: Curves.easeOut));

    // ── Text (550 ms, ease-out, delayed 580 ms) ───────────────────
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _textSlide =
        Tween<Offset>(begin: const Offset(0, 0.38), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _textCtrl, curve: Curves.easeOut));
    _subOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _textCtrl,
            curve:
                const Interval(0.35, 1.0, curve: Curves.easeOut)));

    // ── Glow pulse (2 400 ms loop) ────────────────────────────────
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.88, end: 1.12).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // ── Arc loader (1 100 ms loop) ────────────────────────────────
    _arcCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();

    // ── Particles (4 s loop) ──────────────────────────────────────
    _particleCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat();

    // Sequence
    _bloomCtrl.forward();
    _logoCtrl.forward();
    Future.delayed(const Duration(milliseconds: 580), () {
      if (mounted) _textCtrl.forward();
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _bloomCtrl.dispose();
    _textCtrl.dispose();
    _pulseCtrl.dispose();
    _arcCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.white,
      body: Stack(
        children: [
          // ── Radial bloom background ──────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bloomCtrl,
              builder: (_, _) => CustomPaint(
                painter: _BloomPainter(
                  isDark: isDark,
                  progress: _bloomProgress.value,
                  screenSize: size,
                ),
              ),
            ),
          ),

          // ── Ambient floating particles ───────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_particleCtrl, _bloomCtrl]),
              builder: (_, _) => CustomPaint(
                painter: _ParticlePainter(
                  particles: _particles,
                  t: _particleCtrl.value,
                  isDark: isDark,
                  bloomProgress: _bloomProgress.value,
                  screenSize: size,
                ),
              ),
            ),
          ),

          // ── Main centred content ─────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo area
                SizedBox(
                  width: 210,
                  height: 210,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Breathing glow halo
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, _) => Transform.scale(
                          scale: _pulseScale.value,
                          child: Container(
                            width: 178,
                            height: 178,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.primary
                                      .withValues(alpha: isDark ? 0.22 : 0.10),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Second ring — offset phase for depth
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, _) {
                          // Inverted phase
                          final inv = 1.0 - _pulseCtrl.value;
                          final s = 0.88 + inv * 0.24;
                          return Transform.scale(
                            scale: s,
                            child: Container(
                              width: 148,
                              height: 148,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.primary.withValues(
                                        alpha: isDark ? 0.10 : 0.05),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      // Logo card — spring pop-in
                      AnimatedBuilder(
                        animation: _logoCtrl,
                        builder: (_, _) => Opacity(
                          opacity: _logoOpacity.value,
                          child: Transform.scale(
                            scale: _logoScale.value,
                            child: Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.32),
                                    blurRadius: 52,
                                    offset: const Offset(0, 18),
                                    spreadRadius: -4,
                                  ),
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(
                                            alpha: isDark ? 0.55 : 0.08),
                                    blurRadius: 14,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: Image.asset(
                                  'assets/lumin-logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 34),

                // App name + tagline
                AnimatedBuilder(
                  animation: _textCtrl,
                  builder: (_, child) => FadeTransition(
                    opacity: _textOpacity,
                    child: SlideTransition(
                      position: _textSlide,
                      child: child,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Lumio',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.2,
                          color: isDark
                              ? AppColors.darkFg1
                              : AppColors.lightFg1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AnimatedBuilder(
                        animation: _textCtrl,
                        builder: (_, child) => FadeTransition(
                          opacity: _subOpacity,
                          child: child,
                        ),
                        child: Text(
                          'Calls and chat, made simple.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? AppColors.darkFg2
                                : AppColors.lightFg2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 56),

                // Sweeping arc loader
                AnimatedBuilder(
                  animation: Listenable.merge([_arcCtrl, _textCtrl]),
                  builder: (_, _) => Opacity(
                    opacity: _textOpacity.value,
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CustomPaint(
                        painter: _ArcLoaderPainter(
                            t: _arcCtrl.value, isDark: isDark),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Version footer ───────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 38,
            child: AnimatedBuilder(
              animation: _textCtrl,
              builder: (_, child) =>
                  FadeTransition(opacity: _subOpacity, child: child),
              child: Text(
                'v 1.0 · Made with care',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkFg3 : AppColors.lightFg3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class _Particle {
  final double x;           // normalized 0–1
  final double yBase;       // normalized 0–1 start
  final double radius;
  final double phaseOffset; // 0–1 — staggers per-particle timing
  final double driftSpeed;  // multiplier for drift speed

  const _Particle({
    required this.x,
    required this.yBase,
    required this.radius,
    required this.phaseOffset,
    required this.driftSpeed,
  });
}

// ── Painters ──────────────────────────────────────────────────────────────────

class _BloomPainter extends CustomPainter {
  final bool isDark;
  final double progress;
  final Size screenSize;

  const _BloomPainter({
    required this.isDark,
    required this.progress,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height * 0.42);
    final maxR = size.width * 0.85;
    final r = maxR * progress;

    if (isDark) {
      // Primary blue haze
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            AppColors.primary.withValues(alpha: 0.18 * progress),
            AppColors.primary.withValues(alpha: 0.06 * progress),
            Colors.transparent,
          ], stops: const [
            0.0,
            0.55,
            1.0
          ]).createShader(Rect.fromCircle(center: center, radius: r)),
      );
      // Second wider outer haze
      canvas.drawCircle(
        center,
        r * 1.4,
        Paint()
          ..shader = RadialGradient(colors: [
            AppColors.primary.withValues(alpha: 0.06 * progress),
            Colors.transparent,
          ]).createShader(
              Rect.fromCircle(center: center, radius: r * 1.4)),
      );
    } else {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            AppColors.primary.withValues(alpha: 0.08 * progress),
            Colors.transparent,
          ]).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BloomPainter old) =>
      old.progress != progress || old.isDark != isDark;
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final bool isDark;
  final double bloomProgress;
  final Size screenSize;

  const _ParticlePainter({
    required this.particles,
    required this.t,
    required this.isDark,
    required this.bloomProgress,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bloomProgress < 0.25) return;
    final visibility = ((bloomProgress - 0.25) / 0.75).clamp(0.0, 1.0);

    for (final p in particles) {
      final phase = (t * p.driftSpeed + p.phaseOffset) % 1.0;
      // Drift 40 px upward per full cycle, wrap smoothly via sine opacity
      final yOff = -40.0 * phase;
      final alpha =
          (math.sin(phase * math.pi) * visibility * (isDark ? 0.50 : 0.28))
              .clamp(0.0, 1.0);

      if (alpha < 0.01) continue;

      final px = p.x * size.width;
      final py = p.yBase * size.height + yOff;

      canvas.drawCircle(
        Offset(px, py),
        p.radius,
        Paint()
          ..color = AppColors.primary.withValues(alpha: alpha)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.t != t || old.bloomProgress != bloomProgress || old.isDark != isDark;
}

class _ArcLoaderPainter extends CustomPainter {
  final double t; // 0–1 looping
  final bool isDark;

  const _ArcLoaderPainter({required this.t, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;
    const strokeW = 2.5;

    // Track ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    // Sweeping arc — rotates + breathes in length
    final startAngle = t * 2 * math.pi * 1.6 - math.pi / 2;
    final sweep = math.pi * 0.3 +
        math.pi * 0.55 * math.sin(t * math.pi * 2).abs();

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcLoaderPainter old) => old.t != t;
}

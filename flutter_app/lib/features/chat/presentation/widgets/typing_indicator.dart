import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  static const _dotCount = 3;
  static const _dotSize = 7.0;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _dotCount,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(reverse: true, period: const Duration(milliseconds: 1200)),
    );
    _anims = List.generate(
      _dotCount,
      (i) {
        _controllers[i].forward(from: i / _dotCount);
        return Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _controllers[i], curve: Curves.easeInOut),
        );
      },
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          _dotCount,
          (i) => Padding(
            padding: EdgeInsets.only(right: i < _dotCount - 1 ? 4 : 0),
            child: AnimatedBuilder(
              animation: _anims[i],
              builder: (_, _) => Transform.translate(
                offset: Offset(0, -4 * math.sin(_anims[i].value * math.pi)),
                child: Container(
                  width: _dotSize,
                  height: _dotSize,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

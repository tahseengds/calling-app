import 'package:flutter/material.dart';

/// Wraps [child] in a tap-and-drag listener that unfocuses the current
/// primary focus — typically a TextField. Tapping anywhere outside an
/// input dismisses the keyboard.
///
/// Use as the body of a Scaffold on every form-bearing screen:
///
/// ```dart
/// Scaffold(
///   body: DismissKeyboard(child: SingleChildScrollView(...)),
/// );
/// ```
class DismissKeyboard extends StatelessWidget {
  final Widget child;
  const DismissKeyboard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // HitTestBehavior.opaque ensures empty regions (no painted widget under
      // the pointer) still receive the tap.
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

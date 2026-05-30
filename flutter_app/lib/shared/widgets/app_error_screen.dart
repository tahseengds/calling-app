import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Friendly fallback shown (in release builds) when a widget subtree throws
/// during build, instead of Flutter's default grey/red error box. The error
/// itself is already reported to Crashlytics by the global FlutterError.onError
/// handler in main.dart — this is purely the visual the user sees.
class AppErrorScreen extends StatelessWidget {
  const AppErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Self-contained styling: this can render outside the app's Theme scope
    // (e.g. if the failing subtree is above MaterialApp), so don't depend on it.
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF0B0F1A),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: AppColors.primary, size: 48),
                SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please go back and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9AA3B2), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

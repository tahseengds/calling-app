import 'package:flutter/material.dart';

// Margin chosen so the floating snackbar clears the bottom nav (~64dp) +
// safe-area on devices with no hardware back gesture.
const EdgeInsets _snackMargin = EdgeInsets.fromLTRB(16, 0, 16, 16);

void showErrorSnackbar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        margin: _snackMargin,
        duration: const Duration(seconds: 4),
      ),
    );
}

void showSuccessSnackbar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: _snackMargin,
        duration: const Duration(seconds: 3),
      ),
    );
}

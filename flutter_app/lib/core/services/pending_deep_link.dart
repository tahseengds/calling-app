import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stash for a deep-link path that arrived before the app could navigate
/// (typically an FCM tap during cold start, or before auth resolves).
///
/// LuminApp watches this and routes the saved path once the user is on
/// the authenticated side of the router.
///
/// Lives in core/services/ rather than main.dart so app.dart can import
/// it without main.dart having to import app.dart in turn.
class _PendingDeepLinkNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String path) => state = path;

  String? consume() {
    final v = state;
    state = null;
    return v;
  }
}

final pendingDeepLinkProvider =
    NotifierProvider<_PendingDeepLinkNotifier, String?>(
  _PendingDeepLinkNotifier.new,
);

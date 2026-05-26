import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin wrapper around the `app_links` plugin so the rest of the app can
/// stay package-agnostic.
///
/// Surfaces two channels:
///   - `getInitialLink()` returns the link the app was cold-started with
///     (e.g. user tapped the verification email while the app was killed).
///   - `uriStream` emits every link delivered while the app is running
///     (cold-started OR foreground/background hand-off).
///
/// Both swallow plugin errors so a misbehaving deep link can never crash
/// the app — failures are logged and the rest of the system carries on.
class DeepLinkService {
  final AppLinks _links = AppLinks();

  Future<Uri?> getInitialLink() async {
    try {
      return await _links.getInitialLink();
    } catch (e, st) {
      debugPrint('[DeepLinkService] getInitialLink failed: $e\n$st');
      return null;
    }
  }

  Stream<Uri> get uriStream => _links.uriLinkStream.handleError(
        (e, st) => debugPrint('[DeepLinkService] stream error: $e\n$st'),
      );
}

final deepLinkServiceProvider = Provider<DeepLinkService>(
  (_) => DeepLinkService(),
);

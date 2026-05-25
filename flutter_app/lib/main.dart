// Replace android/app/google-services.json with the file from Firebase Console
// when enabling push notifications (FCM). A placeholder is committed for builds.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/services/notification_service.dart';
import 'core/services/signaling_service.dart';
import 'core/services/sync_service.dart';

// Must be a top-level function — background isolates cannot capture closures.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint(
    '[FCM background] id=${message.messageId} type=${message.data['type']}',
  );
  // TODO: prompt 15 — wake CallService for incoming call data messages
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.uiOnly) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  final container = ProviderContainer();
  await container.read(notificationServiceProvider).init();

  if (!AppConfig.uiOnly) {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Deep-link: app opened from a terminated state via notification tap.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleFcmMessage(initial, container);
    }

    // Deep-link: app in background, notification tapped.
    FirebaseMessaging.onMessageOpenedApp.listen(
      (msg) => _handleFcmMessage(msg, container),
    );

    // Foreground FCM messages — show local notification; socket delivers data.
    FirebaseMessaging.onMessage.listen((msg) {
      final type = msg.data['type'] as String?;
      if (type == 'new_message') {
        final notif = msg.notification;
        container.read(notificationServiceProvider).showMessageNotification(
              id: msg.messageId ?? '',
              senderName: notif?.title ?? 'New message',
              preview: notif?.body ?? '',
              conversationId: msg.data['conversation_id'] as String? ?? '',
            );
      }
    });
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: LuminApp(
        onResume: () {
          if (!AppConfig.uiOnly) {
            // Ensure socket is up and sync missed messages.
            container.read(signalingServiceProvider); // warm up provider
            container
                .read(syncServiceProvider)
                .syncConversations()
                .ignore();
          }
        },
      ),
    ),
  );
}

/// Routes FCM data messages to the correct conversation.
void _handleFcmMessage(RemoteMessage msg, ProviderContainer container) {
  final conversationId = msg.data['conversation_id'] as String?;
  if (conversationId == null) return;
  // The router will handle /chat/:id navigation once the app is mounted.
  // We store the pending deep-link in a simple notifier.
  container
      .read(pendingDeepLinkProvider.notifier)
      .set('/chat/$conversationId');
}

// ── Pending deep-link ─────────────────────────────────────────────────────────
// Written by FCM handler, consumed once by LuminApp._onFirstFrame.

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
        _PendingDeepLinkNotifier.new);

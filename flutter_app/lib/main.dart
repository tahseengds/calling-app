// Replace android/app/google-services.json with the file from Firebase Console
// when enabling push notifications (FCM). A placeholder is committed for builds.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/services/native_call_bridge.dart';
import 'core/services/notification_service.dart';
import 'core/services/signaling_service.dart';
import 'core/services/sync_service.dart';
import 'features/calling/domain/call_notifier.dart';

// Must be a top-level function — background isolates cannot capture closures.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final type = message.data['type'];
  debugPrint('[FCM background] id=${message.messageId} type=$type');
  // For incoming_call data messages the native FcmService.kt has already
  // started CallService — do NOT do anything here that would double-ring.
  // Missed-call notifications are also handled natively. The Dart background
  // handler is therefore a no-op for prompt-15 types.
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
      // incoming_call & missed_call are handled by the native FcmService
      // (which is invoked in parallel by the system). We don't replicate
      // here to avoid a double-ring.
    });

    // Prompt 15 — pull any pending native call payload that landed before
    // the Dart engine was alive (CallService full-screen intent or
    // CallActionReceiver cold-launch). Seed the CallNotifier with it.
    await _consumeInitialNativeCallData(container);
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

/// Prompt 15 — at cold start, ask the native side whether MainActivity was
/// launched from a call notification (full-screen intent or accept/decline
/// action). If so, seed CallNotifier with the payload, and honor any
/// pre-accept / pre-decline the user already tapped on the lock screen.
Future<void> _consumeInitialNativeCallData(
  ProviderContainer container,
) async {
  try {
    final bridge = container.read(nativeCallBridgeProvider);
    final initial = await bridge.getInitialCallData();
    if (initial == null) return;
    final notifier = container.read(callSessionProvider.notifier);
    switch (initial.kind) {
      case NativeCallEventKind.incoming:
        await notifier.handleIncomingCallFromKilledState(initial.payload);
      case NativeCallEventKind.accept:
        await notifier.handleIncomingCallFromKilledState(initial.payload);
        await notifier.acceptCall();
      case NativeCallEventKind.decline:
        await notifier.handleIncomingCallFromKilledState(initial.payload);
        notifier.declineCall();
    }
  } catch (e) {
    debugPrint('[prompt-15 cold-start] failed: $e');
  }
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

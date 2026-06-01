// Replace android/app/google-services.json with the file from Firebase Console
// when enabling push notifications (FCM). A placeholder is committed for builds.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'shared/widgets/app_error_screen.dart';
import 'core/services/analytics_service.dart';
import 'core/services/native_call_bridge.dart';
import 'core/services/notification_service.dart';
import 'core/services/pending_deep_link.dart';
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

/// True for the benign "element is defunct" teardown race that Flutter +
/// Riverpod already catch and recover from — most commonly a provider (e.g. the
/// connectivity `StreamProvider` behind the per-screen OfflineBanner) delivering
/// a value to a `Consumer` that was just unmounted during navigation or app
/// backgrounding. The framework asserts `_lifecycleState != _ElementLifecycle.defunct`
/// inside `markNeedsBuild`; Riverpod's `runBinaryGuarded` traps it so the app
/// keeps running. It's never fatal — telling a disposed widget to rebuild is a
/// no-op — so we record it non-fatally instead of letting it tank the
/// crash-free rate. Anything else is reported as a real crash.
bool _isBenignTeardownError(Object error) {
  final s = error.toString();
  return s.contains('_ElementLifecycle.defunct');
}

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Keep the native splash visible while we do async initialization.
  // FlutterNativeSplash.remove() is called right before runApp().
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // In release builds, replace Flutter's default grey/red build-error box with
  // a calm fallback screen. Debug builds keep the detailed red box (useful for
  // developers). The error is still reported to Crashlytics via onError below.
  if (kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) => const AppErrorScreen();
  }

  late final ProviderContainer container;

  try {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // ── Crash + error reporting ───────────────────────────────────────────
      // Route every uncaught Flutter error and async (platform) error into
      // Crashlytics so any in-app issue is tracked automatically.
      FlutterError.onError = (details) {
        // Benign teardown races (see [_isBenignTeardownError]) are caught and
        // recovered from by the framework / Riverpod — telling a disposed
        // widget to rebuild is a no-op. Don't dump them or report them to
        // Crashlytics; just leave a terse breadcrumb so the console isn't
        // spammed with a non-issue (and the crash-free rate isn't dented).
        if (_isBenignTeardownError(details.exception)) {
          debugPrint('[teardown] ignored defunct-element rebuild (benign)');
          return;
        }
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        if (_isBenignTeardownError(error)) {
          debugPrint('[teardown] ignored defunct-element error (benign)');
          return true;
        }
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      // Collection follows the platform default (on in release builds).
    } catch (e) {
      debugPrint('[startup] Firebase.initializeApp failed: $e');
      // Continue without Firebase — the app can still show the UI.
    }

    container = ProviderContainer();
    container.read(analyticsServiceProvider).logEvent('app_open');
    final notifications = container.read(notificationServiceProvider);
    // Route taps on the local notifications we show ourselves (foreground FCM
    // messages) into the same pendingDeepLink path the cold-start FCM handler
    // uses, so the app navigates to the right chat once auth is ready.
    notifications.onMessageNotificationTap = (conversationId) {
      if (conversationId.isEmpty) return;
      container
          .read(pendingDeepLinkProvider.notifier)
          .set('/chat/$conversationId');
    };
    await notifications.init();

    {
      // Request notification permission — no-op on Android < 13.
      try {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}

      // Deep-link: app opened from a terminated state via notification tap.
      // Use a timeout so a slow/disconnected FCM doesn't block startup.
      try {
        final initial = await FirebaseMessaging.instance
            .getInitialMessage()
            .timeout(const Duration(seconds: 5));
        if (initial != null) {
          _handleFcmMessage(initial, container);
        }
      } catch (_) {}

      // Deep-link: app in background, notification tapped.
      FirebaseMessaging.onMessageOpenedApp.listen(
        (msg) => _handleFcmMessage(msg, container),
      );

      // Foreground FCM messages — show local notification; socket delivers data.
      FirebaseMessaging.onMessage.listen((msg) {
        final type = msg.data['type'] as String?;
        if (type == 'new_message') {
          final convId = msg.data['conversation_id'] as String? ?? '';
          // Don't post a notification for the chat the user is currently
          // viewing — it's already on screen and gets marked read.
          if (convId.isNotEmpty &&
              convId == container.read(activeConversationProvider)) {
            return;
          }
          // Our pushes are data-only (no `notification` block) so the native
          // FcmService can render them in the background. That means
          // `msg.notification` is null here — read the real sender/preview from
          // the data payload (the worker puts them there), falling back to the
          // notification block only if a server ever sends one.
          final notif = msg.notification;
          final senderName =
              msg.data['sender_name'] as String? ?? notif?.title ?? 'New message';
          final preview =
              msg.data['preview'] as String? ?? notif?.body ?? '';
          container.read(notificationServiceProvider).showMessageNotification(
                id: msg.messageId ?? '',
                senderName: senderName,
                preview: preview,
                conversationId: convId,
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

      // Message-notification tap routing. The native FcmService owns FCM
      // message notifications, so firebase_messaging's onMessageOpenedApp never
      // fires for them — MainActivity forwards the conversation_id instead.
      final bridge = container.read(nativeCallBridgeProvider);
      bridge.onOpenConversation = (convId) {
        container
            .read(pendingDeepLinkProvider.notifier)
            .set('/chat/$convId');
      };
      // Generic notification routes (e.g. missed-call → /call/history).
      bridge.onOpenRoute = (route) {
        container.read(pendingDeepLinkProvider.notifier).set(route);
      };
      final initialConv = await bridge.getInitialConversation();
      if (initialConv != null && initialConv.isNotEmpty) {
        container
            .read(pendingDeepLinkProvider.notifier)
            .set('/chat/$initialConv');
      }
      final initialRoute = await bridge.getInitialRoute();
      if (initialRoute != null && initialRoute.isNotEmpty) {
        container.read(pendingDeepLinkProvider.notifier).set(initialRoute);
      }
    }
  } catch (e, st) {
    debugPrint('[startup] Unexpected initialization error: $e\n$st');
    // Fall through — always call runApp so the native splash is dismissed.
  }

  FlutterNativeSplash.remove();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: LuminApp(
        onResume: () {
          // Ensure socket is up and sync missed messages.
          container.read(signalingServiceProvider); // warm up provider
          container.read(syncServiceProvider).syncConversations().ignore();
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
      case NativeCallEventKind.hangup:
        // FIX 7 cold-start: the user tapped Hang Up on the persistent
        // in-call notification while the engine was dead. The peer/Node
        // already saw the call end (or will via its own hangup signal),
        // so nothing for us to send — just don't try to resurrect the
        // call session on app open.
        break;
      case NativeCallEventKind.cancelled:
        // The caller cancelled before the app finished cold-starting. There's
        // nothing to resurrect — leave the call session null so no stale
        // incoming-call screen is shown on launch.
        break;
    }
  } catch (e) {
    debugPrint('[prompt-15 cold-start] failed: $e');
  }
}

// pendingDeepLinkProvider lives in core/services/pending_deep_link.dart
// so that app.dart can import it without cycling back through main.dart.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Channel IDs referenced by the native manifest and prompt 15 call service.
const kChannelMessages = 'messages';
const kChannelCalls = 'calls';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Set by main.dart so a notification tap can route into the app even when
  /// the local notification (not FCM directly) was the entry point — e.g.
  /// foreground messages we show ourselves via [showMessageNotification].
  void Function(String conversationId)? onMessageNotificationTap;

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _handleTap,
    );
    await _createChannels();
  }

  void _handleTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    onMessageNotificationTap?.call(payload);
  }

  Future<void> _createChannels() async {
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        kChannelMessages,
        'Messages',
        description: 'New message notifications',
        importance: Importance.defaultImportance,
        playSound: true,
      ),
    );

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        kChannelCalls,
        'Calls',
        description: 'Incoming call notifications',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        // Full-screen-intent capable — wired in prompt 15.
      ),
    );
  }

  /// Shows a heads-up notification for a new message received while the app is
  /// backgrounded. [payload] is the conversationId for deep-link routing.
  Future<void> showMessageNotification({
    required String id,
    required String senderName,
    required String preview,
    required String conversationId,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      kChannelMessages,
      'Messages',
      channelDescription: 'New message notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(''),
    );
    await _plugin.show(
      id: id.hashCode,
      title: senderName,
      body: preview,
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: conversationId,
    );
  }

  // Incoming-call full-screen notifications are owned by the native
  // FcmService + CallService on Android (see android/.../FcmService.kt).
  // The Dart side never paints that surface — it would race the native
  // ringer and produce a double-ring.
}

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService(),
);

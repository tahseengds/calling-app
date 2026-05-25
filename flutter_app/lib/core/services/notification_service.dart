import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Channel IDs referenced by the native manifest and prompt 15 call service.
const kChannelMessages = 'messages';
const kChannelCalls = 'calls';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(settings: const InitializationSettings(android: android));
    await _createChannels();
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

  // TODO: prompt 13 — show message notification
  // TODO: prompt 15 — show full-screen incoming call notification
}

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService(),
);

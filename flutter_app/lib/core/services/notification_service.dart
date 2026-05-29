import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

// Channel IDs referenced by the native manifest and prompt 15 call service.
const kChannelMessages = 'messages';
const kChannelCalls = 'calls';

// Status-bar small icon (white silhouette). Shared by the Dart-shown
// (foreground) notifications and the native FcmService (background).
const _kNotifIcon = '@drawable/ic_stat_notification';
const _kMessagesGroup = 'lumin_messages';
// Group-summary notification id. Negative so it never collides with a
// per-conversation id (conversationNotificationId only returns 1..0x3FFFFFF).
const _kMessagesSummaryId = -1000;

/// The conversation the user is currently viewing (null when none). New
/// messages for this conversation are NOT turned into notifications — the open
/// chat already shows them and marks them read. Set by the chat screen.
final activeConversationProvider = StateProvider<String?>((_) => null);

/// Stable notification id for a conversation. Deliberately a hand-rolled 31x
/// polynomial hash (masked to 26 bits so the *31 never overflows a 32-bit Kotlin
/// Int) so it produces the SAME value as `convNotifId` in FcmService.kt — that
/// lets Dart cancel notifications the native background handler posted.
int conversationNotificationId(String conversationId) {
  var h = 0;
  for (final c in conversationId.codeUnits) {
    h = (h * 31 + c) & 0x3FFFFFF;
  }
  return h == 0 ? 1 : h;
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Set by main.dart so a notification tap can route into the app even when
  /// the local notification (not FCM directly) was the entry point — e.g.
  /// foreground messages we show ourselves via [showMessageNotification].
  void Function(String conversationId)? onMessageNotificationTap;

  Future<void> init() async {
    const android = AndroidInitializationSettings(_kNotifIcon);
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

  /// Shows a heads-up notification for a new message. Keyed by [conversationId]
  /// so successive messages from the same chat COLLAPSE into one updating
  /// notification (instead of stacking separately), and so [cancelConversation]
  /// can clear it when the chat is opened/read. [payload] is the conversationId
  /// for deep-link routing.
  Future<void> showMessageNotification({
    required String id, // unused for the notification id now; kept for callers
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
      icon: _kNotifIcon,
      groupKey: _kMessagesGroup,
      styleInformation: BigTextStyleInformation(''),
    );
    await _plugin.show(
      id: conversationNotificationId(conversationId),
      title: senderName,
      body: preview,
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: conversationId,
    );
    await _showMessagesSummary();
  }

  /// Posts (or refreshes) the group-summary notification so multiple chats'
  /// notifications bundle under one "New messages" header instead of stacking
  /// loose. Re-posting with the same id just updates it.
  Future<void> _showMessagesSummary() async {
    const summaryDetails = AndroidNotificationDetails(
      kChannelMessages,
      'Messages',
      channelDescription: 'New message notifications',
      icon: _kNotifIcon,
      groupKey: _kMessagesGroup,
      setAsGroupSummary: true,
    );
    await _plugin.show(
      id: _kMessagesSummaryId,
      title: 'New messages',
      body: '',
      notificationDetails: const NotificationDetails(android: summaryDetails),
    );
  }

  /// Clear the tray notification for [conversationId] — call when the chat is
  /// opened or its messages are marked read. Also clears the launcher badge on
  /// most launchers (they derive the badge from active notifications). Matches
  /// the id used by both the Dart and native (FcmService) message paths.
  Future<void> cancelConversation(String conversationId) async {
    if (conversationId.isEmpty) return;
    await _plugin.cancel(id: conversationNotificationId(conversationId));
    // Android doesn't reliably auto-remove a group SUMMARY when its last child
    // is cancelled — and a lingering summary keeps the launcher badge. So if no
    // message notifications remain, clear the summary too.
    try {
      final active = await _plugin.getActiveNotifications();
      final messagesLeft = active.any((n) =>
          n.id != _kMessagesSummaryId &&
          (n.channelId == null || n.channelId == kChannelMessages));
      if (!messagesLeft) {
        await _plugin.cancel(id: _kMessagesSummaryId);
      }
    } catch (_) {
      // getActiveNotifications unsupported on this platform/version — the
      // child cancel above is still the important part.
    }
  }

  /// Clear every message notification (e.g. on logout).
  Future<void> cancelAll() => _plugin.cancelAll();

  // Incoming-call full-screen notifications are owned by the native
  // FcmService + CallService on Android (see android/.../FcmService.kt).
  // The Dart side never paints that surface — it would race the native
  // ringer and produce a double-ring.
}

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService(),
);

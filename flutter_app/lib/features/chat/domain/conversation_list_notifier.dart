import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/services/signaling_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/storage/local_db.dart';
import '../../../shared/models/conversation.dart';
import '../../../shared/models/message.dart';
import '../../../shared/models/user.dart';

class ConversationListNotifier
    extends Notifier<AsyncValue<List<Conversation>>> {
  StreamSubscription<List<ConversationRow>>? _dbSub;
  StreamSubscription<MessageNewEvent>? _msgSub;
  StreamSubscription<PresenceEvent>? _presenceSub;

  @override
  AsyncValue<List<Conversation>> build() {
    if (AppConfig.uiOnly) {
      return AsyncData(_mockConversations());
    }
    _startWatching();
    ref.onDispose(() {
      _dbSub?.cancel();
      _msgSub?.cancel();
      _presenceSub?.cancel();
    });
    return const AsyncLoading();
  }

  void _startWatching() {
    final db = ref.read(appDatabaseProvider);

    _dbSub = db.conversationsDao.watchAll().listen((rows) async {
      final convos = await _rowsToConversations(rows);
      state = AsyncData(convos);
    });

    // New incoming message — bump conversation to top.
    final signaling = ref.read(signalingServiceProvider);
    _msgSub = signaling.onMessageNew.listen((_) {
      ref.read(syncServiceProvider).syncConversations();
    });

    // Presence updates — refresh user in conversation.
    _presenceSub = signaling.onPresence.listen((event) {
      final current = state.value;
      if (current == null) return;
      state = AsyncData(current.map((c) {
        if (c.otherUser.id != event.userId) return c;
        return c.copyWith(
          otherUser: c.otherUser.copyWith(
            presence: event.status == 'online'
                ? PresenceStatus.online
                : PresenceStatus.offline,
          ),
        );
      }).toList());
    });

    // Initial sync from server.
    ref.read(syncServiceProvider).syncConversations();
  }

  Future<void> refresh() async {
    if (AppConfig.uiOnly) return;
    await ref.read(syncServiceProvider).syncConversations();
  }

  Future<List<Conversation>> _rowsToConversations(
      List<ConversationRow> rows) async {
    final db = ref.read(appDatabaseProvider);
    final result = <Conversation>[];

    for (final row in rows) {
      final userRow = await db.usersDao.getById(row.otherUserId);
      if (userRow == null) continue;

      String? preview;
      MessageType? lastType;
      if (row.lastMessageId != null) {
        final msgRows = await (db.select(db.messagesTable)
              ..where((m) => m.id.equals(row.lastMessageId!)))
            .get();
        if (msgRows.isNotEmpty) {
          final msg = msgRows.first;
          lastType = MessageType.values.firstWhere(
            (e) => e.name == msg.messageType,
            orElse: () => MessageType.text,
          );
          // call_log messages store their meta as JSON in `content`. Showing
          // the raw JSON in the chats list is obviously wrong — render a
          // human-readable summary instead. Other types fall back to
          // content-or-media-label as before.
          //
          // The call_log message's sender_id is always the CALLER (see
          // backend/signaling/src/callLogMessage.js). For the conversation
          // list, "incoming" means the other user called me (sender ==
          // otherUserId), "outgoing" means I called them.
          if (lastType == MessageType.callLog) {
            final isIncoming = msg.senderId == row.otherUserId;
            preview = _callLogPreview(msg.content, isIncoming: isIncoming);
          } else {
            preview = msg.content ?? _mediaPreview(lastType);
          }
        }
      }

      result.add(Conversation(
        id: row.id,
        otherUser: User(
          id: userRow.id,
          name: userRow.name,
          avatarUrl: userRow.avatarUrl,
          lastSeen: userRow.lastSeen,
          presence: PresenceStatus.values.firstWhere(
            (e) => e.name == userRow.presence,
            orElse: () => PresenceStatus.offline,
          ),
        ),
        lastMessagePreview: preview,
        lastMessageType: lastType,
        lastActivity: row.lastActivity,
        unreadCount: row.unreadCount,
      ));
    }
    return result;
  }

  // No emoji prefix — the conversation row already renders a type-specific
  // icon next to this string, and emoji + icon + word read as three duplicate
  // labels for the same attachment.
  String _mediaPreview(MessageType type) => switch (type) {
        MessageType.image => 'Photo',
        MessageType.video => 'Video',
        MessageType.audio => 'Voice note',
        MessageType.file => 'File',
        MessageType.callLog => 'Call',
        MessageType.text => '',
      };

  /// Build the chats-home preview text for a [MessageType.callLog] message.
  /// Content is the JSON blob written by backend/signaling/src/callLogMessage.js
  /// (see CallLogMeta in shared/models/message.dart).
  ///
  /// [isIncoming] distinguishes "cancelled by me" from "missed by me" — the
  /// backend's `outcome: 'missed'` covers both cases (caller-cancelled and
  /// callee-no-answer). From the caller's chat list a cancellation should
  /// read "Cancelled call"; from the callee's it should read "Missed call".
  ///
  ///   answered  → "Voice call · 2m 14s"   / "Video call · 2m 14s"
  ///   missed (incoming)  → "Missed voice call"
  ///   missed (outgoing)  → "Cancelled call"
  ///   declined  → "Declined voice call"
  ///   busy/failed → "Call failed"
  ///   anything else → "Call"
  String _callLogPreview(String? content, {required bool isIncoming}) {
    if (content == null || content.isEmpty) return 'Call';
    try {
      final json = jsonDecode(content);
      if (json is! Map<String, dynamic>) return 'Call';
      final outcome = json['outcome'] as String? ?? '';
      final callType = json['call_type'] as String? ?? 'audio';
      final duration = (json['duration_seconds'] as num?)?.toInt() ?? 0;
      final kind = callType == 'video' ? 'video' : 'voice';
      switch (outcome) {
        case 'answered':
          final cap = kind == 'video' ? 'Video' : 'Voice';
          if (duration <= 0) return '$cap call';
          return '$cap call · ${_formatCallLogDuration(duration)}';
        case 'missed':
          return isIncoming ? 'Missed $kind call' : 'Cancelled call';
        case 'declined':
          return isIncoming ? 'Declined $kind call' : 'Call declined';
        case 'busy':
        case 'failed':
          return 'Call failed';
        default:
          return 'Call';
      }
    } catch (_) {
      // Malformed JSON — fall back to a generic label rather than dumping
      // the raw blob into the preview.
      return 'Call';
    }
  }

  static String _formatCallLogDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    if (s == 0) return '${m}m';
    return '${m}m ${s}s';
  }

  List<Conversation> _mockConversations() {
    final now = DateTime.now();
    return [
      Conversation(
        id: 'rose',
        otherUser: User(
          id: 'rose',
          name: 'Grandma Rose',
          email: 'rose@example.com',
          lastSeen: now.subtract(const Duration(minutes: 2)),
          presence: PresenceStatus.online,
        ),
        lastMessagePreview: "Perfect. The kettle's already on.",
        lastMessageType: MessageType.text,
        lastActivity: now.subtract(const Duration(minutes: 18)),
        unreadCount: 0,
      ),
      Conversation(
        id: 'mike',
        otherUser: User(
          id: 'mike',
          name: 'Dad Mike',
          email: 'mike@example.com',
          lastSeen: now.subtract(const Duration(hours: 1)),
          presence: PresenceStatus.offline,
        ),
        lastMessagePreview: 'Will do, see you then',
        lastMessageType: MessageType.text,
        lastActivity: now.subtract(const Duration(hours: 1)),
        unreadCount: 2,
      ),
      Conversation(
        id: 'fam',
        otherUser: MockData.currentUser,
        lastMessagePreview: 'Photo',
        lastMessageType: MessageType.image,
        lastActivity: now.subtract(const Duration(days: 1)),
        unreadCount: 0,
      ),
    ];
  }
}

final conversationListProvider =
    NotifierProvider.autoDispose<ConversationListNotifier,
        AsyncValue<List<Conversation>>>(ConversationListNotifier.new);

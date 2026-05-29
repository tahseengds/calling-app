import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final signaling = ref.read(signalingServiceProvider);

    _dbSub = db.conversationsDao.watchAll().listen((rows) async {
      final convos = await _rowsToConversations(rows);
      state = AsyncData(convos);
      // Ask the signaling server for the current presence of everyone in the
      // list. Live changes arrive afterwards via the presence:update stream;
      // this seeds the initial online/last-seen state which REST never carries.
      final ids = convos.map((c) => c.otherUser.id).toList();
      if (ids.isNotEmpty) signaling.requestPresence(ids);
    });

    // New incoming message — bump conversation to top.
    _msgSub = signaling.onMessageNew.listen((_) {
      ref.read(syncServiceProvider).syncConversations();
    });

    // Presence updates — refresh both online status and last-seen for the
    // matching user. Covers the initial presence:data batch (seeded by
    // requestPresence) and subsequent live presence:update broadcasts.
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
            lastSeen: event.lastSeen,
          ),
        );
      }).toList());
    });

    // Initial sync from server.
    ref.read(syncServiceProvider).syncConversations();
  }

  Future<void> refresh() async {
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
  /// Content is the JSON blob written by the signaling layer.
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
}

final conversationListProvider =
    NotifierProvider.autoDispose<ConversationListNotifier,
        AsyncValue<List<Conversation>>>(ConversationListNotifier.new);

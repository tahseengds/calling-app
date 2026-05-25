import 'dart:async';
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
          preview = msg.content ?? _mediaPreview(lastType);
        }
      }

      result.add(Conversation(
        id: row.id,
        otherUser: User(
          id: userRow.id,
          name: userRow.name,
          phone: userRow.phone,
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

  String _mediaPreview(MessageType type) => switch (type) {
        MessageType.image => '📷 Photo',
        MessageType.video => '🎥 Video',
        MessageType.audio => '🎵 Voice note',
        MessageType.file => '📎 File',
        MessageType.text => '',
      };

  List<Conversation> _mockConversations() {
    final now = DateTime.now();
    return [
      Conversation(
        id: 'rose',
        otherUser: User(
          id: 'rose',
          name: 'Grandma Rose',
          phone: '+15551234567',
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
          phone: '+15559876543',
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
        lastMessagePreview: '📷 Photo',
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

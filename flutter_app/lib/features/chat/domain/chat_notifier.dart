import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/signaling_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/storage/local_db.dart';
import '../../../features/auth/domain/auth_notifier.dart';
import '../../../features/auth/domain/auth_state.dart';
import '../../../shared/models/message.dart';
import '../../../shared/models/user.dart';
import '../data/message_local_dao.dart';
import '../data/message_repository.dart';

const _uuid = Uuid();

// ── Chat state ────────────────────────────────────────────────────────────────

class ChatState {
  final List<Message> messages;
  final User? otherUser;
  final bool isLoadingOlder;
  final bool otherUserTyping;
  final bool hasOlderMessages;
  final String? oldestCursor;

  const ChatState({
    this.messages = const [],
    this.otherUser,
    this.isLoadingOlder = false,
    this.otherUserTyping = false,
    this.hasOlderMessages = true,
    this.oldestCursor,
  });

  ChatState copyWith({
    List<Message>? messages,
    User? otherUser,
    bool? isLoadingOlder,
    bool? otherUserTyping,
    bool? hasOlderMessages,
    String? oldestCursor,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        otherUser: otherUser ?? this.otherUser,
        isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
        otherUserTyping: otherUserTyping ?? this.otherUserTyping,
        hasOlderMessages: hasOlderMessages ?? this.hasOlderMessages,
        oldestCursor: oldestCursor ?? this.oldestCursor,
      );
}

// ── ChatNotifier ──────────────────────────────────────────────────────────────

class ChatNotifier extends FamilyNotifier<ChatState, String> {
  String get _conversationId => arg;

  StreamSubscription<List<Message>>? _dbSub;
  StreamSubscription<MessageNewEvent>? _msgNewSub;
  StreamSubscription<MessageAckEvent>? _msgAckSub;
  StreamSubscription<MessageDeletedEvent>? _msgDelSub;
  StreamSubscription<TypingEvent>? _typingSub;
  Timer? _typingStopTimer;
  bool _isTyping = false;

  @override
  ChatState build(String conversationId) {
    ref.onDispose(() {
      _dbSub?.cancel();
      _msgNewSub?.cancel();
      _msgAckSub?.cancel();
      _msgDelSub?.cancel();
      _typingSub?.cancel();
      _typingStopTimer?.cancel();
    });

    if (AppConfig.uiOnly) {
      // UI-only: use mock data from the existing chat_thread_notifier pattern.
      return const ChatState();
    }

    _init();
    return const ChatState();
  }

  Future<void> _init() async {
    final dao = ref.read(messageLocalDaoProvider);
    final db = ref.read(appDatabaseProvider);

    // Load cached messages immediately.
    final cached = await dao.getMessages(_conversationId);
    state = state.copyWith(messages: cached);

    // Load other-user profile.
    final convRows = await (db.select(db.conversationsTable)
          ..where((c) => c.id.equals(_conversationId)))
        .get();
    if (convRows.isNotEmpty) {
      final userRow = await db.usersDao.getById(convRows.first.otherUserId);
      if (userRow != null) {
        state = state.copyWith(
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
        );
      }
    }

    // Watch Drift for any changes (including optimistic writes).
    _dbSub = dao.watchMessages(_conversationId).listen((msgs) {
      state = state.copyWith(messages: msgs);
    });

    // Mark unread as read.
    final unread = cached
        .where((m) => m.status != MessageStatus.read &&
            m.senderId != _currentUserId)
        .map((m) => m.id)
        .toList();
    if (unread.isNotEmpty) {
      ref.read(messageRepositoryProvider).markRead(unread).ignore();
      dao.clearUnread(_conversationId);
    }

    // Fetch missed messages from server.
    await ref.read(syncServiceProvider).fetchMissedMessages(_conversationId);

    // Real-time events.
    _subscribeToSignaling();

    // Wire up reconnect → sync.
    ref.read(signalingServiceProvider).onReconnect = () {
      ref.read(syncServiceProvider).syncAll(_conversationId);
    };
  }

  String get _currentUserId {
    final auth = ref.read(authNotifierProvider);
    if (auth is AuthAuthenticated) return auth.me.id;
    return '';
  }

  void _subscribeToSignaling() {
    final signaling = ref.read(signalingServiceProvider);

    _msgNewSub = signaling.onMessageNew.listen((event) {
      final msg = Message.fromJson(event.json);
      if (msg.conversationId != _conversationId) return;
      // Dedup on id — upsert into Drift, which fires the watch.
      ref.read(messageLocalDaoProvider).upsertMessage(msg);
      // Send read receipt.
      if (msg.senderId != _currentUserId) {
        ref.read(messageRepositoryProvider).markRead([msg.id]).ignore();
      }
    });

    _msgAckSub = signaling.onMessageAck.listen((event) {
      final status = MessageStatus.values.firstWhere(
        (e) => e.name == event.status,
        orElse: () => MessageStatus.delivered,
      );
      ref.read(messageLocalDaoProvider).updateStatus(event.messageId, status);
    });

    _msgDelSub = signaling.onMessageDeleted.listen((event) {
      if (event.conversationId != _conversationId) return;
      ref.read(messageLocalDaoProvider).markDeleted(event.messageId);
    });

    _typingSub = signaling.onTyping.listen((event) {
      if (event.conversationId != _conversationId) return;
      state = state.copyWith(otherUserTyping: event.isTyping);
    });
  }

  // ── Send text ─────────────────────────────────────────────────────────────

  Future<void> sendText(String content, {String? replyToId}) async {
    if (content.trim().isEmpty) return;
    _stopTyping();

    final clientId = _uuid.v4();
    final now = DateTime.now();
    final optimistic = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      type: MessageType.text,
      content: content.trim(),
      status: MessageStatus.sending,
      createdAt: now,
      replyToId: replyToId,
    );

    // Write to Drift immediately → optimistic UI.
    await ref.read(messageLocalDaoProvider).upsertMessage(optimistic);

    try {
      final result = await ref.read(messageRepositoryProvider).sendMessage(
            clientId: clientId,
            conversationId: _conversationId,
            type: MessageType.text,
            content: content.trim(),
            replyToId: replyToId,
          );
      // Server response may differ in status/timestamps.
      await ref.read(messageLocalDaoProvider).upsertMessage(result);
      await ref.read(messageLocalDaoProvider).markSynced(clientId);
    } catch (_) {
      // Mark as failed — user can retry via long-press.
      await ref.read(messageLocalDaoProvider).updateStatus(
            clientId,
            MessageStatus.failed,
          );
    }
  }

  // ── Send media ────────────────────────────────────────────────────────────

  Future<void> sendMedia(
    File file,
    MessageType type, {
    String? replyToId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final clientId = _uuid.v4();
    final now = DateTime.now();

    // Track in PendingMediaUploads so it survives app restart.
    final db = ref.read(appDatabaseProvider);
    final stat = await file.stat();
    await db.pendingMediaUploadsDao.upsert(PendingMediaUploadsTableCompanion(
      localId: Value(clientId),
      filePath: Value(file.path),
      type: Value(type.name),
      conversationId: Value(_conversationId),
      totalBytes: Value(stat.size),
    ));

    final optimistic = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      type: type,
      media: MediaAttachment(url: file.path), // local path for optimistic UI
      status: MessageStatus.sending,
      createdAt: now,
      replyToId: replyToId,
    );
    await ref.read(messageLocalDaoProvider).upsertMessage(optimistic);

    try {
      final upload = await ref.read(messageRepositoryProvider).uploadMedia(
            file: file,
            type: type.name,
            onProgress: (sent, total) {
              onProgress?.call(sent, total);
              db.pendingMediaUploadsDao.upsert(
                PendingMediaUploadsTableCompanion(
                  localId: Value(clientId),
                  uploadedBytes: Value(sent),
                  status: const Value('uploading'),
                ),
              );
            },
          );

      final result = await ref.read(messageRepositoryProvider).sendMessage(
            clientId: clientId,
            conversationId: _conversationId,
            type: type,
            mediaId: upload.mediaId,
            replyToId: replyToId,
          );
      await ref.read(messageLocalDaoProvider).upsertMessage(result);
      await ref.read(messageLocalDaoProvider).markSynced(clientId);
      await db.pendingMediaUploadsDao.markDone(clientId);
    } catch (_) {
      await ref.read(messageLocalDaoProvider).updateStatus(
            clientId,
            MessageStatus.failed,
          );
    }
  }

  // ── Retry ─────────────────────────────────────────────────────────────────

  Future<void> retryMessage(String messageId) async {
    final msgs = state.messages;
    final msg = msgs.where((m) => m.id == messageId).firstOrNull;
    if (msg == null) return;

    await ref.read(messageLocalDaoProvider).updateStatus(
          messageId,
          MessageStatus.sending,
        );

    try {
      final result = await ref.read(messageRepositoryProvider).sendMessage(
            clientId: messageId,
            conversationId: _conversationId,
            type: msg.type,
            content: msg.content,
            replyToId: msg.replyToId,
          );
      await ref.read(messageLocalDaoProvider).upsertMessage(result);
      await ref.read(messageLocalDaoProvider).markSynced(messageId);
    } catch (_) {
      await ref.read(messageLocalDaoProvider).updateStatus(
            messageId,
            MessageStatus.failed,
          );
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    await ref.read(messageLocalDaoProvider).markDeleted(messageId);
    ref.read(messageRepositoryProvider).deleteMessage(messageId).ignore();
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  Future<void> loadOlderMessages() async {
    if (state.isLoadingOlder || !state.hasOlderMessages) return;
    state = state.copyWith(isLoadingOlder: true);

    try {
      final older = await ref.read(messageRepositoryProvider).fetchMessages(
            _conversationId,
            cursor: state.oldestCursor,
          );
      if (older.isEmpty) {
        state = state.copyWith(isLoadingOlder: false, hasOlderMessages: false);
        return;
      }
      for (final msg in older) {
        await ref.read(messageLocalDaoProvider).upsertMessage(msg);
      }
      state = state.copyWith(
        isLoadingOlder: false,
        oldestCursor: older.first.id,
      );
    } catch (_) {
      state = state.copyWith(isLoadingOlder: false);
    }
  }

  // ── Typing ────────────────────────────────────────────────────────────────

  void onUserTyping() {
    if (!_isTyping) {
      _isTyping = true;
      ref.read(signalingServiceProvider).emitTyping(
            isTyping: true,
            conversationId: _conversationId,
          );
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    if (!_isTyping) return;
    _isTyping = false;
    _typingStopTimer?.cancel();
    ref.read(signalingServiceProvider).emitTyping(
          isTyping: false,
          conversationId: _conversationId,
        );
  }
}

final chatProvider =
    NotifierProviderFamily<ChatNotifier, ChatState, String>(ChatNotifier.new);

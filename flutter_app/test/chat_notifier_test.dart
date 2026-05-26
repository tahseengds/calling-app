// Tests for ChatNotifier:
//   1. optimistic send writes a "sending" row before the network resolves
//   2. network failure marks the row "failed"
//   3. duplicate message:new events are deduped by primary key
//   4. message:ack events update the stored status (receipt ticks)
//
// All Drift I/O uses an in-memory NativeDatabase — nothing is written to disk.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/config/app_config.dart';
import 'package:flutter_app/core/services/signaling_service.dart';
import 'package:flutter_app/core/services/sync_service.dart';
import 'package:flutter_app/core/storage/local_db.dart';
import 'package:flutter_app/core/storage/secure_storage.dart';
import 'package:flutter_app/features/auth/data/auth_repository.dart';
import 'package:flutter_app/features/chat/data/message_local_dao.dart';
import 'package:flutter_app/features/chat/data/message_repository.dart';
import 'package:flutter_app/features/chat/domain/chat_notifier.dart';
import 'package:flutter_app/shared/models/message.dart';

// ── Test constants ────────────────────────────────────────────────────────────

const _convId = 'conv-test-001';
const _userId = 'user-me-001';
const _otherId = 'user-other-001';

// ── Fake: SecureStorageService ────────────────────────────────────────────────
// Overrides every method so FlutterSecureStorage (a platform channel) is never
// called in the unit-test environment.

class _FakeSecureStorage extends SecureStorageService {
  @override
  Future<String?> readRefreshToken() async => null; // → AuthUnauthenticated

  @override
  Future<void> saveRefreshToken(String token) async {}

  @override
  Future<void> deleteRefreshToken() async {}

  @override
  Future<String> readDeviceId() async => 'test-device-id';
}

// ── Fake: SignalingService ────────────────────────────────────────────────────
// Replaces the socket.io connection with local StreamControllers so tests can
// push events directly without a running server.

class _FakeSignalingService extends SignalingService {
  final _newCtrl = StreamController<MessageNewEvent>.broadcast();
  final _ackCtrl = StreamController<MessageAckEvent>.broadcast();
  final _delCtrl = StreamController<MessageDeletedEvent>.broadcast();
  final _typCtrl = StreamController<TypingEvent>.broadcast();

  @override
  Stream<MessageNewEvent> get onMessageNew => _newCtrl.stream;
  @override
  Stream<MessageAckEvent> get onMessageAck => _ackCtrl.stream;
  @override
  Stream<MessageDeletedEvent> get onMessageDeleted => _delCtrl.stream;
  @override
  Stream<TypingEvent> get onTyping => _typCtrl.stream;

  @override
  void connect(String token) {}
  @override
  void emitTyping({required bool isTyping, required String conversationId}) {}
  @override
  void disconnect() {}

  @override
  void dispose() {
    // Close only our controllers — do NOT call super.dispose() which would
    // try to close the parent's private controllers.
    _newCtrl.close();
    _ackCtrl.close();
    _delCtrl.close();
    _typCtrl.close();
  }

  void injectNew(MessageNewEvent e) => _newCtrl.add(e);
  void injectAck(MessageAckEvent e) => _ackCtrl.add(e);
}

// ── Fake: MessageRepository ───────────────────────────────────────────────────
// Lets each test either block the sendMessage call (to inspect mid-flight DB
// state) or make it throw immediately.

class _FakeMessageRepository extends MessageRepository {
  _FakeMessageRepository() : super(Dio());

  Completer<Message>? _sendHold;
  bool _throwNext = false;

  /// Makes the next [sendMessage] hang until [completeSend] is called.
  void holdNextSend() => _sendHold = Completer<Message>();

  /// Unblocks a previously held send with the given server response.
  void completeSend(Message response) {
    _sendHold!.complete(response);
    _sendHold = null;
  }

  /// Makes the next [sendMessage] throw a network exception.
  void throwOnNextSend() => _throwNext = true;

  @override
  Future<Message> sendMessage({
    required String clientId,
    required String recipientId,
    required MessageType type,
    String? content,
    String? mediaId,
    String? replyToId,
  }) async {
    if (_throwNext) {
      _throwNext = false;
      throw Exception('simulated network error');
    }
    if (_sendHold != null) return _sendHold!.future;
    return Message(
      id: clientId,
      conversationId: _convId,
      senderId: _userId,
      type: type,
      content: content,
      status: MessageStatus.sent,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> markRead(List<String> ids) async {}
  @override
  Future<void> markDelivered(List<String> ids) async {}
  @override
  Future<MessagePage> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit = 40,
  }) async =>
      const MessagePage(messages: [], nextCursor: null);
  @override
  Future<void> deleteMessage(String id) async {}
}

// ── Fake: SyncService ─────────────────────────────────────────────────────────
// All methods are no-ops so test setup does not trigger any network calls.

class _FakeSyncService extends SyncService {
  _FakeSyncService(AppDatabase db) : super(db, Dio());

  @override
  Future<void> syncPendingMessages() async {}
  @override
  Future<void> fetchMissedMessages(String id) async {}
  @override
  Future<void> syncConversations() async {}
  @override
  Future<void> syncAll(String id) async {}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Flushes the microtask queue in multiple passes.
/// NativeDatabase.memory() uses synchronous FFI calls, so a handful of
/// Future.delayed(Duration.zero) round-trips is enough for async chains to
/// propagate through all chained awaits.
Future<void> _pump([int passes = 8]) async {
  for (var i = 0; i < passes; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase testDb;
  late _FakeSignalingService fakeSignaling;
  late _FakeMessageRepository fakeRepo;
  late ProviderContainer container;

  setUp(() async {
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
    fakeSignaling = _FakeSignalingService();
    fakeRepo = _FakeMessageRepository();

    // Seed the conversation row so ChatNotifier._init() finds it.
    await testDb.conversationsDao.upsert(ConversationsTableCompanion(
      id: const Value(_convId),
      otherUserId: const Value(_otherId),
      lastActivity: Value(DateTime.now()),
    ));

    container = ProviderContainer(
      overrides: [
        // Shared in-memory DB — used by the notifier, DAO provider, and fakes.
        appDatabaseProvider.overrideWithValue(testDb),
        // No socket.io: push events via injectNew / injectAck.
        signalingServiceProvider.overrideWithValue(fakeSignaling),
        // Controlled HTTP: block or fail individual calls.
        messageRepositoryProvider.overrideWithValue(fakeRepo),
        // Sync is a no-op — avoids network calls during init.
        syncServiceProvider.overrideWith((ref) => _FakeSyncService(testDb)),
        // Replace platform-channel storage with in-memory stubs.
        secureStorageProvider.overrideWithValue(_FakeSecureStorage()),
        // AuthRepository needs only a base URL — it will never be called since
        // _FakeSecureStorage returns null for the refresh token, causing
        // _tryRestoreSession to exit early (AuthUnauthenticated).
        authRepositoryProvider.overrideWith(
          (_) => AuthRepository(AppConfig.apiBaseUrl),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose(); // cancels notifier subscriptions before we close streams
    fakeSignaling.dispose();
    await testDb.close();
  });

  /// Builds the ChatNotifier for [_convId] and waits for _init() to settle.
  Future<ChatNotifier> buildNotifier() async {
    final notifier = container.read(chatProvider(_convId).notifier);
    await _pump(12);
    return notifier;
  }

  group('ChatNotifier —', () {
    // ── 1. Optimistic send ────────────────────────────────────────────────────

    test(
        'sendText writes a "sending" row immediately, '
        'then promotes it to "sent" once the server responds', () async {
      final notifier = await buildNotifier();
      final dao = container.read(messageLocalDaoProvider);

      // Block the network call so we can inspect the mid-flight DB state.
      fakeRepo.holdNextSend();

      // Start the send without awaiting.
      final sendFuture = notifier.sendText('Hello world');
      await _pump(6); // flush until after the optimistic upsert completes

      // ── Before server ack ─────────────────────────────────────────────────
      final preAck = await dao.getMessages(_convId);
      expect(preAck, hasLength(1),
          reason: 'optimistic row must be in the DB immediately');
      expect(preAck.first.status, MessageStatus.sending,
          reason: 'status must be "sending" while network call is in-flight');
      expect(preAck.first.content, 'Hello world');

      // ── After server ack ──────────────────────────────────────────────────
      fakeRepo.completeSend(Message(
        id: preAck.first.id,
        conversationId: _convId,
        senderId: _userId,
        type: MessageType.text,
        content: 'Hello world',
        status: MessageStatus.sent,
        createdAt: preAck.first.createdAt,
      ));

      await sendFuture;
      await _pump(6); // flush markSynced + Drift watch notification

      final postAck = await dao.getMessages(_convId);
      expect(postAck.first.status, MessageStatus.sent,
          reason: 'status must be promoted to "sent" after server ack');
    });

    // ── 2. Network failure ────────────────────────────────────────────────────

    test('network failure marks the row "failed" in the local DB', () async {
      final notifier = await buildNotifier();
      final dao = container.read(messageLocalDaoProvider);

      fakeRepo.throwOnNextSend();

      await notifier.sendText('This will fail');
      await _pump(6);

      final msgs = await dao.getMessages(_convId);
      expect(msgs, hasLength(1));
      expect(msgs.first.status, MessageStatus.failed,
          reason: '"failed" status must be set when sendMessage throws');
    });

    // ── 3. Socket dedup ───────────────────────────────────────────────────────

    test(
        'injecting the same message:new event twice does not create duplicate '
        'rows (insertOnConflictUpdate deduplicates on the id primary key)',
        () async {
      await buildNotifier();
      final dao = container.read(messageLocalDaoProvider);

      final msgJson = {
        'id': 'msg-dup-001',
        'conversation_id': _convId,
        'sender_id': _otherId,
        'type': 'text',
        'content': 'Hello from the other side',
        'status': 'sent',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_deleted': false,
      };

      fakeSignaling.injectNew(MessageNewEvent(msgJson));
      fakeSignaling.injectNew(MessageNewEvent(msgJson)); // duplicate delivery
      await _pump(12);

      final msgs = await dao.getMessages(_convId);
      expect(
        msgs.where((m) => m.id == 'msg-dup-001'),
        hasLength(1),
        reason: 'only one row must exist after two upserts with the same id',
      );
    });

    // ── 4. Receipt ticks ──────────────────────────────────────────────────────

    test('message:ack event updates the stored status from "sent" to "delivered"',
        () async {
      await buildNotifier();
      final dao = container.read(messageLocalDaoProvider);

      // Pre-seed a sent message.
      await dao.upsertMessage(Message(
        id: 'msg-ack-001',
        conversationId: _convId,
        senderId: _userId,
        type: MessageType.text,
        content: 'Waiting for receipt',
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      ));

      // Inject the "delivered" receipt from the server.
      fakeSignaling.injectAck(
        const MessageAckEvent(messageId: 'msg-ack-001', status: 'delivered'),
      );
      await _pump(12);

      final msgs = await dao.getMessages(_convId);
      final target = msgs.firstWhere((m) => m.id == 'msg-ack-001');
      expect(
        target.status,
        MessageStatus.delivered,
        reason: 'message:ack must tick the status to "delivered"',
      );
    });
  });
}

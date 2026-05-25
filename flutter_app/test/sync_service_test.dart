// Tests for SyncService:
//   1. syncPendingMessages sends messages in oldest-first order
//   2. successfully sent messages are marked isSynced=true in the DB
//   3. messages whose POST fails are left as unsynced for the next retry
//
// All Drift I/O uses an in-memory NativeDatabase — nothing is written to disk.
// HTTP calls are intercepted by a Dio interceptor — no real server needed.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/services/sync_service.dart';
import 'package:flutter_app/core/storage/local_db.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Seeds one pending (un-synced) text message into [db].
Future<void> _seedPending(
  AppDatabase db, {
  required String id,
  required DateTime createdAt,
}) =>
    db.messagesDao.upsert(MessagesTableCompanion(
      id: Value(id),
      conversationId: const Value('conv-sync-001'),
      senderId: const Value('user-001'),
      messageType: const Value('text'),
      content: Value('Content of $id'),
      status: const Value('sending'),
      createdAt: Value(createdAt),
      isSynced: const Value(false),
      isDeleted: const Value(false),
    ));

/// Creates a [Dio] instance whose interceptor calls [onRequest] for every
/// outgoing request and immediately resolves it with an empty 200 response.
/// [onRequest] receives the [RequestOptions] so callers can record call order.
Dio _fakeDio({required void Function(RequestOptions opts) onRequest}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onRequest(options);
        handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{},
        ));
      },
    ),
  );
  return dio;
}

/// Creates a [Dio] instance that rejects every request with a timeout error.
Dio _failingDio() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
          message: 'simulated timeout',
        ));
      },
    ),
  );
  return dio;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncService.syncPendingMessages —', () {
    // ── 1. Ordering ───────────────────────────────────────────────────────────

    test(
        'sends messages in oldest-first order regardless of insertion order',
        () async {
      // Insert in reverse-chronological order to stress-test the sort.
      final t1 = DateTime.utc(2024, 1, 1, 10, 0); // oldest
      final t2 = DateTime.utc(2024, 1, 1, 11, 0);
      final t3 = DateTime.utc(2024, 1, 1, 12, 0); // newest

      await _seedPending(db, id: 'msg-3', createdAt: t3); // inserted first
      await _seedPending(db, id: 'msg-1', createdAt: t1);
      await _seedPending(db, id: 'msg-2', createdAt: t2);

      final sentIds = <String>[];
      final service = SyncService(
        db,
        _fakeDio(onRequest: (opts) {
          if (opts.method == 'POST') {
            final data = opts.data as Map<String, dynamic>;
            sentIds.add(data['id'] as String);
          }
        }),
      );

      await service.syncPendingMessages();

      expect(
        sentIds,
        ['msg-1', 'msg-2', 'msg-3'],
        reason: 'messages must be delivered to the server in chronological order '
            'so the server reconstructs the correct conversation sequence',
      );
    });

    // ── 2. Success → isSynced = true ──────────────────────────────────────────

    test(
        'marks a successfully sent message as isSynced=true and status="sent"',
        () async {
      await _seedPending(
        db,
        id: 'msg-sync-ok',
        createdAt: DateTime.utc(2024),
      );

      final service = SyncService(db, _fakeDio(onRequest: (_) {}));
      await service.syncPendingMessages();

      final rows = await (db.select(db.messagesTable)
            ..where((m) => m.id.equals('msg-sync-ok')))
          .get();

      expect(rows, hasLength(1));
      expect(rows.first.isSynced, isTrue,
          reason: 'row must be marked isSynced=true after a successful POST');
      expect(rows.first.status, 'sent',
          reason: 'status must be promoted to "sent"');
    });

    // ── 3. Failure → stays unsynced ───────────────────────────────────────────

    test(
        'leaves a message unsynced when the server call fails '
        '(error is swallowed; row is retried on next reconnect)',
        () async {
      await _seedPending(
        db,
        id: 'msg-sync-fail',
        createdAt: DateTime.utc(2024),
      );

      final service = SyncService(db, _failingDio());

      // syncPendingMessages must not throw — errors are swallowed per the impl.
      await expectLater(service.syncPendingMessages(), completes);

      final rows = await (db.select(db.messagesTable)
            ..where((m) => m.id.equals('msg-sync-fail')))
          .get();

      expect(rows.first.isSynced, isFalse,
          reason: 'row must remain unsynced so it is retried on the next call');
      expect(rows.first.status, 'sending',
          reason: 'status must not change when the POST fails');
    });

    // ── 4. Empty outbox → no requests ─────────────────────────────────────────

    test('makes no HTTP calls when the outbox is empty', () async {
      var callCount = 0;
      final service = SyncService(
        db,
        _fakeDio(onRequest: (_) => callCount++),
      );

      await service.syncPendingMessages();

      expect(callCount, 0,
          reason: 'no POST should be made when there are no pending messages');
    });
  });
}

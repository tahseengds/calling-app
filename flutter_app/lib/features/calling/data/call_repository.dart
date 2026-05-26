import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/local_db.dart';
import '../domain/call_state.dart';

class CallRepository {
  final Dio _dio;
  final AppDatabase _db;

  const CallRepository(this._dio, this._db);

  // ── TURN credentials ────────────────────────────────────────────────────────

  /// Fetch TURN/STUN credentials for a new call.
  /// Returns a list of ICE server config maps ready for `RTCPeerConnection`.
  Future<List<Map<String, dynamic>>> getTurnCredentials() async {
    try {
      final resp = await _dio
          .get<Map<String, dynamic>>('/api/calls/turn-credentials');
      final servers = resp.data?['ice_servers'] as List<dynamic>? ?? [];
      return servers
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      // Fallback: public STUN only (no TURN relay)
      return [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
    }
  }

  // ── Call history ─────────────────────────────────────────────────────────────

  /// Fetch paginated call history from the API and write to Drift.
  ///
  /// The `/api/calls/history` endpoint is not yet implemented on the
  /// backend (tracked as a follow-up). When it 404s we silently return an
  /// empty list — the UI keeps streaming from the local Drift cache via
  /// [watchCachedHistory], so calls made on *this* device still appear.
  Future<List<CallRecord>> getCallHistory({
    String? cursor,
    int limit = 30,
  }) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/calls/history',
        queryParameters: {
          'limit': limit,
          'cursor': ?cursor,
        },
      );
      final items = (resp.data?['items'] as List<dynamic>?) ?? [];
      final records = items
          .map((e) => CallRecord.fromJson(e as Map<String, dynamic>))
          .toList();

      // Cache to Drift (best-effort — ignore failures)
      for (final rec in records) {
        try {
          await _db.callRecordsDao.upsert(
            CallRecordsTableCompanion(
              id: Value(rec.id),
              otherUserId: Value(rec.peerUser.id),
              callType: Value(rec.callType.name),
              status: Value(
                '${rec.direction.name}_${rec.status}', // e.g. 'incoming_missed'
              ),
              startedAt: Value(rec.startedAt),
              durationSeconds: Value(rec.durationSeconds),
            ),
          );
        } catch (_) {}
      }
      return records;
    } on DioException catch (e) {
      // 404 → endpoint not yet shipped. Other errors → log and degrade.
      if (e.response?.statusCode != 404) {
        // ignore: avoid_print
        print('[call_repository] getCallHistory failed: ${e.message}');
      }
      return const [];
    }
  }

  /// Fetch a single call record.
  ///
  /// Same caveat as [getCallHistory]: returns null when the endpoint is
  /// unavailable rather than throwing.
  Future<CallRecord?> getCall(String callId) async {
    try {
      final resp =
          await _dio.get<Map<String, dynamic>>('/api/calls/$callId');
      if (resp.data == null) {
        return null;
      }
      return CallRecord.fromJson(resp.data!);
    } on DioException {
      return null;
    }
  }

  /// Watch cached call records from Drift (offline-first).
  Stream<List<CallRecordRow>> watchCachedHistory() =>
      _db.callRecordsDao.watchAll();
}

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepository(
    ref.watch(dioProvider),
    ref.watch(appDatabaseProvider),
  );
});

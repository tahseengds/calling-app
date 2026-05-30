import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/local_db.dart';
import '../domain/call_state.dart';

/// One page of call history: the records plus the cursor to fetch the next
/// (older) page, or null when the end has been reached.
class CallHistoryPageResult {
  final List<CallRecord> records;
  final String? nextCursor;
  const CallHistoryPageResult({required this.records, required this.nextCursor});
}

class CallRepository {
  final Dio _dio;
  final AppDatabase _db;

  const CallRepository(this._dio, this._db);

  // ── TURN credentials ────────────────────────────────────────────────────────

  /// Fetch TURN/STUN credentials for a new call.
  ///
  /// Backend returns Coturn `use-auth-secret` style credentials:
  ///   { username, credential, ttl, uris: [stun:…, turn:…, turn:…?transport=tcp, turns:…] }
  /// — NOT a pre-built `ice_servers` array. We assemble the
  /// RTCPeerConnection-shaped list here: one entry per URI, with the
  /// credential pair attached to every turn/turns URL (STUN URLs don't
  /// take credentials, so we omit them there).
  ///
  /// Without this translation the previous code read a non-existent
  /// `ice_servers` field, fell through to an empty list, and every call
  /// ran with no STUN/TURN — meaning ICE could only find host candidates
  /// and any cross-NAT call would silently fail with the classic
  /// "have-local-offer" ICE-restart-glare loop.
  Future<List<Map<String, dynamic>>> getTurnCredentials() async {
    try {
      final resp = await _dio
          .get<Map<String, dynamic>>('/api/calls/turn-credentials');
      final data = resp.data;
      if (data == null) return _fallbackIceServers();

      final uris = (data['uris'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      final username = data['username'] as String?;
      final credential = data['credential'] as String?;

      if (uris.isEmpty) return _fallbackIceServers();

      final servers = <Map<String, dynamic>>[];
      for (final uri in uris) {
        final isTurn = uri.startsWith('turn:') || uri.startsWith('turns:');
        if (isTurn && username != null && credential != null) {
          servers.add({
            'urls': uri,
            'username': username,
            'credential': credential,
          });
        } else {
          // STUN URL, or TURN without credentials (degraded — log so it's
          // visible). STUN entries deliberately omit the credentials.
          servers.add({'urls': uri});
        }
      }
      debugPrint(
          '[call] iceServers loaded: ${servers.length} entries (uris=$uris)');
      return servers;
    } catch (e, st) {
      // Previously swallowed silently — now we know when TURN fetch fails.
      debugPrint('[call] getTurnCredentials failed, falling back to public STUN: $e\n$st');
      return _fallbackIceServers();
    }
  }

  static List<Map<String, dynamic>> _fallbackIceServers() => const [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];

  // ── Call history ─────────────────────────────────────────────────────────────

  /// Fetch one page of call history from the API and write to Drift.
  ///
  /// Returns both the records and the `next_cursor` (null when there are no
  /// older calls) so callers can implement infinite scroll. On any
  /// DioException we degrade to an empty page — the UI keeps streaming from the
  /// local Drift cache via [watchCachedHistory], so calls made on *this* device
  /// still appear.
  Future<CallHistoryPageResult> getCallHistoryPage({
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
      final nextCursor = resp.data?['next_cursor'] as String?;

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
      return CallHistoryPageResult(records: records, nextCursor: nextCursor);
    } on DioException catch (e) {
      debugPrint('[call_repository] getCallHistory failed: ${e.message}');
      return const CallHistoryPageResult(records: [], nextCursor: null);
    }
  }

  /// Convenience wrapper that returns just the first page's records (no cursor).
  Future<List<CallRecord>> getCallHistory({
    String? cursor,
    int limit = 30,
  }) async =>
      (await getCallHistoryPage(cursor: cursor, limit: limit)).records;

  /// Watch cached call records from Drift (offline-first).
  Stream<List<CallRecordRow>> watchCachedHistory() =>
      _db.callRecordsDao.watchAll();

  // ── Interrupted-call reconciliation (FIX 6) ─────────────────────────────────
  //
  // When the app is force-killed mid-call, ref.onDispose doesn't fire and
  // the call_notifier can't tell the backend the call ended. Same applies
  // when the OS interrupts audio for a cellular call. To recover gracefully:
  //
  //   1. On every "interrupted" end (force-kill simulated via app lifecycle,
  //      audio interruption, ICE failure, mid-call block), stash a record
  //      via [stashInterruptedCall].
  //   2. On next app launch, call [syncInterruptedCalls] — POSTs to
  //      /api/calls/log, then clears the local copy on success.
  //
  // Storage: SharedPreferences under a single JSON-list key. This is small
  // (a few records max, only between failure and next launch) so a full
  // Drift table is overkill; prefs is simpler and survives app restart.

  static const String _interruptedKey = 'lumio.calls.interrupted_v1';

  /// Append a minimal record describing an interrupted call. Safe to call
  /// repeatedly; each call is stored independently and reconciled on next
  /// launch.
  Future<void> stashInterruptedCall({
    required String callId,
    required String peerUserId,
    required String callType,
    required String direction,
    required DateTime startedAt,
    required DateTime? connectedAt,
    required DateTime endedAt,
    required int durationSeconds,
    required String reason,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_interruptedKey) ?? const [];
      final entry = jsonEncode({
        'call_id': callId,
        'peer_user_id': peerUserId,
        'call_type': callType,
        'direction': direction,
        'started_at': startedAt.toUtc().toIso8601String(),
        'connected_at': connectedAt?.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'reason': reason,
      });
      await prefs.setStringList(_interruptedKey, [...existing, entry]);
      debugPrint('[call_repo] stashed interrupted call $callId ($reason)');
    } catch (e) {
      debugPrint('[call_repo] stashInterruptedCall failed: $e');
    }
  }

  /// On app open: read any stashed interrupted-call records and POST each
  /// to /api/calls/log. Clears the local list on full success; keeps
  /// failures around for the next launch so we don't lose them on a
  /// transient network blip. Safe to call multiple times (idempotent via
  /// call_id on the backend).
  Future<void> syncInterruptedCalls() async {
    final SharedPreferences prefs;
    final List<String> stashed;
    try {
      prefs = await SharedPreferences.getInstance();
      stashed = prefs.getStringList(_interruptedKey) ?? const [];
      if (stashed.isEmpty) return;
    } catch (e) {
      debugPrint('[call_repo] syncInterruptedCalls read failed: $e');
      return;
    }
    debugPrint(
        '[call_repo] reconciling ${stashed.length} interrupted call(s)');

    final remaining = <String>[];
    for (final raw in stashed) {
      try {
        final body = jsonDecode(raw) as Map<String, dynamic>;
        // Backend dedups on call_id; POSTing the same id again is a no-op.
        await _dio.post<Map<String, dynamic>>('/api/calls/log', data: body);
      } catch (e) {
        // Keep the record around to retry on next launch.
        debugPrint('[call_repo] log replay failed for one entry: $e');
        remaining.add(raw);
      }
    }
    try {
      if (remaining.isEmpty) {
        await prefs.remove(_interruptedKey);
      } else {
        await prefs.setStringList(_interruptedKey, remaining);
      }
    } catch (e) {
      debugPrint('[call_repo] syncInterruptedCalls write failed: $e');
    }
  }
}

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepository(
    ref.watch(dioProvider),
    ref.watch(appDatabaseProvider),
  );
});

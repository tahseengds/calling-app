import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/local_db.dart';
import '../data/call_repository.dart';

/// Cached call records (offline-first) — the source for the missed-call badge.
final cachedCallHistoryProvider = StreamProvider<List<CallRecordRow>>((ref) {
  return ref.watch(callRepositoryProvider).watchCachedHistory();
});

/// Persisted "last time the user looked at the Calls tab". Missed calls newer
/// than this drive the bottom-nav badge, so the count is meaningful across
/// restarts instead of re-counting the entire history every launch.
class CallsLastSeenNotifier extends StateNotifier<DateTime?> {
  CallsLastSeenNotifier() : super(null) {
    _load();
  }

  static const _key = 'calls_last_seen_ms';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key);
    if (ms != null) {
      state = DateTime.fromMillisecondsSinceEpoch(ms);
    } else {
      // First-ever launch: treat everything up to now as already seen so a
      // backlog of old missed calls doesn't light up the badge.
      await markSeen();
    }
  }

  Future<void> markSeen() async {
    final now = DateTime.now();
    state = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, now.millisecondsSinceEpoch);
  }
}

final callsLastSeenProvider =
    StateNotifierProvider<CallsLastSeenNotifier, DateTime?>(
  (ref) => CallsLastSeenNotifier(),
);

/// Count of missed calls newer than the last Calls-tab view.
final missedCallsBadgeProvider = Provider<int>((ref) {
  final rows = ref.watch(cachedCallHistoryProvider).maybeWhen(
        data: (r) => r,
        orElse: () => const <CallRecordRow>[],
      );
  final lastSeen = ref.watch(callsLastSeenProvider);
  if (lastSeen == null) return 0; // prefs still loading
  return rows
      .where((r) => r.status == 'missed' && r.startedAt.isAfter(lastSeen))
      .length;
});

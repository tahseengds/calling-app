import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/signaling_service.dart';
import '../../../core/storage/local_db.dart';
import '../../../shared/models/user.dart';

/// Live presence for a single userId.
/// Starts with the cached value from Drift, then updates from socket events.
final presenceProvider =
    StreamProvider.family<PresenceStatus, String>((ref, userId) async* {
  // Seed from local DB.
  final db = ref.watch(appDatabaseProvider);
  final cached = await db.usersDao.getById(userId);
  if (cached != null) {
    yield PresenceStatus.values.firstWhere(
      (e) => e.name == cached.presence,
      orElse: () => PresenceStatus.offline,
    );
  } else {
    yield PresenceStatus.offline;
  }

  // Request current presence from the server.
  final signaling = ref.watch(signalingServiceProvider);
  signaling.requestPresence([userId]);

  // Stream live updates.
  yield* signaling.onPresence
      .where((e) => e.userId == userId)
      .map((e) => e.status == 'online' ? PresenceStatus.online : PresenceStatus.offline);
});

/// Last-seen string for display in the chat app bar.
final lastSeenProvider = FutureProvider.family<String, String>((ref, userId) async {
  final db = ref.watch(appDatabaseProvider);
  final row = await db.usersDao.getById(userId);
  if (row == null) return 'last seen recently';
  final diff = DateTime.now().difference(row.lastSeen);
  if (diff.inMinutes < 2) return 'last seen just now';
  if (diff.inHours < 1) return 'last seen ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'last seen ${diff.inHours}h ago';
  return 'last seen ${diff.inDays}d ago';
});

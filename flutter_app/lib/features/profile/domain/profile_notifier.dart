import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/models/user.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../auth/domain/auth_state.dart';
import '../data/profile_repository.dart';

class ProfileNotifier extends StateNotifier<AsyncValue<User>> {
  final ProfileRepository _repo;
  final Ref _ref;

  ProfileNotifier(this._repo, this._ref) : super(_seed(_ref)) {
    // Background refresh — UI is already showing the auth-cached user
    // (if any), so failures here shouldn't flip the screen to an error
    // state. We only show loading/error when we genuinely have nothing.
    load();
  }

  /// Reuse the User AuthNotifier already loaded during sign-in / restore so
  /// the profile screen renders immediately instead of racing its own
  /// getMe() against the Dio interceptor's token refresh.
  static AsyncValue<User> _seed(Ref ref) {
    final auth = ref.read(authNotifierProvider);
    if (auth is AuthAuthenticated) return AsyncData(auth.me);
    return const AsyncLoading();
  }

  void _syncAuthCache(User user) {
    _ref.read(authNotifierProvider.notifier).updateCachedUser(user);
  }

  Future<void> load() async {
    // Only show the loading spinner if we have nothing to display yet —
    // a background refresh shouldn't flash the spinner on top of perfectly
    // good cached data.
    if (!state.hasValue) {
      state = const AsyncLoading();
    }
    try {
      final user = await _repo.getMe();
      state = AsyncData(user);
      _syncAuthCache(user);
    } catch (e, st) {
      if (!state.hasValue) {
        // Cold load with no cache → surface the error so the UI can show
        // a Retry button.
        state = AsyncError(e, st);
      } else {
        // We're showing cached data — keep it. Log so a persistent failure
        // is still debuggable, but don't replace the screen with an error.
        debugPrint('[profile] background refresh failed (keeping cached): $e');
      }
    }
  }

  Future<void> updateName(String name) async {
    final updated = await _repo.updateName(name);
    state = AsyncData(updated);
    _syncAuthCache(updated);
  }

  Future<void> updateAvatar(String filePath) async {
    final updated = await _repo.updateAvatar(filePath);
    state = AsyncData(updated);
    _syncAuthCache(updated);
  }
}

final profileNotifierProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<User>>((ref) {
  return ProfileNotifier(ref.watch(profileRepositoryProvider), ref);
});

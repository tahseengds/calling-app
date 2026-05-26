import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/config/app_config.dart';
import '../../../core/mock/mock_data.dart';
import '../../../shared/models/user.dart';
import '../../auth/domain/auth_notifier.dart';
import '../data/profile_repository.dart';

class ProfileNotifier extends StateNotifier<AsyncValue<User>> {
  final ProfileRepository _repo;
  final Ref _ref;

  ProfileNotifier(this._repo, this._ref) : super(const AsyncLoading()) {
    load();
  }

  void _syncAuthCache(User user) {
    _ref.read(authNotifierProvider.notifier).updateCachedUser(user);
  }

  Future<void> load() async {
    if (AppConfig.uiOnly) {
      state = AsyncData(MockData.currentUser);
      return;
    }
    state = const AsyncLoading();
    try {
      final user = await _repo.getMe();
      state = AsyncData(user);
      _syncAuthCache(user);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> updateName(String name) async {
    if (AppConfig.uiOnly) {
      final current = state.value ?? MockData.currentUser;
      state = AsyncData(User(
        id: current.id,
        name: name,
        email: current.email,
        avatarUrl: current.avatarUrl,
        lastSeen: current.lastSeen,
        presence: current.presence,
      ));
      return;
    }
    final updated = await _repo.updateName(name);
    state = AsyncData(updated);
    _syncAuthCache(updated);
  }

  Future<void> updateAvatar(String filePath) async {
    if (AppConfig.uiOnly) {
      return;
    }
    final updated = await _repo.updateAvatar(filePath);
    state = AsyncData(updated);
    _syncAuthCache(updated);
  }
}

final profileNotifierProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<User>>((ref) {
  return ProfileNotifier(ref.watch(profileRepositoryProvider), ref);
});

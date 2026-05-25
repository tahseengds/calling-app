import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/config/app_config.dart';
import '../../../core/mock/mock_data.dart';
import '../../../shared/models/user.dart';
import '../data/profile_repository.dart';

class ProfileNotifier extends StateNotifier<AsyncValue<User>> {
  final ProfileRepository _repo;

  ProfileNotifier(this._repo) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    if (AppConfig.uiOnly) {
      state = AsyncData(MockData.currentUser);
      return;
    }
    state = const AsyncLoading();
    try {
      state = AsyncData(await _repo.getMe());
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
        phone: current.phone,
        avatarUrl: current.avatarUrl,
        lastSeen: current.lastSeen,
        presence: current.presence,
      ));
      return;
    }
    final updated = await _repo.updateName(name);
    state = AsyncData(updated);
  }

  Future<void> updatePhone(String phone) async {
    if (AppConfig.uiOnly) {
      final current = state.value ?? MockData.currentUser;
      state = AsyncData(User(
        id: current.id,
        name: current.name,
        phone: phone,
        avatarUrl: current.avatarUrl,
        lastSeen: current.lastSeen,
        presence: current.presence,
      ));
      return;
    }
    final updated = await _repo.updatePhone(phone);
    state = AsyncData(updated);
  }

  Future<void> updateAvatar(String filePath) async {
    if (AppConfig.uiOnly) {
      // Avatar upload needs the API; keep the current mock user locally.
      return;
    }
    final updated = await _repo.updateAvatar(filePath);
    state = AsyncData(updated);
  }
}

final profileNotifierProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<User>>((ref) {
  return ProfileNotifier(ref.watch(profileRepositoryProvider));
});

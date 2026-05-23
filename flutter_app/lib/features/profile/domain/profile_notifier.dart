import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/user.dart';
import '../data/profile_repository.dart';

class ProfileNotifier extends StateNotifier<AsyncValue<User>> {
  final ProfileRepository _repo;

  ProfileNotifier(this._repo) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _repo.getMe());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> updateName(String name) async {
    final updated = await _repo.updateName(name);
    state = AsyncData(updated);
  }

  Future<void> updateAvatar(String filePath) async {
    final updated = await _repo.updateAvatar(filePath);
    state = AsyncData(updated);
  }
}

final profileNotifierProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<User>>((ref) {
  return ProfileNotifier(ref.watch(profileRepositoryProvider));
});

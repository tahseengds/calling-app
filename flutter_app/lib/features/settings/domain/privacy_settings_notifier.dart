import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/settings_repository.dart';
import 'models/privacy_settings.dart';
import 'settings_save_error.dart';

class PrivacySettingsNotifier
    extends StateNotifier<AsyncValue<PrivacySettings>> {
  final SettingsRepository _repo;
  final Ref _ref;

  PrivacySettingsNotifier(this._repo, this._ref)
      : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      final prefs = await _repo.getPrivacy();
      state = AsyncData(prefs);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> _apply(PrivacySettings next) async {
    HapticFeedback.selectionClick();
    final previous = state.value;
    state = AsyncData(next);
    try {
      final saved = await _repo.updatePrivacy(next);
      state = AsyncData(saved);
    } catch (e, st) {
      if (previous != null) {
        state = AsyncData(previous);
        _ref.read(settingsSaveErrorProvider.notifier).state = e;
      } else {
        state = AsyncError(e, st);
      }
    }
  }

  PrivacySettings get _current => state.value ?? const PrivacySettings();

  Future<void> setLastSeen(VisibilityLevel v) =>
      _apply(_current.copyWith(lastSeenVisibility: v));
  Future<void> setProfilePhoto(VisibilityLevel v) =>
      _apply(_current.copyWith(profilePhotoVisibility: v));
  Future<void> setAbout(VisibilityLevel v) =>
      _apply(_current.copyWith(aboutVisibility: v));
  Future<void> setOnlineStatus(OnlineVisibility v) =>
      _apply(_current.copyWith(onlineStatusVisibility: v));
  Future<void> setGroupsWhoCanAdd(GroupsWhoCanAdd v) =>
      _apply(_current.copyWith(groupsWhoCanAdd: v));
  Future<void> setReadReceipts(bool v) =>
      _apply(_current.copyWith(readReceipts: v));
  Future<void> setSilenceUnknownCallers(bool v) =>
      _apply(_current.copyWith(callsSilenceUnknown: v));
  Future<void> setAppLockEnabled(bool v) =>
      _apply(_current.copyWith(appLockEnabled: v));
  Future<void> setAppLockAutoLockMinutes(int v) =>
      _apply(_current.copyWith(appLockAutoLockMinutes: v));
}

final privacySettingsProvider = StateNotifierProvider<PrivacySettingsNotifier,
    AsyncValue<PrivacySettings>>((ref) {
  return PrivacySettingsNotifier(ref.watch(settingsRepositoryProvider), ref);
});

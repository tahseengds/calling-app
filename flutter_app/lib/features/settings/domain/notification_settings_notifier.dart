import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/config/app_config.dart';
import '../data/settings_repository.dart';
import 'models/notification_preferences.dart';

/// Reads + writes the user's NotificationPreferences. Toggle setters
/// update local state optimistically, then PUT the server; on failure
/// they roll back.
class NotificationSettingsNotifier
    extends StateNotifier<AsyncValue<NotificationPreferences>> {
  final SettingsRepository _repo;

  NotificationSettingsNotifier(this._repo) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    if (AppConfig.uiOnly) {
      state = const AsyncData(NotificationPreferences());
      return;
    }
    state = const AsyncLoading();
    try {
      final prefs = await _repo.getNotifications();
      state = AsyncData(prefs);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> _apply(NotificationPreferences next) async {
    final previous = state.value;
    state = AsyncData(next);
    if (AppConfig.uiOnly) return;
    try {
      final saved = await _repo.updateNotifications(next);
      state = AsyncData(saved);
    } catch (e, st) {
      if (previous != null) {
        state = AsyncData(previous);
      } else {
        state = AsyncError(e, st);
      }
      rethrow;
    }
  }

  NotificationPreferences get _current =>
      state.value ?? const NotificationPreferences();

  Future<void> setMessagesEnabled(bool v) =>
      _apply(_current.copyWith(messagesEnabled: v));
  Future<void> setGroupMessagesEnabled(bool v) =>
      _apply(_current.copyWith(groupMessagesEnabled: v));
  Future<void> setCallsEnabled(bool v) =>
      _apply(_current.copyWith(callsEnabled: v));
  Future<void> setReactionNotifications(bool v) =>
      _apply(_current.copyWith(reactionNotifications: v));
  Future<void> setMentionNotifications(bool v) =>
      _apply(_current.copyWith(mentionNotifications: v));
  Future<void> setShowPreview(bool v) =>
      _apply(_current.copyWith(showPreview: v));
  Future<void> setVibrate(bool v) => _apply(_current.copyWith(vibrate: v));
  Future<void> setHighPriority(bool v) =>
      _apply(_current.copyWith(highPriorityNotifications: v));
  Future<void> setMessageSound(String id) =>
      _apply(_current.copyWith(messageSound: id));
  Future<void> setCallRingtone(String id) =>
      _apply(_current.copyWith(callRingtone: id));
  Future<void> setQuietHoursEnabled(bool v) =>
      _apply(_current.copyWith(quietHoursEnabled: v));
  Future<void> setQuietHoursStart(String hhmm) =>
      _apply(_current.copyWith(quietHoursStart: hhmm));
  Future<void> setQuietHoursEnd(String hhmm) =>
      _apply(_current.copyWith(quietHoursEnd: hhmm));
}

final notificationSettingsProvider = StateNotifierProvider<
    NotificationSettingsNotifier, AsyncValue<NotificationPreferences>>((ref) {
  return NotificationSettingsNotifier(ref.watch(settingsRepositoryProvider));
});

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/settings_repository.dart';
import 'models/notification_preferences.dart';
import 'settings_save_error.dart';

/// Reads + writes the user's NotificationPreferences. Toggle setters
/// update local state optimistically, then PUT the server; on failure
/// they roll back and surface the error via [settingsSaveErrorProvider].
class NotificationSettingsNotifier
    extends StateNotifier<AsyncValue<NotificationPreferences>> {
  final SettingsRepository _repo;
  final Ref _ref;

  NotificationSettingsNotifier(this._repo, this._ref)
      : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      final prefs = await _repo.getNotifications();
      state = AsyncData(prefs);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> _apply(NotificationPreferences next) async {
    HapticFeedback.selectionClick();
    final previous = state.value;
    state = AsyncData(next);
    try {
      final saved = await _repo.updateNotifications(next);
      state = AsyncData(saved);
    } catch (e, st) {
      // Roll the optimistic change back and surface a "couldn't save" message
      // instead of throwing into the void (the toggle reverting alone left the
      // user with no explanation).
      if (previous != null) {
        state = AsyncData(previous);
        _ref.read(settingsSaveErrorProvider.notifier).state = e;
      } else {
        state = AsyncError(e, st);
      }
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
  return NotificationSettingsNotifier(
      ref.watch(settingsRepositoryProvider), ref);
});

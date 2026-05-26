import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/dio_client.dart';
import '../domain/models/notification_preferences.dart';
import '../domain/models/privacy_settings.dart';

/// One source for both notification + privacy settings.
///
/// Reads are read-through: hit the network, fall back to the local
/// `shared_preferences` mirror on failure. Writes are write-through:
/// PUT the server, then mirror the validated response locally.
class SettingsRepository {
  final Dio _dio;
  SettingsRepository(Dio dio) : _dio = dio;

  static const _kNotificationsKey = 'settings:notifications';
  static const _kPrivacyKey = 'settings:privacy';

  // ── Notifications ──────────────────────────────────────────────────────

  Future<NotificationPreferences> getNotifications() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/users/me/settings/notifications',
      );
      final prefs = NotificationPreferences.fromJson(resp.data!);
      await _cacheNotifications(prefs);
      return prefs;
    } catch (_) {
      final cached = await _readCachedNotifications();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<NotificationPreferences> updateNotifications(
    NotificationPreferences prefs,
  ) async {
    final resp = await _dio.put<Map<String, dynamic>>(
      '/api/users/me/settings/notifications',
      data: prefs.toJson(),
    );
    final updated = NotificationPreferences.fromJson(resp.data!);
    await _cacheNotifications(updated);
    return updated;
  }

  Future<void> _cacheNotifications(NotificationPreferences prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNotificationsKey, jsonEncode(prefs.toJson()));
  }

  Future<NotificationPreferences?> _readCachedNotifications() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kNotificationsKey);
    if (raw == null) return null;
    try {
      return NotificationPreferences.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Privacy ────────────────────────────────────────────────────────────

  Future<PrivacySettings> getPrivacy() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/users/me/settings/privacy',
      );
      final prefs = PrivacySettings.fromJson(resp.data!);
      await _cachePrivacy(prefs);
      return prefs;
    } catch (_) {
      final cached = await _readCachedPrivacy();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<PrivacySettings> updatePrivacy(PrivacySettings prefs) async {
    final resp = await _dio.put<Map<String, dynamic>>(
      '/api/users/me/settings/privacy',
      data: prefs.toJson(),
    );
    final updated = PrivacySettings.fromJson(resp.data!);
    await _cachePrivacy(updated);
    return updated;
  }

  Future<void> _cachePrivacy(PrivacySettings prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrivacyKey, jsonEncode(prefs.toJson()));
  }

  Future<PrivacySettings?> _readCachedPrivacy() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kPrivacyKey);
    if (raw == null) return null;
    try {
      return PrivacySettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(dioProvider)),
);

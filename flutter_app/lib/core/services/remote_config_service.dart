import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin wrapper over Firebase Remote Config.
///
/// Every value has a safe in-app default, so the app behaves correctly even
/// when the Firebase Console has nothing configured (and when a fetch fails
/// offline). The version floors default to `0.0.0`, which means "force-update
/// is off" until you raise them in the Console — no version can be below
/// 0.0.0, so [UpdateGate] is a no-op out of the box.
class RemoteConfigService {
  RemoteConfigService([FirebaseRemoteConfig? rc])
      : _rc = rc ?? FirebaseRemoteConfig.instance;

  final FirebaseRemoteConfig _rc;

  // Keys — keep in sync with the Firebase Console parameter names.
  static const kMinSupportedVersion = 'min_supported_version';
  static const kLatestVersion = 'latest_version';
  static const kUpdateUrlAndroid = 'update_url_android';
  static const kUpdateUrlIos = 'update_url_ios';
  static const kMaintenanceMode = 'maintenance_mode';
  static const kMaintenanceMessage = 'maintenance_message';

  static const Map<String, Object> _defaults = <String, Object>{
    // '0.0.0' floors mean nothing is forced until raised in the Console.
    kMinSupportedVersion: '0.0.0',
    kLatestVersion: '0.0.0',
    kUpdateUrlAndroid:
        'https://play.google.com/store/apps/details?id=tech.tahseen.lumin',
    kUpdateUrlIos: 'https://apps.apple.com/app/lumio',
    kMaintenanceMode: false,
    kMaintenanceMessage:
        "We're doing some quick maintenance. Please check back shortly.",
  };

  /// Fetch + activate once at startup. Best-effort: on any failure we keep the
  /// in-app defaults (or the last activated values) and never block boot.
  Future<void> init() async {
    try {
      await _rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          // One hour is the production-friendly floor (Firebase throttles more
          // aggressive intervals anyway); plenty fresh for an update gate.
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await _rc.setDefaults(_defaults);
      await _rc.fetchAndActivate();
    } catch (e) {
      debugPrint('[remote_config] init failed (using defaults): $e');
    }
  }

  String get minSupportedVersion => _string(kMinSupportedVersion);
  String get latestVersion => _string(kLatestVersion);
  String get updateUrlAndroid => _string(kUpdateUrlAndroid);
  String get updateUrlIos => _string(kUpdateUrlIos);
  bool get maintenanceMode => _bool(kMaintenanceMode);
  String get maintenanceMessage => _string(kMaintenanceMessage);

  String _string(String key) {
    try {
      final v = _rc.getString(key);
      if (v.isNotEmpty) return v;
    } catch (_) {/* fall through to default */}
    return _defaults[key] as String? ?? '';
  }

  bool _bool(String key) {
    try {
      return _rc.getBool(key);
    } catch (_) {
      return _defaults[key] as bool? ?? false;
    }
  }
}

final remoteConfigServiceProvider = Provider<RemoteConfigService>(
  (_) => RemoteConfigService(),
);

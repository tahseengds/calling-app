// Battery optimization service (prompt 15).
//
// Aggressive OEM battery managers (Xiaomi, Huawei, Oppo, Vivo, Samsung) will
// silently kill the FCM listener and the foreground CallService unless the
// user explicitly whitelists the app. The Android platform has no public API
// to grant the whitelist programmatically — we can only nudge the user into
// the right settings screen and show OEM-specific text.
//
// This service wraps the MethodChannel methods exposed by MainActivity.kt
// for that nudge.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OemHints {
  final String manufacturer;
  final String model;
  final bool isAggressive;
  final String? autoStartLabel;

  const OemHints({
    required this.manufacturer,
    required this.model,
    required this.isAggressive,
    this.autoStartLabel,
  });

  static OemHints empty() => const OemHints(
        manufacturer: '',
        model: '',
        isAggressive: false,
        autoStartLabel: null,
      );

  factory OemHints.fromMap(Map<String, dynamic> map) => OemHints(
        manufacturer: (map['manufacturer'] as String?) ?? '',
        model: (map['model'] as String?) ?? '',
        isAggressive: (map['isAggressive'] as bool?) ?? false,
        autoStartLabel: map['autoStartLabel'] as String?,
      );
}

class BatteryOptimizationService {
  BatteryOptimizationService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('familylink/calls');

  final MethodChannel _channel;

  /// Whether the OS considers our app exempt from doze / battery optimization.
  ///
  /// Returns `true` on pre-M devices and non-Android platforms (nothing to
  /// guard against there). Returns `true` on errors as a safe fallback so
  /// we don't pester the user when we can't detect the state.
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb) return true;
    try {
      final result = await _channel
          .invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  /// Open the system battery-optimization settings screen.
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } on MissingPluginException {
      /* tests */
    } on PlatformException {
      /* swallow */
    }
  }

  /// Open the per-app settings screen (fallback).
  Future<void> openAppSettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on MissingPluginException {
      /* tests */
    } on PlatformException {
      /* swallow */
    }
  }

  Future<OemHints> getOemHints() async {
    if (kIsWeb) return OemHints.empty();
    try {
      final raw = await _channel.invokeMethod<dynamic>('getOemHints');
      if (raw is Map) {
        final map = <String, dynamic>{};
        for (final entry in raw.entries) {
          if (entry.key is String) map[entry.key as String] = entry.value;
        }
        return OemHints.fromMap(map);
      }
      return OemHints.empty();
    } on MissingPluginException {
      return OemHints.empty();
    } on PlatformException {
      return OemHints.empty();
    }
  }

  /// Try to open the OEM-specific autostart screen. Returns false if we
  /// couldn't find a known intent — caller should fall back to
  /// [openAppSettings].
  Future<bool> openOemAutoStartSettings() async {
    if (kIsWeb) return false;
    try {
      final ok =
          await _channel.invokeMethod<bool>('openOemAutoStartSettings');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

final batteryOptimizationServiceProvider =
    Provider<BatteryOptimizationService>(
  (_) => BatteryOptimizationService(),
);

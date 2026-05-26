import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum AuthOutcome {
  /// Biometric prompt succeeded.
  success,

  /// User dismissed the prompt without authenticating.
  cancelled,

  /// `local_auth` is unavailable on this device, or the host Activity isn't a
  /// FragmentActivity, or some other PlatformException was raised — caller
  /// should fall back to the PIN flow.
  unavailable,
}

/// Wraps the device biometric prompt + a 6-digit PIN fallback stored in
/// the OS keystore via flutter_secure_storage. The PrivacySettings JSONB
/// only stores a yes/no flag — the secret never leaves the device.
class AppLockController {
  static const _kPinKey = 'app_lock_pin_v1';

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _store = const FlutterSecureStorage();

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Run the biometric prompt and report a tri-state outcome so callers can
  /// distinguish "user cancelled" from "platform unavailable" (and fall back
  /// to PIN in the latter case).
  Future<AuthOutcome> authenticateBiometric({
    String reason = 'Unlock Lumio',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      return ok ? AuthOutcome.success : AuthOutcome.cancelled;
    } on PlatformException {
      // NotAvailable, NotEnrolled, PasscodeNotSet, LockedOut, etc. —
      // caller falls back to the PIN path.
      return AuthOutcome.unavailable;
    } catch (_) {
      return AuthOutcome.unavailable;
    }
  }

  Future<bool> hasPin() async => (await _store.read(key: _kPinKey)) != null;

  Future<void> setPin(String pin) async {
    if (pin.length < 4 || pin.length > 8) {
      throw ArgumentError('PIN must be 4–8 digits');
    }
    await _store.write(key: _kPinKey, value: pin);
  }

  Future<bool> verifyPin(String pin) async {
    final saved = await _store.read(key: _kPinKey);
    return saved != null && saved == pin;
  }

  Future<void> clearPin() async => _store.delete(key: _kPinKey);

  /// `local_auth` isn't supported on every platform — keep the screen
  /// graceful when used on desktop/web builds.
  bool get isLockSupported => Platform.isAndroid || Platform.isIOS;
}

final appLockControllerProvider = Provider<AppLockController>(
  (_) => AppLockController(),
);

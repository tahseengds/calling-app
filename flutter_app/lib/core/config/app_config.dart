// Build-time configuration.
//
// Both debug and release builds default to the LIVE production backend, so
// `flutter run` (incl. on a physical device) and `flutter build apk` hit
// https://lumin.tahseen.tech out of the box — no flags needed.
//
// To target a LOCAL backend instead, override explicitly, e.g. on the emulator:
//   flutter run \
//     --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
//     --dart-define=SIGNALING_URL=ws://10.0.2.2:8001
// (cleartext http:// to a local host also needs a debug network-security-config
// since targetSdk 34 blocks it by default.)

import 'package:flutter/foundation.dart' show kReleaseMode;

abstract final class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://lumin.tahseen.tech',
  );

  static const String signalingUrl = String.fromEnvironment(
    'SIGNALING_URL',
    defaultValue: 'wss://lumin.tahseen.tech',
  );

  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: kReleaseMode ? 'prod' : 'debug',
  );

  static bool get isProduction => appEnv == 'prod';
}

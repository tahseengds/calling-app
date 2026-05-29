// Build-time configuration.
//
// Defaults are chosen by build mode, so no flags are needed for the common
// cases:
//   • Release builds (`flutter build apk --release`, `--split-per-abi`, etc.)
//     default to the live production backend.
//   • Debug / profile builds (`flutter run`) default to the local emulator
//     host (10.0.2.2), so on-device dev hits a local backend out of the box.
//
// Any value can still be overridden explicitly, e.g.:
//   flutter run \
//     --dart-define=API_BASE_URL=https://staging.example.com \
//     --dart-define=SIGNALING_URL=wss://staging.example.com \
//     --dart-define=APP_ENV=prod

import 'package:flutter/foundation.dart' show kReleaseMode;

abstract final class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
        kReleaseMode ? 'https://lumin.tahseen.tech' : 'http://10.0.2.2:8000',
  );

  static const String signalingUrl = String.fromEnvironment(
    'SIGNALING_URL',
    defaultValue:
        kReleaseMode ? 'wss://lumin.tahseen.tech' : 'ws://10.0.2.2:8001',
  );

  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: kReleaseMode ? 'prod' : 'debug',
  );

  static bool get isProduction => appEnv == 'prod';

  // ── Public links shown in About screen ─────────────────────────────────
  static const String termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: 'https://lumin.tahseen.tech/terms',
  );

  static const String privacyUrl = String.fromEnvironment(
    'PRIVACY_URL',
    defaultValue: 'https://lumin.tahseen.tech/privacy',
  );
}

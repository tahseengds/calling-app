// Build-time configuration via --dart-define.
//
// Usage:
//   flutter run \
//     --dart-define=API_BASE_URL=https://lumin.example.com \
//     --dart-define=SIGNALING_URL=wss://lumin.example.com \
//     --dart-define=APP_ENV=prod
//
//   flutter build apk \
//     --dart-define=API_BASE_URL=https://lumin.example.com \
//     --dart-define=SIGNALING_URL=wss://lumin.example.com \
//     --dart-define=APP_ENV=prod

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
    defaultValue: 'debug',
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

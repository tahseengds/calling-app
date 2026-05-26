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
//
//   UI-only (no API): enabled by default. Disable when the backend is ready:
//     --dart-define=UI_ONLY=false

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

  /// When true, auth/contacts/profile use local mock data instead of the API.
  ///
  /// Off by default — production builds use the real backend.
  /// Enable for UI-preview / design-review builds only:
  ///   `--dart-define=UI_ONLY=true`
  static const bool uiOnly = bool.fromEnvironment('UI_ONLY');

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

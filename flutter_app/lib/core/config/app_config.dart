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
    defaultValue: 'https://lumin.example.com',
  );

  static const String signalingUrl = String.fromEnvironment(
    'SIGNALING_URL',
    defaultValue: 'wss://lumin.example.com',
  );

  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'debug',
  );

  static bool get isProduction => appEnv == 'prod';

  /// When true, auth/contacts/profile use local mock data instead of the API.
  ///
  /// On by default (including release APKs). Disable with:
  /// `--dart-define=UI_ONLY=false`
  static const bool uiOnly = bool.hasEnvironment('UI_ONLY')
      ? bool.fromEnvironment('UI_ONLY')
      : true;
}

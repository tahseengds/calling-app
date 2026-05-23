// Build-time configuration via --dart-define.
//
// Usage:
//   flutter run \
//     --dart-define=API_BASE_URL=https://family.example.com \
//     --dart-define=SIGNALING_URL=wss://family.example.com \
//     --dart-define=APP_ENV=prod
//
//   flutter build apk \
//     --dart-define=API_BASE_URL=https://family.example.com \
//     --dart-define=SIGNALING_URL=wss://family.example.com \
//     --dart-define=APP_ENV=prod

abstract final class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://family.example.com',
  );

  static const String signalingUrl = String.fromEnvironment(
    'SIGNALING_URL',
    defaultValue: 'wss://family.example.com',
  );

  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'debug',
  );

  static bool get isProduction => appEnv == 'prod';
}

import '../../../shared/models/user.dart';

/// Sealed auth state — the single source of truth for whether the user is
/// logged in. The GoRouter redirect reads this to decide where to route.
sealed class AuthState {
  const AuthState();
}

/// Initial state while we check secure storage for a saved refresh token.
/// The splash screen shows during this state.
final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// No valid session. Show login / register screens.
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Login or registration was accepted; waiting for the user to enter the OTP.
final class AuthOtpPending extends AuthState {
  final String phone;
  final bool isRegistering;

  /// Populated only when the backend runs in debug mode (DEBUG=true).
  /// Never log or display this in production.
  final String? debugOtp;

  const AuthOtpPending({
    required this.phone,
    this.isRegistering = false,
    this.debugOtp,
  });
}

/// OTP was verified; the user is fully authenticated.
final class AuthAuthenticated extends AuthState {
  final User me;
  const AuthAuthenticated({required this.me});
}

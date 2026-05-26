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

/// Firebase Phone Auth handed back a verificationId after sending the SMS
/// (or after an Android auto-retrieval-pending callback). The OTP screen
/// reads [phone] for display and uses [verificationId] when calling
/// `signInWithCredential`.
///
/// [resendToken] is the integer handle Firebase uses to resend the SMS
/// without consuming a fresh verification flow. Null on iOS / web.
final class AuthOtpPending extends AuthState {
  final String phone;
  final String verificationId;
  final int? resendToken;

  /// When true the user is going through the Firebase phone flow for the
  /// first time — the UI shows the "Welcome" header instead of "Sign in".
  final bool isRegistering;

  const AuthOtpPending({
    required this.phone,
    required this.verificationId,
    this.resendToken,
    this.isRegistering = false,
  });

  AuthOtpPending copyWith({
    String? verificationId,
    int? resendToken,
  }) =>
      AuthOtpPending(
        phone: phone,
        verificationId: verificationId ?? this.verificationId,
        resendToken: resendToken ?? this.resendToken,
        isRegistering: isRegistering,
      );
}

/// OTP was verified; the user is fully authenticated.
final class AuthAuthenticated extends AuthState {
  final User me;
  const AuthAuthenticated({required this.me});
}

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

/// The user just registered (or tried to sign in) with email/password but
/// hasn't clicked the verification link yet. The verify-pending screen
/// reads [email] for display and offers resend + "I've verified" buttons.
///
/// [isRegistering] flips the copy from "Verify to finish sign-in" to
/// "Verify to finish creating your account".
///
/// [name] is the display name the user typed on the register screen;
/// stashed here so we can pass it to the backend once verification
/// completes.
final class AuthEmailVerificationPending extends AuthState {
  final String email;
  final String? name;
  final bool isRegistering;

  const AuthEmailVerificationPending({
    required this.email,
    this.name,
    this.isRegistering = false,
  });
}

/// Fully authenticated.
final class AuthAuthenticated extends AuthState {
  final User me;
  const AuthAuthenticated({required this.me});
}

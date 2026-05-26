import 'dart:async';

// hide User so it doesn't collide with our own shared/models/user.dart.
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/auth/auth_token.dart';
import '../../../core/config/app_config.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/services/fcm_token_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/models/user.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

/// AuthNotifier drives the Firebase Phone Auth flow:
///
///   LoginScreen.startPhoneVerification(phone)
///     → FirebaseAuth.verifyPhoneNumber sends SMS + emits codeSent
///     → state = AuthOtpPending(verificationId, ...)
///   OtpScreen.verifySmsCode(code)
///     → FirebaseAuth.signInWithCredential
///     → firebaseUser.getIdToken()
///     → POST /api/auth/firebase-signin → our tokens
///     → state = AuthAuthenticated
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final SecureStorageService _secure;
  final Ref _ref;

  /// Optional FirebaseAuth override for tests. When null we resolve
  /// `FirebaseAuth.instance` lazily on first phone-verification call —
  /// crucial because the notifier is built during app start (and during
  /// unrelated unit tests like chat_notifier_test) before Firebase has
  /// been initialized.
  final FirebaseAuth? _firebaseOverride;
  FirebaseAuth get _firebase => _firebaseOverride ?? FirebaseAuth.instance;

  /// Latest pending name supplied by the user on register, kept on the
  /// notifier (not in state) because [AuthOtpPending] does not carry it —
  /// the SMS code-entry screen has no need to read it.
  String? _pendingName;

  AuthNotifier(
    this._repo,
    this._secure,
    this._ref, {
    FirebaseAuth? firebase,
  })  : _firebaseOverride = firebase,
        super(
          AppConfig.uiOnly
              ? AuthAuthenticated(me: MockData.currentUser)
              : const AuthUnknown(),
        ) {
    if (AppConfig.uiOnly) {
      Future.microtask(
        () => _ref.read(authTokenProvider.notifier).set('ui-only-token'),
      );
    } else {
      _tryRestoreSession();
    }
  }

  // ── Session restore ───────────────────────────────────────────────────────

  Future<void> _tryRestoreSession() async {
    final savedRefresh = await _secure.readRefreshToken();
    if (savedRefresh == null) {
      state = const AuthUnauthenticated();
      return;
    }
    try {
      final deviceId = await _secure.readDeviceId();
      final tokens = await _repo.refreshAccessToken(
        refreshToken: savedRefresh,
        deviceId: deviceId,
      );
      _ref.read(authTokenProvider.notifier).set(tokens.accessToken);
      await _secure.saveRefreshToken(tokens.refreshToken);
      final me = await _repo.getMe(tokens.accessToken);
      state = AuthAuthenticated(me: me);

      // Re-register the FCM token — it may have rotated while the app was
      // closed (or it might not have been registered at all if a previous
      // sign-in pre-dated the wiring). Fire-and-forget; never blocks the
      // user from reaching the home shell.
      final fcm = _ref.read(fcmTokenServiceProvider);
      unawaited(fcm.registerCurrentToken());
      fcm.startRotationListener();
    } catch (_) {
      await _secure.deleteRefreshToken();
      _ref.read(authTokenProvider.notifier).clear();
      state = const AuthUnauthenticated();
    }
  }

  // ── UI-only demo path (no backend) ────────────────────────────────────────

  Future<void> signInDemo() async {
    _ref.read(authTokenProvider.notifier).set('ui-only-token');
    state = AuthAuthenticated(me: MockData.currentUser);
  }

  // ── Phone verification (start) ────────────────────────────────────────────

  /// Kick off the Firebase Phone Auth flow.
  ///
  /// On Android, Firebase may auto-verify silently (no SMS shown to the
  /// user) — in that case we skip straight to a token exchange and
  /// transition directly to AuthAuthenticated.
  ///
  /// Throws [FirebaseAuthException] on verification failure so the calling
  /// screen can surface the error in a Snackbar.
  Future<void> startPhoneVerification({
    required String phone,
    bool isRegistering = false,
    String? name,
  }) async {
    if (AppConfig.uiOnly) {
      await signInDemo();
      return;
    }
    _pendingName = name;

    final completer = Completer<void>();

    await _firebase.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android auto-retrieval — we have a Firebase credential without
        // any user-entered SMS code. Sign in immediately.
        try {
          await _signInWithFirebaseCredential(credential, isRegistering: isRegistering);
          if (!completer.isCompleted) completer.complete();
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        state = AuthOtpPending(
          phone: phone,
          verificationId: verificationId,
          resendToken: resendToken,
          isRegistering: isRegistering,
        );
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // Auto-retrieval timed out — keep the manual-entry state if we're
        // already there, otherwise transition to it.
        final current = state;
        if (current is AuthOtpPending) {
          state = current.copyWith(verificationId: verificationId);
        } else {
          state = AuthOtpPending(
            phone: phone,
            verificationId: verificationId,
            isRegistering: isRegistering,
          );
        }
      },
    );

    // Wait for either codeSent or verificationCompleted/Failed before
    // returning so the caller can `await` the call.
    await completer.future;
  }

  // ── OTP verification ──────────────────────────────────────────────────────

  /// Confirm the SMS code the user typed. Throws on a wrong code so the
  /// OTP screen can shake the boxes.
  Future<void> verifyOtp({required String code}) async {
    if (AppConfig.uiOnly) {
      await signInDemo();
      return;
    }
    final pending = state;
    if (pending is! AuthOtpPending) {
      throw StateError('verifyOtp called outside AuthOtpPending');
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: pending.verificationId,
      smsCode: code,
    );
    await _signInWithFirebaseCredential(
      credential,
      isRegistering: pending.isRegistering,
    );
  }

  /// Shared finalizer used by both auto-retrieval and manual-entry paths.
  Future<void> _signInWithFirebaseCredential(
    PhoneAuthCredential credential, {
    required bool isRegistering,
  }) async {
    final userCred = await _firebase.signInWithCredential(credential);
    final idToken = await userCred.user?.getIdToken();
    if (idToken == null) {
      throw StateError('Firebase sign-in succeeded but no ID token');
    }

    final deviceId = await _secure.readDeviceId();

    // Grab the FCM token *before* sign-in so the backend can persist it in
    // the same transaction that creates / updates the user row. Without
    // this, killed-app push delivery (messages + incoming calls) silently
    // skips this device — the worker just logs "no FCM token, skipping".
    final fcmService = _ref.read(fcmTokenServiceProvider);
    final fcmToken = await fcmService.currentToken();

    final tokens = await _repo.firebaseSignIn(
      firebaseIdToken: idToken,
      deviceId: deviceId,
      fcmToken: fcmToken,
      name: isRegistering ? _pendingName : null,
    );

    _ref.read(authTokenProvider.notifier).set(tokens.accessToken);
    await _secure.saveRefreshToken(tokens.refreshToken);

    final me = await _repo.getMe(tokens.accessToken);
    state = AuthAuthenticated(me: me);

    // Install the rotation listener so any future FCM token refresh is
    // automatically re-uploaded.
    fcmService.startRotationListener();

    // We no longer need to keep the Firebase session around — our own
    // JWTs are the source of truth from here on.
    await _firebase.signOut();
    _pendingName = null;
  }

  /// Re-send the SMS code without restarting the entire flow. Returns
  /// silently if the current state isn't waiting for OTP.
  Future<void> resendOtp() async {
    final pending = state;
    if (pending is! AuthOtpPending) return;
    await startPhoneVerification(
      phone: pending.phone,
      isRegistering: pending.isRegistering,
      name: _pendingName,
    );
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    if (AppConfig.uiOnly) {
      _ref.read(authTokenProvider.notifier).clear();
      state = const AuthUnauthenticated();
      return;
    }
    final token = _ref.read(authTokenProvider);
    final refresh = await _secure.readRefreshToken();
    if (token != null && refresh != null) {
      try {
        await _repo.logout(accessToken: token, refreshToken: refresh);
      } catch (_) {
        // Always clear locally, even if server call fails.
      }
    }
    // Stop the FCM rotation listener — no point re-uploading tokens for an
    // anonymous user. (Note: the user's row on the server still has the
    // FCM token until they sign in elsewhere; that's a known limitation.)
    _ref.read(fcmTokenServiceProvider).stopRotationListener();
    _ref.read(authTokenProvider.notifier).clear();
    await _secure.deleteRefreshToken();
    state = const AuthUnauthenticated();
  }

  /// Called by the Dio interceptor when a token refresh fails mid-flight.
  /// Does NOT await async cleanup — it's fire-and-forget by design.
  void forceSignOut() {
    if (AppConfig.uiOnly) return;
    _ref.read(authTokenProvider.notifier).clear();
    state = const AuthUnauthenticated();
    _secure.deleteRefreshToken();
  }

  // ── Profile sync ──────────────────────────────────────────────────────────

  /// Updates the cached User inside the Authenticated state, e.g. after name
  /// or avatar changes from ProfileScreen.
  void updateCachedUser(User user) {
    final current = state;
    if (current is AuthAuthenticated) {
      state = AuthAuthenticated(me: user);
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(secureStorageProvider),
    ref,
  );
});

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
// hide User so it doesn't collide with our own shared/models/user.dart.
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/auth/auth_token.dart';
import '../../../core/config/app_config.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/services/fcm_token_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/models/user.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

/// AuthNotifier drives two Firebase Auth flows:
///
/// Google Sign-In:
///   signInWithGoogle()
///     → GoogleSignIn picker → GoogleAuthProvider credential
///     → FirebaseAuth.signInWithCredential
///     → backend /api/auth/firebase-signin
///     → AuthAuthenticated
///
/// Email/Password:
///   registerWithEmail(email, password, name)
///     → createUserWithEmailAndPassword
///     → sendEmailVerification (Firebase ships a verification link)
///     → AuthEmailVerificationPending
///     [user clicks link in their inbox]
///     → reloadAndCompleteVerification()
///     → backend /api/auth/firebase-signin → AuthAuthenticated
///
///   signInWithEmail(email, password)
///     → signInWithEmailAndPassword
///     → if !user.emailVerified: resend link, → AuthEmailVerificationPending
///     → else: backend /api/auth/firebase-signin → AuthAuthenticated
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final SecureStorageService _secure;
  final Ref _ref;

  /// Optional FirebaseAuth override for tests. When null we resolve
  /// `FirebaseAuth.instance` lazily — crucial because the notifier is
  /// built during app start (and during unit tests like
  /// chat_notifier_test) before Firebase has been initialized.
  final FirebaseAuth? _firebaseOverride;
  FirebaseAuth get _firebase => _firebaseOverride ?? FirebaseAuth.instance;

  /// Google sign-in client. Lazy for the same Firebase-init reason as above.
  GoogleSignIn? _googleOverride;
  GoogleSignIn get _google =>
      _googleOverride ??= GoogleSignIn(scopes: const ['email']);

  /// Set while [_tryRestoreSession] is doing a `POST /api/auth/refresh`.
  /// Exposed so the Dio interceptor can await this instead of firing its
  /// own parallel refresh during cold start — two refreshes with the
  /// same refresh-token trip the backend's reuse-detection guard and
  /// revoke every session for the user.
  Future<bool>? _refreshInFlight;
  Future<bool>? get refreshInFlight => _refreshInFlight;

  AuthNotifier(
    this._repo,
    this._secure,
    this._ref, {
    FirebaseAuth? firebase,
    GoogleSignIn? google,
  })  : _firebaseOverride = firebase,
        _googleOverride = google,
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

  /// Cold-start session restore.
  ///
  /// Goals (in priority order):
  ///   1. If the user was authenticated and we have a cached profile, render
  ///      the home screen *immediately* — even if the network is down. Deep
  ///      links (FCM message tap) need a valid auth state to route properly,
  ///      and bouncing a logged-in user to /login because the refresh call
  ///      hadn't resolved yet was the original security flaw.
  ///   2. Refresh the access token in the background. On success, swap to the
  ///      fresh tokens. On a 401/403 (token actually invalid), sign out. On a
  ///      network/timeout error, keep the cached session — the refresh will
  ///      retry on next API call via the Dio interceptor.
  Future<void> _tryRestoreSession() async {
    final savedRefresh = await _secure.readRefreshToken();
    if (savedRefresh == null) {
      debugPrint(
          '[auth] restore: no refresh token in secure storage → /login. '
          'Expected on first launch / after sign-out / if secure storage '
          'was cleared by the OS (uninstall, factory-reset).');
      state = const AuthUnauthenticated();
      return;
    }

    // Optimistic restore from cached user — keeps the user logged in on cold
    // start, including when launched from an FCM notification while offline.
    final cachedJson = await _secure.readCachedUser();
    User? cachedUser;
    if (cachedJson != null) {
      try {
        cachedUser = User.fromJson(cachedJson);
        state = AuthAuthenticated(me: cachedUser);
        debugPrint('[auth] restore: showing cached user ${cachedUser.id} '
            'while refresh runs in background');
      } catch (e) {
        debugPrint('[auth] restore: cached user JSON failed to parse — '
            'wiping and falling through to network restore. error=$e');
        await _secure.deleteCachedUser();
      }
    } else {
      debugPrint(
          '[auth] restore: have refresh token but no cached user; '
          'showing splash until network restore completes');
    }

    // Publish the in-flight refresh BEFORE doing any HTTP work so the Dio
    // interceptor (which may fire on a parallel screen mount) can await
    // this instead of POSTing /api/auth/refresh with the same token.
    final refreshDone = Completer<bool>();
    _refreshInFlight = refreshDone.future;
    try {
      final deviceId = await _secure.readDeviceId();
      final tokens = await _repo.refreshAccessToken(
        refreshToken: savedRefresh,
        deviceId: deviceId,
      );
      _ref.read(authTokenProvider.notifier).set(tokens.accessToken);
      await _secure.saveRefreshToken(tokens.refreshToken);
      final me = await _repo.getMe(tokens.accessToken);
      await _secure.saveCachedUserJson(jsonEncode(me.toJson()));
      state = AuthAuthenticated(me: me);
      debugPrint('[auth] restore: refreshed + getMe ok → AuthAuthenticated');
      refreshDone.complete(true);

      final fcm = _ref.read(fcmTokenServiceProvider);
      unawaited(fcm.registerCurrentToken());
      fcm.startRotationListener();
    } catch (e) {
      // Distinguish "server says the refresh token is dead" from "we couldn't
      // reach the server". Only the former should sign the user out.
      if (_isAuthRejection(e)) {
        debugPrint('[auth] restore: refresh REJECTED by server '
            '(token revoked/expired) → /login. error=$e');
        await _secure.deleteRefreshToken();
        await _secure.deleteCachedUser();
        _ref.read(authTokenProvider.notifier).clear();
        state = const AuthUnauthenticated();
        refreshDone.complete(false);
        return;
      }

      // Transient — leave refresh + cached user in place so the next launch
      // (or the Dio interceptor on the next request) can retry.
      if (cachedUser == null) {
        // No cache to fall back on; this device truly has no usable session.
        debugPrint('[auth] restore: refresh network error AND no cached '
            'user → /login. error=$e');
        state = const AuthUnauthenticated();
      } else {
        debugPrint('[auth] restore: refresh network error but keeping '
            'cached AuthAuthenticated — will retry on next API call. '
            'error=$e');
      }
      refreshDone.complete(false);
    } finally {
      _refreshInFlight = null;
    }
  }

  /// Returns true when the error indicates the refresh token itself was
  /// rejected by the server (vs. a transport / connectivity problem).
  static bool _isAuthRejection(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      return code == 401 || code == 403;
    }
    return false;
  }

  // ── UI-only demo path (no backend) ────────────────────────────────────────

  Future<void> signInDemo() async {
    _ref.read(authTokenProvider.notifier).set('ui-only-token');
    state = AuthAuthenticated(me: MockData.currentUser);
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  /// Run the native Google account picker, exchange the result for a
  /// Firebase credential, and complete the backend handshake.
  ///
  /// Throws [FirebaseAuthException] on Firebase-side failures and a plain
  /// [Exception] with a friendly message on Google-side failures (cancel,
  /// no network, etc.).
  Future<void> signInWithGoogle() async {
    if (AppConfig.uiOnly) {
      await signInDemo();
      return;
    }

    final GoogleSignInAccount? account = await _google.signIn();
    if (account == null) {
      // User cancelled — drop back to the login screen silently.
      return;
    }

    final auth = await account.authentication;
    if (auth.idToken == null && auth.accessToken == null) {
      throw Exception('Google sign-in did not return any tokens.');
    }

    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    );

    final userCred = await _firebase.signInWithCredential(credential);
    await _completeBackendSignIn(
      firebaseUser: userCred.user!,
      // First-time Google sign-ups can lift the name from the Google
      // profile so the welcome screen has something to show.
      nameForFirstSignIn: account.displayName,
    );
  }

  // ── Email / Password ─────────────────────────────────────────────────────

  /// Create a new Firebase account with email+password, send the
  /// verification link, and park in [AuthEmailVerificationPending].
  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    if (AppConfig.uiOnly) {
      await signInDemo();
      return;
    }
    final normalized = email.trim().toLowerCase();
    final userCred = await _firebase.createUserWithEmailAndPassword(
      email: normalized,
      password: password,
    );
    // Update the Firebase displayName so the ID token carries 'name' as a
    // claim — handy for the backend's first-user-creation fallback.
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) {
      await userCred.user?.updateDisplayName(trimmedName);
    }
    await userCred.user?.sendEmailVerification(_verifyEmailActionCodeSettings);

    state = AuthEmailVerificationPending(
      email: normalized,
      name: trimmedName.isEmpty ? null : trimmedName,
      isRegistering: true,
    );
  }

  /// Sign in to an existing email/password account. If the email is not
  /// yet verified we re-send the verification link and park in
  /// [AuthEmailVerificationPending].
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (AppConfig.uiOnly) {
      await signInDemo();
      return;
    }
    final normalized = email.trim().toLowerCase();
    final userCred = await _firebase.signInWithEmailAndPassword(
      email: normalized,
      password: password,
    );
    final fbUser = userCred.user;
    if (fbUser == null) {
      throw StateError('Firebase sign-in returned no user');
    }
    if (!fbUser.emailVerified) {
      // Re-send the link so the user has a fresh one in their inbox.
      try {
        await fbUser.sendEmailVerification(_verifyEmailActionCodeSettings);
      } catch (_) {
        // Best-effort — the UI still shows resend.
      }
      state = AuthEmailVerificationPending(
        email: normalized,
        isRegistering: false,
      );
      return;
    }

    await _completeBackendSignIn(firebaseUser: fbUser);
  }

  /// Re-send the verification link from the pending-verification screen.
  Future<void> resendVerificationEmail() async {
    final user = _firebase.currentUser;
    if (user == null) {
      throw StateError('Cannot resend — no Firebase user signed in');
    }
    await user.sendEmailVerification(_verifyEmailActionCodeSettings);
  }

  // ── Deep-link verification ────────────────────────────────────────────────

  /// Tap-of-the-email-link entry point.
  ///
  /// Called by the app-wide `app_links` listener when the system delivers a
  /// URI matching our intent filter. We extract the `oobCode` from the URI,
  /// apply it server-side, then reload the Firebase user and complete the
  /// backend handshake. Returns true if we transitioned to
  /// [AuthAuthenticated].
  ///
  /// Safe to call with any URI — non-verification links return false silently.
  Future<bool> handleVerificationDeepLink(Uri uri) async {
    if (AppConfig.uiOnly) return false;

    final mode = uri.queryParameters['mode'];
    final oobCode = uri.queryParameters['oobCode'];
    final looksLikeVerify =
        (mode == 'verifyEmail' || _pathLooksLikeVerify(uri)) &&
            (oobCode != null && oobCode.isNotEmpty);
    if (!looksLikeVerify) return false;

    // applyActionCode is the canonical way to consume an oobCode. The Firebase
    // web action handler does this server-side when the user opens the link in
    // a browser; doing it explicitly in the app guarantees verification even
    // when the system hands us the URL directly (App Link / custom scheme)
    // before the web page runs.
    try {
      await _firebase.applyActionCode(oobCode);
    } on FirebaseAuthException catch (e) {
      // Common codes: expired-action-code, invalid-action-code,
      // user-disabled, user-not-found.
      if (e.code != 'invalid-action-code') {
        // Even an "invalid" code can mean it was already consumed (e.g. the
        // browser handled it). Fall through and try a reload before giving up.
        return false;
      }
    } catch (_) {
      return false;
    }

    return reloadAndCompleteVerification();
  }

  bool _pathLooksLikeVerify(Uri uri) {
    final p = uri.path.toLowerCase();
    if (p.endsWith('/auth/verify-email') || p.endsWith('/verify-email')) {
      return true;
    }
    // lumin://verify-email — the host carries the path on custom-scheme URIs.
    return uri.host.toLowerCase() == 'verify-email';
  }

  // ── ActionCodeSettings ────────────────────────────────────────────────────
  //
  // The email-verification link routes through Firebase's web action handler
  // (`<project>.firebaseapp.com/__/auth/action`), which redirects to our
  // `url`. The redirect lands on a URL Android/iOS associate with this app via
  // the intent filters in AndroidManifest.xml and the CFBundleURLTypes in
  // Info.plist, so tapping the email foregrounds Lumio.
  //
  // `handleCodeInApp: true` ensures the `oobCode` is passed through to the
  // continue URL rather than consumed by Firebase's web handler — we apply it
  // ourselves via [handleVerificationDeepLink] so verification is
  // deterministic regardless of the user's default browser.

  static const _kVerifyEmailUrl =
      'https://lumin.tahseen.tech/auth/verify-email';
  static const _kAndroidPackageName = 'com.lumin.app';
  static const _kIosBundleId = 'com.lumin.app';

  ActionCodeSettings get _verifyEmailActionCodeSettings => ActionCodeSettings(
        url: _kVerifyEmailUrl,
        handleCodeInApp: true,
        androidPackageName: _kAndroidPackageName,
        androidInstallApp: true,
        androidMinimumVersion: '24',
        iOSBundleId: _kIosBundleId,
      );

  /// Called by the "I've verified my email" button on the pending screen.
  /// Reloads the Firebase user; if the verification flag has flipped, we
  /// trade the ID token for our own JWTs. Returns true if the user is
  /// now authenticated.
  Future<bool> reloadAndCompleteVerification() async {
    final pending = state;
    if (pending is! AuthEmailVerificationPending) {
      // Not in the pending state — nothing to do.
      return state is AuthAuthenticated;
    }
    final user = _firebase.currentUser;
    if (user == null) {
      // Lost the Firebase session somehow — bounce back to login.
      state = const AuthUnauthenticated();
      return false;
    }
    await user.reload();
    final refreshed = _firebase.currentUser;
    if (refreshed == null || !refreshed.emailVerified) {
      return false;
    }
    await _completeBackendSignIn(
      firebaseUser: refreshed,
      nameForFirstSignIn: pending.name,
    );
    return true;
  }

  // ── Backend handshake (shared) ────────────────────────────────────────────

  Future<void> _completeBackendSignIn({
    required dynamic firebaseUser,
    String? nameForFirstSignIn,
  }) async {
    // firebaseUser is dynamic only to dodge the import-name clash; in
    // practice it's a firebase_auth User. force a fresh ID token so the
    // backend's tight replay window doesn't reject a cached one.
    final idToken = await firebaseUser.getIdToken(true);
    if (idToken == null) {
      throw StateError('Firebase sign-in succeeded but no ID token');
    }

    final deviceId = await _secure.readDeviceId();

    // Grab the FCM token *before* the handshake so the backend can persist
    // it in the same transaction that creates / updates the user row.
    final fcmService = _ref.read(fcmTokenServiceProvider);
    final fcmToken = await fcmService.currentToken();

    final tokens = await _repo.firebaseSignIn(
      firebaseIdToken: idToken,
      deviceId: deviceId,
      fcmToken: fcmToken,
      name: nameForFirstSignIn,
    );

    _ref.read(authTokenProvider.notifier).set(tokens.accessToken);
    await _secure.saveRefreshToken(tokens.refreshToken);

    final me = await _repo.getMe(tokens.accessToken);
    await _secure.saveCachedUserJson(jsonEncode(me.toJson()));
    state = AuthAuthenticated(me: me);

    fcmService.startRotationListener();

    // We no longer need to keep the Firebase session around — our own
    // JWTs are the source of truth. Fire-and-forget.
    unawaited(_firebase.signOut().catchError((_) {}));
    unawaited(_google.signOut().catchError((_) => null));
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
    _ref.read(fcmTokenServiceProvider).stopRotationListener();
    _ref.read(authTokenProvider.notifier).clear();
    await _secure.deleteRefreshToken();
    await _secure.deleteCachedUser();
    // Best-effort: also drop the Google cached account so the next
    // sign-in shows the picker.
    try {
      await _google.signOut();
    } catch (_) {}
    state = const AuthUnauthenticated();
  }

  /// Called by the Dio interceptor when a token refresh fails mid-flight.
  /// Does NOT await async cleanup — it's fire-and-forget by design.
  void forceSignOut() {
    if (AppConfig.uiOnly) return;
    _ref.read(authTokenProvider.notifier).clear();
    state = const AuthUnauthenticated();
    _secure.deleteRefreshToken();
    _secure.deleteCachedUser();
  }

  // ── Profile sync ──────────────────────────────────────────────────────────

  /// Updates the cached User inside the Authenticated state, e.g. after name
  /// or avatar changes from ProfileScreen. Persists to disk so the next cold
  /// start sees the fresh profile without waiting for the network.
  void updateCachedUser(User user) {
    final current = state;
    if (current is AuthAuthenticated) {
      state = AuthAuthenticated(me: user);
      unawaited(_secure.saveCachedUserJson(jsonEncode(user.toJson())));
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

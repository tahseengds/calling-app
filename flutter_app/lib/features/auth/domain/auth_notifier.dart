import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/auth/auth_token.dart';
import '../../../core/config/app_config.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/models/user.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final SecureStorageService _secure;
  final Ref _ref;

  AuthNotifier(this._repo, this._secure, this._ref)
      : super(
          AppConfig.uiOnly
              ? AuthAuthenticated(me: MockData.currentUser)
              : const AuthUnknown(),
        ) {
    if (AppConfig.uiOnly) {
      // Defer — Riverpod forbids modifying another provider during init.
      Future.microtask(
        () => _ref.read(authTokenProvider.notifier).set('ui-only-token'),
      );
    } else {
      _tryRestoreSession();
    }
  }

  // ── Session restore ───────────────────────────────────────────────────────

  Future<void> _tryRestoreSession() async {
    if (AppConfig.uiOnly) {
      _ref.read(authTokenProvider.notifier).set('ui-only-token');
      state = AuthAuthenticated(me: MockData.currentUser);
      return;
    }

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
    } catch (_) {
      await _secure.deleteRefreshToken();
      _ref.read(authTokenProvider.notifier).clear();
      state = const AuthUnauthenticated();
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  /// Validates credentials and requests an OTP. Throws on failure so the
  /// screen can display a Snackbar without changing global auth state.
  /// Skips login/API and opens the main shell (UI-only mode).
  Future<void> signInDemo() async {
    _ref.read(authTokenProvider.notifier).set('ui-only-token');
    state = AuthAuthenticated(me: MockData.currentUser);
  }

  Future<void> requestLoginOtp({
    required String phone,
    required String password,
  }) async {
    if (AppConfig.uiOnly) {
      await signInDemo();
      return;
    }
    final result = await _repo.requestLoginOtp(
      phone: phone,
      password: password,
    );
    state = AuthOtpPending(phone: result.phone, debugOtp: result.debugOtp);
  }

  // ── Register ──────────────────────────────────────────────────────────────

  Future<void> register({
    required String name,
    required String phone,
    required String password,
  }) async {
    if (AppConfig.uiOnly) {
      _ref.read(authTokenProvider.notifier).set('ui-only-token');
      state = AuthAuthenticated(
        me: User(
          id: MockData.currentUser.id,
          name: name,
          phone: phone,
          lastSeen: DateTime.now(),
          presence: PresenceStatus.online,
        ),
      );
      return;
    }
    final result = await _repo.register(
      name: name,
      phone: phone,
      password: password,
    );
    state = AuthOtpPending(
      phone: result.phone,
      isRegistering: true,
      debugOtp: result.debugOtp,
    );
  }

  // ── OTP verification ──────────────────────────────────────────────────────

  /// Throws on wrong code so the OTP screen can shake the boxes.
  Future<void> verifyOtp({required String code}) async {
    if (AppConfig.uiOnly) {
      await signInDemo();
      return;
    }
    final pending = state as AuthOtpPending;
    final deviceId = await _secure.readDeviceId();
    final result = await _repo.verifyOtp(
      phone: pending.phone,
      code: code,
      deviceId: deviceId,
    );
    _ref.read(authTokenProvider.notifier).set(result.accessToken);
    await _secure.saveRefreshToken(result.refreshToken);
    state = AuthAuthenticated(me: result.me);
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    if (AppConfig.uiOnly) {
      _ref.read(authTokenProvider.notifier).clear();
      state = const AuthUnauthenticated();
      return;
    }
    final token = _ref.read(authTokenProvider);
    if (token != null) {
      try {
        final deviceId = await _secure.readDeviceId();
        await _repo.logout(accessToken: token, deviceId: deviceId);
      } catch (_) {
        // Always clear locally, even if server call fails.
      }
    }
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
    // Delete the stale refresh token in the background.
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

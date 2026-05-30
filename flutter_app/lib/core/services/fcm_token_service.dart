// FCM token registration (prompt-15 follow-up).
//
// Backend infrastructure for killed-app push delivery is fully built:
//   • Node.js signaling enqueues `incoming_call` / `missed_call` FCM jobs
//   • FastAPI message_service enqueues `new_message` FCM jobs
//   • A Python worker consumes the queue and pushes via FCM HTTP v1
//   • Android FcmService (prompt 15) wakes the device on receipt
//
// All of that is dead weight unless the server knows each user's FCM token.
// This service plumbs that single missing link: get the token from
// FirebaseMessaging and ship it to /api/users/fcm-token.
//
// Three trigger points (every sign-in path is covered):
//   1. First sign-in:        token is passed inline in the firebase-signin
//                            body (backend stores it during user upsert).
//   2. Session restore:      token re-uploaded via POST /api/users/fcm-token
//                            in case Firebase rotated it while the app was
//                            closed.
//   3. Live token rotation:  onTokenRefresh listener re-uploads.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/dio_client.dart';
import '../storage/secure_storage.dart';

class FcmTokenService {
  FcmTokenService(this._ref);

  final Ref _ref;

  FirebaseMessaging get _firebaseMessaging => FirebaseMessaging.instance;

  /// Returns the device's current FCM token (or null if Firebase couldn't
  /// resolve one — happens on emulators without Play Services, behind some
  /// VPNs, etc.). Safe to call anytime.
  Future<String?> currentToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      debugPrint('[fcm] getToken failed: $e');
      return null;
    }
  }

  /// Upload the current token to the backend via POST /api/users/fcm-token.
  /// Caller must already be authenticated — uses the shared Dio (which
  /// attaches the Bearer header via TokenInterceptor).
  ///
  /// Returns true on 204, false otherwise. Errors are swallowed so token
  /// registration never blocks the sign-in flow.
  ///
  /// Retries transient failures (no response / 5xx) with exponential backoff so
  /// a momentary network blip at startup doesn't leave the user silently
  /// unable to receive pushes. Client errors (4xx — e.g. an expired session)
  /// are not retried since a retry can't fix them. The success path makes a
  /// single request with no added latency.
  Future<bool> registerCurrentToken({int maxAttempts = 3}) async {
    final token = await currentToken();
    if (token == null || token.isEmpty) return false;

    final deviceId = await _ref.read(secureStorageProvider).readDeviceId();
    final dio = _ref.read(dioProvider);
    var delay = const Duration(seconds: 1);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await dio.post<void>(
          '/api/users/fcm-token',
          data: {'fcm_token': token, 'device_id': deviceId},
        );
        return resp.statusCode == 204;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final transient = status == null || status >= 500;
        debugPrint(
            '[fcm] register attempt $attempt/$maxAttempts failed: ${e.message}');
        if (!transient || attempt == maxAttempts) return false;
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
    return false;
  }

  /// Wire up the onTokenRefresh listener. Idempotent — calling more than
  /// once cancels the previous subscription. Call this once after the user
  /// is authenticated; cancel on sign-out via [stopRotationListener].
  void startRotationListener() {
    stopRotationListener();
    _rotationSub = _firebaseMessaging.onTokenRefresh.listen((token) async {
      debugPrint('[fcm] token rotated — re-registering');
      await registerCurrentToken();
    });
  }

  void stopRotationListener() {
    _rotationSub?.cancel();
    _rotationSub = null;
  }

  /// Active subscription to FirebaseMessaging.onTokenRefresh. Null when no
  /// listener is installed.
  // ignore: cancel_subscriptions
  StreamSubscription<String>? _rotationSub;
}

final fcmTokenServiceProvider = Provider<FcmTokenService>((ref) {
  final svc = FcmTokenService(ref);
  ref.onDispose(svc.stopRotationListener);
  return svc;
});

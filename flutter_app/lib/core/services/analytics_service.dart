import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin wrapper over Firebase Analytics (usage events / screen views) and
/// Crashlytics (crashes + non-fatal "issues"). Every call is guarded so a
/// missing/uninitialised Firebase never takes the app down.
class AnalyticsService {
  FirebaseAnalytics get analytics => FirebaseAnalytics.instance;
  FirebaseCrashlytics get crashlytics => FirebaseCrashlytics.instance;

  /// Drop into GoRouter `observers` for automatic screen_view tracking.
  FirebaseAnalyticsObserver get navigatorObserver =>
      FirebaseAnalyticsObserver(analytics: analytics);

  Future<void> logEvent(String name, [Map<String, Object>? params]) async {
    try {
      await analytics.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('[analytics] logEvent($name) failed: $e');
    }
  }

  Future<void> logScreen(String name) async {
    try {
      await analytics.logScreenView(screenName: name);
    } catch (_) {/* best effort */}
  }

  // ── Curated product events ─────────────────────────────────────────────────
  // Centralised, consistently-named events for key user actions so product
  // analytics stays queryable instead of a grab-bag of ad-hoc strings. Each is
  // a thin alias over [logEvent] (already crash-guarded).

  Future<void> accountDeleted() => logEvent('account_deleted');

  Future<void> passwordResetRequested() =>
      logEvent('password_reset_requested');

  Future<void> callStarted({
    required String callType,
    required String direction,
  }) =>
      logEvent('call_started', {
        'call_type': callType,
        'direction': direction,
      });

  Future<void> callEnded({
    required String callType,
    required String direction,
    required String reason,
    required bool connected,
    required String durationBucket,
  }) =>
      logEvent('call_ended', {
        'call_type': callType,
        'direction': direction,
        'end_reason': reason,
        // Firebase event params accept only String/num — send the flag as text.
        'connected': connected.toString(),
        'duration_bucket': durationBucket,
      });

  Future<void> supportRequestSubmitted(String category) =>
      logEvent('support_request_submitted', {'category': category});

  /// Associate events + crashes with a user (call on sign-in / clear on logout).
  Future<void> setUser(String? id) async {
    try {
      await analytics.setUserId(id: id);
      await crashlytics.setUserIdentifier(id ?? '');
    } catch (_) {/* best effort */}
  }

  /// Record a non-fatal issue (a caught exception, a failed network call…) so
  /// it shows up in Crashlytics with a reason and stack.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    try {
      await crashlytics.recordError(error, stack, reason: reason, fatal: fatal);
    } catch (e) {
      debugPrint('[analytics] recordError failed: $e');
    }
  }

  /// Breadcrumb shown alongside the next crash.
  void log(String message) {
    try {
      crashlytics.log(message);
    } catch (_) {/* best effort */}
  }
}

final analyticsServiceProvider = Provider<AnalyticsService>(
  (_) => AnalyticsService(),
);

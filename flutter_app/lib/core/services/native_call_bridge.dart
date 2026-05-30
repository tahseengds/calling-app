// Native call bridge (prompt 15).
//
// Wraps the `familylink/calls` MethodChannel that connects Flutter to the
// Android-native call layer (CallService, CallActionReceiver, FcmService).
//
// Responsibilities:
//   1. Pull the initial call payload at app startup (set by CallService's
//      full-screen-intent launch of MainActivity, or by CallActionReceiver
//      tapping Accept/Decline when the engine was dead).
//   2. Receive runtime events from native (incomingCall, callAction) and
//      republish them as a Dart stream so CallNotifier can subscribe.
//   3. Provide methods to tell native to stop the ringtone / foreground
//      service once Flutter has taken over the call.
//
// The bridge intentionally has zero knowledge of WebRTC or signaling — it's
// a pure transport layer. CallNotifier interprets the payloads.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Event types ──────────────────────────────────────────────────────────────

/// What native is reporting to Flutter.
enum NativeCallEventKind {
  /// FCM woke the device and CallService is now ringing. Payload carries the
  /// full call data (call_id, caller_*, sdp_offer, signal_token, etc.).
  incoming,

  /// User tapped Accept on the native notification (or via cold-start launch).
  accept,

  /// User tapped Decline on the native notification (or via cold-start launch).
  decline,

  /// FIX 7: User tapped Hang Up on the persistent in-call notification while
  /// the app was backgrounded. Payload carries only call_id + native_action.
  hangup,
}

class NativeCallEvent {
  final NativeCallEventKind kind;
  final Map<String, dynamic> payload;
  const NativeCallEvent({required this.kind, required this.payload});

  /// The call_id this event refers to, if present.
  String? get callId => payload['call_id'] as String?;

  @override
  String toString() => 'NativeCallEvent($kind, call_id=$callId)';
}

// ── Bridge ──────────────────────────────────────────────────────────────────

/// Thin wrapper around the `familylink/calls` MethodChannel.
class NativeCallBridge {
  NativeCallBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'familylink/calls';

  final MethodChannel _channel;
  final StreamController<NativeCallEvent> _events =
      StreamController<NativeCallEvent>.broadcast();
  bool _handlerInstalled = false;

  /// Whether the app is currently in Android Picture-in-Picture mode. The call
  /// screens watch this to collapse to a video-only layout while in PiP.
  final ValueNotifier<bool> isInPip = ValueNotifier<bool>(false);

  /// Called when the user taps a message notification (warm start) — the arg
  /// is the conversation_id to route to. Set by main.dart.
  void Function(String conversationId)? onOpenConversation;

  /// Called when the user taps a notification carrying a generic route (warm
  /// start) — e.g. a missed-call notification → "/call/history". Set by main.dart.
  void Function(String route)? onOpenRoute;

  /// Stream of events pushed by the native side.
  Stream<NativeCallEvent> get events => _events.stream;

  /// Install the MethodCallHandler. Safe to call more than once.
  void installHandler() {
    if (_handlerInstalled) {
      return;
    }
    _handlerInstalled = true;
    _channel.setMethodCallHandler(_onNativeCall);
  }

  /// Query the native side for any pending incoming call payload (set by the
  /// notification full-screen intent or by a cold-start accept/decline tap).
  ///
  /// Returns `null` if there's no pending call.
  ///
  /// The returned map's `native_action` field is `'accept' | 'decline' | null`.
  Future<NativeCallEvent?> getInitialCallData() async {
    if (kIsWeb) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>('getInitialCallData');
      return parseInitialCallData(raw);
    } on MissingPluginException {
      // Channel not wired (e.g. unit tests without a host implementation).
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Tell the native side the user has accepted; CallService will stop ringing.
  Future<void> acceptCall(String callId) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('acceptCall', {'call_id': callId});
    } on PlatformException {
      /* swallow — best-effort */
    } on MissingPluginException {
      /* tests */
    }
  }

  /// Tell the native side the user has declined; CallService will stop.
  Future<void> declineCall(String callId) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('declineCall', {'call_id': callId});
    } on PlatformException {
      /* swallow */
    } on MissingPluginException {
      /* tests */
    }
  }

  /// Tell the native side the call ended (hangup from the in-call UI).
  Future<void> endCall(String callId) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('endCall', {'call_id': callId});
    } on PlatformException {
      /* swallow */
    } on MissingPluginException {
      /* tests */
    }
  }

  /// Tell native to tear down the foreground service unconditionally.
  Future<void> stopCallService() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('stopCallService');
    } on PlatformException {
      /* swallow */
    } on MissingPluginException {
      /* tests */
    }
  }

  /// Spin up the native CallService for an incoming call that arrived over
  /// the socket (not FCM). Used by [CallNotifier.handleIncomingCall] when
  /// the app is backgrounded — without this, a backgrounded callee with a
  /// live socket sees nothing (Flutter can't show UI while not in the
  /// foreground), and FCM may take 10–30 s under battery optimization.
  ///
  /// [payload] must include `call_id`. Other keys (`caller_id`, `caller_name`,
  /// `caller_avatar`, `call_type`, `sdp_offer`, `signal_token`) are forwarded
  /// to CallService as intent extras so the full-screen activity and the
  /// notification can populate themselves.
  ///
  /// Idempotent on the native side — calling this for a callId that's
  /// already ringing (e.g. because FCM also arrived) is a no-op.
  Future<void> startIncomingCallService(Map<String, String?> payload) async {
    if (kIsWeb) return;
    if ((payload['call_id'] ?? '').isEmpty) return;
    try {
      await _channel.invokeMethod<void>('startIncomingCallService', payload);
    } on PlatformException catch (e) {
      debugPrint('[native_call_bridge] startIncomingCallService failed: $e');
    } on MissingPluginException {
      /* tests */
    }
  }

  /// Route hardware volume buttons to the in-call (voice-call) stream while
  /// `enabled` is true. Without this, pressing volume during an active call
  /// changes media volume — the wrong stream entirely. Call with `false` at
  /// call end to restore default (media) routing.
  Future<void> setVoiceCallVolumeStream(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>(
        'setVoiceCallVolumeStream',
        {'enabled': enabled},
      );
    } on PlatformException catch (e) {
      debugPrint('[native_call_bridge] setVoiceCallVolumeStream failed: $e');
    } on MissingPluginException {
      /* tests */
    }
  }

  /// Acquire a PROXIMITY_SCREEN_OFF_WAKE_LOCK so the screen blanks when the
  /// user puts the phone to their ear. Only enable during VOICE calls (not
  /// video — the user needs to see the screen). Idempotent on the native
  /// side; safe to call with the same value repeatedly.
  Future<void> setProximityAware(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>(
        'setProximityAware',
        {'enabled': enabled},
      );
    } on PlatformException catch (e) {
      debugPrint('[native_call_bridge] setProximityAware failed: $e');
    } on MissingPluginException {
      /* tests */
    }
  }

  /// FIX 7: Start the active-call foreground service when the call
  /// transitions to connected. Keeps the process priority high enough that
  /// Android doesn't kill it while the user is in another app or on the
  /// lock screen. Shows a persistent low-importance notification with a
  /// hang-up action. Idempotent — calling again for the same call_id is
  /// a no-op on the native side.
  Future<void> startActiveCallService({
    required String callId,
    required String peerName,
    required String callType,
  }) async {
    if (kIsWeb) return;
    if (callId.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('startActiveCallService', {
        'call_id': callId,
        'peer_name': peerName,
        'call_type': callType,
      });
    } on PlatformException catch (e) {
      debugPrint('[native_call_bridge] startActiveCallService failed: $e');
    } on MissingPluginException {
      /* tests */
    }
  }

  /// FIX 7: Stop the active-call foreground service. Called from every
  /// end-of-call path so the notification disappears the instant the
  /// call ends.
  Future<void> stopActiveCallService() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('stopActiveCallService');
    } on PlatformException catch (e) {
      debugPrint('[native_call_bridge] stopActiveCallService failed: $e');
    } on MissingPluginException {
      /* tests */
    }
  }

  /// Toggle whether backgrounding the app should auto-enter Picture-in-Picture.
  /// Call with `true` while a call screen is foregrounded, `false` on leave.
  Future<void> setPipActive(bool active) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setPipActive', {'active': active});
    } on PlatformException catch (e) {
      debugPrint('[native_call_bridge] setPipActive failed: $e');
    } on MissingPluginException {
      /* tests / iOS */
    }
  }

  /// Cold-start: the conversation_id from a message notification that launched
  /// the app (null if it wasn't launched from one).
  Future<String?> getInitialConversation() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('getInitialConversation');
    } on PlatformException catch (e) {
      debugPrint('[native_call_bridge] getInitialConversation failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Explicitly request Picture-in-Picture (e.g. the minimize button).
  /// Returns true if the OS entered PiP; false when unsupported.
  Future<bool> enterPip() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('enterPip') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[native_call_bridge] enterPip failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    isInPip.dispose();
    await _events.close();
  }

  // ── MethodCallHandler ──────────────────────────────────────────────────────

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'incomingCall':
        final event = _parseIncomingCall(call.arguments);
        if (event != null) {
          _events.add(event);
        }
        return null;
      case 'callAction':
        final event = _parseCallAction(call.arguments);
        if (event != null) {
          _events.add(event);
        }
        return null;
      case 'pipModeChanged':
        isInPip.value = call.arguments == true;
        return null;
      case 'openConversation':
        final convId = call.arguments as String?;
        if (convId != null && convId.isNotEmpty) {
          onOpenConversation?.call(convId);
        }
        return null;
      case 'openRoute':
        final route = call.arguments as String?;
        if (route != null && route.isNotEmpty) {
          onOpenRoute?.call(route);
        }
        return null;
      default:
        return null;
    }
  }

  // ── Parsers (exposed as static for unit tests) ─────────────────────────────

  /// Parse the value returned by `getInitialCallData`. Returns null when
  /// the value is null or malformed.
  static NativeCallEvent? parseInitialCallData(dynamic raw) {
    if (raw == null) return null;
    final map = _asStringMap(raw);
    if (map == null) return null;
    if ((map['call_id'] as String?) == null) return null;

    final nativeAction = map['native_action'] as String?;
    final kind = switch (nativeAction) {
      'accept' => NativeCallEventKind.accept,
      'decline' => NativeCallEventKind.decline,
      'hangup' => NativeCallEventKind.hangup,
      _ => NativeCallEventKind.incoming,
    };
    return NativeCallEvent(kind: kind, payload: map);
  }

  static NativeCallEvent? _parseIncomingCall(dynamic raw) {
    final map = _asStringMap(raw);
    if (map == null) return null;
    if ((map['call_id'] as String?) == null) return null;
    return NativeCallEvent(
      kind: NativeCallEventKind.incoming,
      payload: map,
    );
  }

  static NativeCallEvent? _parseCallAction(dynamic raw) {
    final map = _asStringMap(raw);
    if (map == null) return null;
    if ((map['call_id'] as String?) == null) return null;
    final nativeAction = map['native_action'] as String?;
    final kind = switch (nativeAction) {
      'accept' => NativeCallEventKind.accept,
      'decline' => NativeCallEventKind.decline,
      'hangup' => NativeCallEventKind.hangup,
      _ => null,
    };
    if (kind == null) return null;
    return NativeCallEvent(kind: kind, payload: map);
  }

  static Map<String, dynamic>? _asStringMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      // Platform channels return Map<Object?, Object?> on Android.
      final out = <String, dynamic>{};
      for (final entry in raw.entries) {
        final k = entry.key;
        if (k is String) {
          out[k] = entry.value;
        }
      }
      return out;
    }
    return null;
  }
}

/// Singleton bridge — one MethodChannel per app, regardless of how many
/// listeners subscribe.
final nativeCallBridgeProvider = Provider<NativeCallBridge>((ref) {
  final bridge = NativeCallBridge();
  bridge.installHandler();
  ref.onDispose(bridge.dispose);
  return bridge;
});

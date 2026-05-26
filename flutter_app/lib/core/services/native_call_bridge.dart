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

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
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

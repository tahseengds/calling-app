// Unit tests for NativeCallBridge — parsing of MethodChannel payloads and the
// dedup behaviour CallNotifier relies on (prompt 15).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/services/native_call_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── parseInitialCallData ──────────────────────────────────────────────────

  group('NativeCallBridge.parseInitialCallData', () {
    test('returns null for null input', () {
      expect(NativeCallBridge.parseInitialCallData(null), isNull);
    });

    test('returns null when call_id is missing', () {
      final raw = {'caller_name': 'A'};
      expect(NativeCallBridge.parseInitialCallData(raw), isNull);
    });

    test('classifies as incoming when no native_action is set', () {
      final raw = {
        'call_id': 'c1',
        'caller_id': 'u-peer',
        'caller_name': 'Peer',
        'call_type': 'audio',
      };
      final ev = NativeCallBridge.parseInitialCallData(raw)!;
      expect(ev.kind, NativeCallEventKind.incoming);
      expect(ev.callId, 'c1');
      expect(ev.payload['caller_name'], 'Peer');
    });

    test('classifies as accept when native_action=accept', () {
      final raw = {
        'call_id': 'c2',
        'native_action': 'accept',
      };
      final ev = NativeCallBridge.parseInitialCallData(raw)!;
      expect(ev.kind, NativeCallEventKind.accept);
    });

    test('classifies as decline when native_action=decline', () {
      final raw = {
        'call_id': 'c3',
        'native_action': 'decline',
      };
      final ev = NativeCallBridge.parseInitialCallData(raw)!;
      expect(ev.kind, NativeCallEventKind.decline);
    });

    test('handles platform-channel Map<Object?,Object?>', () {
      // Platform channels deliver Map<Object?,Object?> on Android.
      final Map<Object?, Object?> raw = <Object?, Object?>{
        'call_id': 'c4',
        'caller_name': 'X',
        'native_action': 'accept',
      };
      final ev = NativeCallBridge.parseInitialCallData(raw)!;
      expect(ev.kind, NativeCallEventKind.accept);
      expect(ev.callId, 'c4');
      expect(ev.payload['caller_name'], 'X');
    });

    test('drops non-string keys', () {
      final Map<Object?, Object?> raw = <Object?, Object?>{
        'call_id': 'c5',
        42: 'should be dropped',
      };
      final ev = NativeCallBridge.parseInitialCallData(raw)!;
      // Payload is Map<String, dynamic>; non-string keys are filtered out
      // before they ever enter the map.
      expect(ev.payload.length, 1);
      expect(ev.payload['call_id'], 'c5');
    });

    test('returns null for non-map input', () {
      expect(NativeCallBridge.parseInitialCallData('a string'), isNull);
      expect(NativeCallBridge.parseInitialCallData(42), isNull);
    });
  });

  // ── MethodCallHandler integration ─────────────────────────────────────────

  group('NativeCallBridge MethodCallHandler', () {
    test('incomingCall pushes an event onto the stream', () async {
      const channel = MethodChannel('familylink/calls.test.in');
      final bridge = NativeCallBridge(channel: channel);
      bridge.installHandler();
      addTearDown(bridge.dispose);

      final eventFuture = bridge.events.first;

      // Simulate the native side invoking incomingCall on the channel.
      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('incomingCall', <String, Object?>{
            'call_id': 'k1',
            'caller_name': 'Family',
            'call_type': 'video',
          }),
        ),
        null,
      );

      final ev = await eventFuture.timeout(const Duration(seconds: 1));
      expect(ev.kind, NativeCallEventKind.incoming);
      expect(ev.callId, 'k1');
      expect(ev.payload['caller_name'], 'Family');
    });

    test('callAction with accept becomes NativeCallEventKind.accept', () async {
      const channel = MethodChannel('familylink/calls.test.action');
      final bridge = NativeCallBridge(channel: channel);
      bridge.installHandler();
      addTearDown(bridge.dispose);

      final eventFuture = bridge.events.first;
      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('callAction', <String, Object?>{
            'call_id': 'k2',
            'native_action': 'accept',
          }),
        ),
        null,
      );

      final ev = await eventFuture.timeout(const Duration(seconds: 1));
      expect(ev.kind, NativeCallEventKind.accept);
      expect(ev.callId, 'k2');
    });

    test('callAction with unknown action emits nothing', () async {
      const channel = MethodChannel('familylink/calls.test.unknown');
      final bridge = NativeCallBridge(channel: channel);
      bridge.installHandler();
      addTearDown(bridge.dispose);

      var fired = false;
      final sub = bridge.events.listen((_) => fired = true);
      addTearDown(sub.cancel);

      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('callAction', <String, Object?>{
            'call_id': 'k3',
            'native_action': 'bogus',
          }),
        ),
        null,
      );

      // Give the broadcast stream a microtask to deliver if it were going to.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fired, isFalse);
    });
  });

  // ── invokeMethod handlers (acceptCall/declineCall/endCall/stopCallService) ─

  group('NativeCallBridge outgoing methods', () {
    test('acceptCall sends call_id over the channel', () async {
      const channel = MethodChannel('familylink/calls.test.accept');
      MethodCall? lastCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        lastCall = call;
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final bridge = NativeCallBridge(channel: channel);
      await bridge.acceptCall('call-xyz');
      expect(lastCall, isNotNull);
      expect(lastCall!.method, 'acceptCall');
      expect((lastCall!.arguments as Map)['call_id'], 'call-xyz');
    });

    test('missing-plugin / platform exceptions are swallowed', () async {
      const channel = MethodChannel('familylink/calls.test.missing');
      // No handler installed → MissingPluginException.
      final bridge = NativeCallBridge(channel: channel);
      // All four should complete without throwing.
      await bridge.acceptCall('x');
      await bridge.declineCall('x');
      await bridge.endCall('x');
      await bridge.stopCallService();
      final initial = await bridge.getInitialCallData();
      expect(initial, isNull);
    });
  });
}

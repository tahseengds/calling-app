import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:flutter_app/core/services/signaling_service.dart';
import 'package:flutter_app/core/services/webrtc_service.dart';
import 'package:flutter_app/core/storage/local_db.dart';
import 'package:flutter_app/features/calling/data/call_repository.dart';
import 'package:flutter_app/features/calling/domain/call_notifier.dart';
import 'package:flutter_app/features/calling/domain/call_state.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────────

class FakeSignalingService extends SignalingService {
  // Expose controllers for test injection
  final incomingCtrl = StreamController<CallIncomingEvent>.broadcast();
  final answeredCtrl = StreamController<CallAnsweredEvent>.broadcast();
  final iceCtrl = StreamController<CallIceEvent>.broadcast();
  final iceRestartCtrl =
      StreamController<CallIceRestartEvent>.broadcast();
  final hangupCtrl = StreamController<CallHangupEvent>.broadcast();
  final rejectedCtrl = StreamController<CallRejectedEvent>.broadcast();
  final busyCtrl = StreamController<CallBusyEvent>.broadcast();
  final missedCtrl = StreamController<CallMissedEvent>.broadcast();

  final List<String> emittedEvents = [];

  @override
  Stream<CallIncomingEvent> get onCallIncoming => incomingCtrl.stream;
  @override
  Stream<CallAnsweredEvent> get onCallAnswered => answeredCtrl.stream;
  @override
  Stream<CallIceEvent> get onCallIce => iceCtrl.stream;
  @override
  Stream<CallIceRestartEvent> get onCallIceRestart =>
      iceRestartCtrl.stream;
  @override
  Stream<CallHangupEvent> get onCallHangup => hangupCtrl.stream;
  @override
  Stream<CallRejectedEvent> get onCallRejected => rejectedCtrl.stream;
  @override
  Stream<CallBusyEvent> get onCallBusy => busyCtrl.stream;
  @override
  Stream<CallMissedEvent> get onCallMissed => missedCtrl.stream;

  @override
  void emitCallInitiate({
    required String callId,
    required String to,
    required Map<String, dynamic> offer,
    required String callType,
  }) {
    emittedEvents.add('call:initiate');
  }

  @override
  void emitCallAnswer({
    required String callId,
    required String to,
    required Map<String, dynamic> answer,
  }) {
    emittedEvents.add('call:answer');
  }

  @override
  void emitCallIce({
    required String callId,
    required String to,
    required Map<String, dynamic> candidate,
  }) {
    emittedEvents.add('call:ice');
  }

  @override
  void emitCallHangup({required String callId, required String to}) {
    emittedEvents.add('call:hangup');
  }

  @override
  void emitCallReject({required String callId, required String to}) {
    emittedEvents.add('call:reject');
  }

  @override
  void emitCallBusy({required String callId, required String to}) {
    emittedEvents.add('call:busy');
  }

  @override
  void emitCallIceRestart({
    required String callId,
    required String to,
    required Map<String, dynamic> offer,
  }) {
    emittedEvents.add('call:ice_restart');
  }

  @override
  void connect(String accessToken) {}
  @override
  void disconnect() {}
  @override
  void dispose() {
    incomingCtrl.close();
    answeredCtrl.close();
    iceCtrl.close();
    iceRestartCtrl.close();
    hangupCtrl.close();
    rejectedCtrl.close();
    busyCtrl.close();
    missedCtrl.close();
  }
}

class FakeWebRTCService implements WebRTCService {
  @override
  Future<void> initialize(
          {required List<Map<String, dynamic>> iceServers}) async {}

  @override
  Future<Map<String, dynamic>> createOffer(
          {required bool videoEnabled}) async =>
      {'sdp': 'fake_offer_sdp', 'type': 'offer'};

  @override
  Future<Map<String, dynamic>> createAnswer(
    Map<String, dynamic> remoteOfferMap, {
    required bool videoEnabled,
  }) async =>
      {'sdp': 'fake_answer_sdp', 'type': 'answer'};

  @override
  Future<void> setRemoteDescription(Map<String, dynamic> sdpMap) async {}

  @override
  Future<void> addIceCandidate(Map<String, dynamic> candidateMap) async {}

  @override
  Future<Map<String, dynamic>> createIceRestartOffer() async =>
      {'sdp': 'fake_restart_sdp', 'type': 'offer'};

  @override
  Future<void> applyIceRestartAnswer(Map<String, dynamic> sdpMap) async {}

  void Function(WebRTCConnectionState)? _onConn;
  void Function(WebRTCIceState)? _onIceState;

  @override
  void onIceCandidate(void Function(Map<String, dynamic>) callback) {
    // ICE candidates are not tested at the unit level
  }

  @override
  void onConnectionStateChange(
      void Function(WebRTCConnectionState) callback) {
    _onConn = callback;
  }

  @override
  void onIceConnectionStateChange(
      void Function(WebRTCIceState) callback) {
    _onIceState = callback;
  }

  void simulateConnected() {
    _onIceState?.call(WebRTCIceState.connected);
  }

  void simulateDisconnected() {
    _onIceState?.call(WebRTCIceState.disconnected);
  }

  void simulateFailed() {
    _onConn?.call(WebRTCConnectionState.failed);
    _onIceState?.call(WebRTCIceState.failed);
  }

  @override
  Future<void> toggleMic() async {}
  @override
  Future<void> toggleCamera() async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> setSpeakerphone(bool enabled) async {}
  @override
  Future<CallQualityStats> getStats() async => const CallQualityStats();

  bool disposed = false;
  @override
  Future<void> dispose() async {
    disposed = true;
  }

  // RTCVideoRenderer stubs — these throw if accessed (unit tests don't render video)
  @override
  RTCVideoRenderer get localRenderer => throw UnimplementedError('no renderer in unit test');
  @override
  RTCVideoRenderer get remoteRenderer => throw UnimplementedError('no renderer in unit test');
  @override
  bool get isMicOn => true;
  @override
  bool get isCameraOn => true;
}

class FakeCallRepository implements CallRepository {
  @override
  Future<List<Map<String, dynamic>>> getTurnCredentials() async => [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];

  @override
  Future<List<CallRecord>> getCallHistory(
          {String? cursor, int limit = 30}) async =>
      [];

  @override
  Future<CallRecord?> getCall(String callId) async => null;

  @override
  Stream<List<CallRecordRow>> watchCachedHistory() => const Stream.empty();
}

// ── Test subclass that swaps in fakes ─────────────────────────────────────────

class TestCallNotifier extends CallNotifier {
  final FakeWebRTCService fakeWebrtc;
  TestCallNotifier(this.fakeWebrtc);

  @override
  WebRTCService createWebRTCService() => fakeWebrtc;
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _incomingPayload = {
  'call_id': 'call-abc-123',
  'from': 'user-peer-456',
  'from_user': {'id': 'user-peer-456', 'name': 'Test Peer'},
  'call_type': 'audio',
  'offer': {'sdp': 'remote_offer_sdp', 'type': 'offer'},
};

const _peerUser = PeerUser(id: 'user-peer-456', name: 'Test Peer');

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // Initialize the Flutter binding so that any remaining platform channel
  // calls (e.g. flutter_webrtc internals) don't crash unit tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSignalingService sig;
  late FakeWebRTCService webrtc;
  late FakeCallRepository repo;
  late ProviderContainer container;
  late CallNotifier notifier;

  setUp(() {
    sig = FakeSignalingService();
    webrtc = FakeWebRTCService();
    repo = FakeCallRepository();

    container = ProviderContainer(overrides: [
      signalingServiceProvider.overrideWithValue(sig),
      callRepositoryProvider.overrideWithValue(repo),
      callSessionProvider.overrideWith(() => TestCallNotifier(webrtc)),
    ]);

    notifier = container.read(callSessionProvider.notifier);
    addTearDown(container.dispose);
  });

  // ── Initial state ──────────────────────────────────────────────────────────

  test('initial state is null', () {
    expect(container.read(callSessionProvider), isNull);
  });

  // ── Incoming call ──────────────────────────────────────────────────────────

  group('handleIncomingCall', () {
    test('transitions to incomingRinging', () async {
      await notifier.handleIncomingCall(_incomingPayload);

      final session = container.read(callSessionProvider);
      expect(session, isNotNull);
      expect(session!.phase, CallPhase.incomingRinging);
      expect(session.peerUser.name, 'Test Peer');
      expect(session.callType, CallType.audio);
      expect(session.direction, CallDirection.incoming);
    });

    test('stores the remote offer in pendingOffer', () async {
      await notifier.handleIncomingCall(_incomingPayload);

      final session = container.read(callSessionProvider);
      expect(session!.pendingOffer, isNotNull);
      expect(session.pendingOffer!['type'], 'offer');
    });

    test('emits call:busy when already in a call', () async {
      await notifier.handleIncomingCall(_incomingPayload);
      expect(sig.emittedEvents, isEmpty);

      await notifier.handleIncomingCall({
        ..._incomingPayload,
        'call_id': 'call-second-999',
        'from': 'user-third-789',
      });

      expect(sig.emittedEvents, contains('call:busy'));
      // First call should still be active
      expect(container.read(callSessionProvider)?.callId, 'call-abc-123');
    });

    test(
      'dedups duplicate incoming for the same call_id (socket + FCM)',
      () async {
        // First delivery: e.g. via the native FCM bridge.
        await notifier.handleIncomingCall(_incomingPayload);
        final firstSession = container.read(callSessionProvider);
        expect(firstSession?.callId, 'call-abc-123');
        expect(firstSession?.phase, CallPhase.incomingRinging);

        // Second delivery: socket call:incoming arriving moments later.
        // Should be a no-op — no call:busy emit, session unchanged.
        await notifier.handleIncomingCall(_incomingPayload);

        expect(sig.emittedEvents, isEmpty);
        expect(
          container.read(callSessionProvider)?.callId,
          'call-abc-123',
        );
      },
    );
  });

  // ── handleIncomingCallFromKilledState (prompt 15) ─────────────────────────

  group('handleIncomingCallFromKilledState', () {
    test('normalizes native FCM payload into a ringing session', () async {
      await notifier.handleIncomingCallFromKilledState({
        'call_id': 'call-fcm-1',
        'caller_id': 'user-peer-fcm',
        'caller_name': 'FCM Peer',
        'caller_avatar': 'https://x/avatar.png',
        'call_type': 'video',
        'sdp_offer': 'v=0\r\no=- 12345 ...\r\n',
        'signal_token': 'opaque',
      });

      final session = container.read(callSessionProvider);
      expect(session, isNotNull);
      expect(session!.callId, 'call-fcm-1');
      expect(session.callType, CallType.video);
      expect(session.peerUser.id, 'user-peer-fcm');
      expect(session.peerUser.name, 'FCM Peer');
      expect(session.phase, CallPhase.incomingRinging);
      expect(session.pendingOffer, isNotNull);
      expect(session.pendingOffer!['type'], 'offer');
      expect(session.pendingOffer!['sdp'], contains('v=0'));
    });

    test('drops payload missing call_id', () async {
      await notifier.handleIncomingCallFromKilledState({
        'caller_name': 'Anonymous',
      });
      expect(container.read(callSessionProvider), isNull);
    });

    test(
      'subsequent socket call:incoming with the same id does not double-ring',
      () async {
        await notifier.handleIncomingCallFromKilledState({
          'call_id': 'call-fcm-2',
          'caller_id': 'user-peer-fcm',
          'caller_name': 'FCM Peer',
          'call_type': 'audio',
          'sdp_offer': 'remote_offer_sdp',
        });

        // Now the socket delivers the same call:incoming event.
        await notifier.handleIncomingCall({
          'call_id': 'call-fcm-2',
          'from': 'user-peer-fcm',
          'from_user': {'id': 'user-peer-fcm', 'name': 'FCM Peer'},
          'call_type': 'audio',
          'offer': {'sdp': 'remote_offer_sdp', 'type': 'offer'},
        });

        expect(sig.emittedEvents, isEmpty); // no call:busy
        // Original ringing session is preserved.
        expect(
          container.read(callSessionProvider)?.callId,
          'call-fcm-2',
        );
        expect(
          container.read(callSessionProvider)?.phase,
          CallPhase.incomingRinging,
        );
      },
    );
  });

  // ── Decline call ──────────────────────────────────────────────────────────

  group('declineCall', () {
    test('transitions to ended with rejected reason', () async {
      await notifier.handleIncomingCall(_incomingPayload);
      notifier.declineCall();

      final session = container.read(callSessionProvider);
      expect(session?.phase, CallPhase.ended);
      expect(session?.endReason, EndReason.rejected);
    });

    test('emits call:reject', () async {
      await notifier.handleIncomingCall(_incomingPayload);
      notifier.declineCall();

      expect(sig.emittedEvents, contains('call:reject'));
    });

    test('no-op when no active call', () {
      notifier.declineCall(); // should not throw
      expect(container.read(callSessionProvider), isNull);
    });
  });

  // ── Accept call ───────────────────────────────────────────────────────────

  group('acceptCall', () {
    test('transitions to connecting then emits call:answer', () async {
      await notifier.handleIncomingCall(_incomingPayload);
      await notifier.acceptCall();

      final session = container.read(callSessionProvider);
      expect(session?.phase, CallPhase.connecting);
      expect(sig.emittedEvents, contains('call:answer'));
    });

    test('transitions to connected when ICE connects', () async {
      await notifier.handleIncomingCall(_incomingPayload);
      await notifier.acceptCall();
      webrtc.simulateConnected();

      await Future.delayed(Duration.zero); // allow state to propagate

      final session = container.read(callSessionProvider);
      expect(session?.phase, CallPhase.connected);
      expect(session?.connectedAt, isNotNull);
    });
  });

  // ── Outgoing call ─────────────────────────────────────────────────────────

  group('startCall', () {
    test('transitions to outgoingRinging and emits call:initiate', () async {
      await notifier.startCall(_peerUser, CallType.audio);

      final session = container.read(callSessionProvider);
      expect(session?.phase, CallPhase.outgoingRinging);
      expect(session?.direction, CallDirection.outgoing);
      expect(sig.emittedEvents, contains('call:initiate'));
    });

    test('transitions to connecting on call:answered', () async {
      await notifier.startCall(_peerUser, CallType.audio);

      sig.answeredCtrl.add(CallAnsweredEvent({
        'call_id': container.read(callSessionProvider)!.callId,
        'answer': {'sdp': 'answer_sdp', 'type': 'answer'},
      }));

      await Future.delayed(Duration.zero);

      expect(container.read(callSessionProvider)?.phase,
          CallPhase.connecting);
    });

    test('transitions to ended on call:rejected', () async {
      await notifier.startCall(_peerUser, CallType.audio);
      final callId = container.read(callSessionProvider)!.callId;

      sig.rejectedCtrl.add(
          CallRejectedEvent(callId: callId, fromUserId: _peerUser.id));
      await Future.delayed(Duration.zero);

      expect(container.read(callSessionProvider)?.phase, CallPhase.ended);
      expect(container.read(callSessionProvider)?.endReason,
          EndReason.declined);
    });

    test('transitions to ended on call:busy', () async {
      await notifier.startCall(_peerUser, CallType.audio);
      final callId = container.read(callSessionProvider)!.callId;

      sig.busyCtrl.add(CallBusyEvent(callId: callId));
      await Future.delayed(Duration.zero);

      expect(container.read(callSessionProvider)?.phase, CallPhase.ended);
      expect(container.read(callSessionProvider)?.endReason, EndReason.busy);
    });

    test('ignores busy/rejected events for different call IDs', () async {
      await notifier.startCall(_peerUser, CallType.audio);

      sig.rejectedCtrl.add(
          CallRejectedEvent(callId: 'different-id', fromUserId: 'x'));
      await Future.delayed(Duration.zero);

      // Still outgoing — not affected
      expect(container.read(callSessionProvider)?.phase,
          CallPhase.outgoingRinging);
    });
  });

  // ── Hang up ────────────────────────────────────────────────────────────────

  group('endCall', () {
    test('emits call:hangup and transitions to ended', () async {
      await notifier.handleIncomingCall(_incomingPayload);
      await notifier.acceptCall();
      await notifier.endCall();

      expect(sig.emittedEvents, contains('call:hangup'));
      expect(container.read(callSessionProvider)?.phase, CallPhase.ended);
      expect(container.read(callSessionProvider)?.endReason,
          EndReason.hungUp);
    });

    test('disposes WebRTC service', () async {
      await notifier.handleIncomingCall(_incomingPayload);
      await notifier.acceptCall();
      await notifier.endCall();

      expect(webrtc.disposed, isTrue);
    });
  });

  // ── Remote hang-up ────────────────────────────────────────────────────────

  test('remote hangup ends call with hungUp reason', () async {
    await notifier.handleIncomingCall(_incomingPayload);
    await notifier.acceptCall();

    sig.hangupCtrl.add(CallHangupEvent(
      callId: 'call-abc-123',
      fromUserId: _peerUser.id,
    ));
    await Future.delayed(Duration.zero);

    expect(container.read(callSessionProvider)?.phase, CallPhase.ended);
    expect(
        container.read(callSessionProvider)?.endReason, EndReason.hungUp);
  });

  // ── In-call controls ──────────────────────────────────────────────────────

  group('in-call controls', () {
    setUp(() async {
      await notifier.handleIncomingCall(_incomingPayload);
      await notifier.acceptCall();
      webrtc.simulateConnected();
      await Future.delayed(Duration.zero);
    });

    test('toggleMic flips isMuted', () async {
      expect(container.read(callSessionProvider)?.isMuted, isFalse);
      await notifier.toggleMic();
      expect(container.read(callSessionProvider)?.isMuted, isTrue);
      await notifier.toggleMic();
      expect(container.read(callSessionProvider)?.isMuted, isFalse);
    });

    test('toggleCamera flips isCameraOff', () async {
      expect(container.read(callSessionProvider)?.isCameraOff, isFalse);
      await notifier.toggleCamera();
      expect(container.read(callSessionProvider)?.isCameraOff, isTrue);
    });

    test('toggleSpeaker flips isSpeakerOn', () async {
      expect(container.read(callSessionProvider)?.isSpeakerOn, isFalse);
      await notifier.toggleSpeaker();
      expect(container.read(callSessionProvider)?.isSpeakerOn, isTrue);
    });
  });

  // ── Reconnection ──────────────────────────────────────────────────────────

  group('reconnection', () {
    setUp(() async {
      await notifier.handleIncomingCall(_incomingPayload);
      await notifier.acceptCall();
      webrtc.simulateConnected();
      await Future.delayed(Duration.zero);
    });

    test('ICE failed triggers ICE restart emit', () async {
      webrtc.simulateFailed();
      await Future.delayed(Duration.zero);

      expect(container.read(callSessionProvider)?.phase,
          CallPhase.reconnecting);
      expect(sig.emittedEvents, contains('call:ice_restart'));
    });
  });

  // ── Video call ────────────────────────────────────────────────────────────

  test('video call stores callType correctly', () async {
    await notifier.startCall(_peerUser, CallType.video);
    expect(container.read(callSessionProvider)?.callType, CallType.video);
  });

  // ── switchToAudioOnly ─────────────────────────────────────────────────────

  test('switchToAudioOnly turns off camera and callType → audio', () async {
    await notifier.handleIncomingCall({
      ..._incomingPayload,
      'call_type': 'video',
    });
    await notifier.acceptCall();
    webrtc.simulateConnected();
    await Future.delayed(Duration.zero);

    await notifier.switchToAudioOnly();

    final session = container.read(callSessionProvider);
    expect(session?.isCameraOff, isTrue);
    expect(session?.callType, CallType.audio);
  });
}

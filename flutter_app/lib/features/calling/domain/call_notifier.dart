import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/services/native_call_bridge.dart';
import '../../../core/services/signaling_service.dart';
import '../../../core/services/webrtc_service.dart';
import '../data/call_repository.dart';
import 'call_state.dart';

class CallNotifier extends Notifier<CallSession?> {
  WebRTCService? _webrtc;

  // ── Timers ──────────────────────────────────────────────────────────────────
  Timer? _reconnectTimer;   // 3 s before entering reconnecting phase
  Timer? _failTimer;        // 30 s before giving up on reconnection
  Timer? _ringTimeoutTimer; // 45 s ring timeout (incoming or outgoing)
  Timer? _qualityTimer;     // 5 s quality poll
  Timer? _durationTimer;    // 1 s tick to update displayed duration

  final List<StreamSubscription<dynamic>> _subs = [];

  // ── Dedup (prompt 15) ───────────────────────────────────────────────────────
  // call_ids we've already accepted for ringing this session. Used to suppress
  // double-ring when both the socket call:incoming and the FCM-driven native
  // bridge deliver the same call. Entries are evicted on call end.
  final Set<String> _seenIncomingIds = <String>{};

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  CallSession? build() {
    _subscribeToSignaling();
    _subscribeToNativeBridge();
    ref.onDispose(_cleanup);
    return null;
  }

  // ── Public interface ────────────────────────────────────────────────────────

  /// Expose the live WebRTC service so screens can access renderers.
  WebRTCService? get webrtcService => _webrtc;

  /// Place an outgoing call to [peer].
  Future<void> startCall(PeerUser peer, CallType callType) async {
    if (state != null) {
      return; // only one active call at a time
    }

    final callId = const Uuid().v4();

    state = CallSession(
      callId: callId,
      peerUser: peer,
      callType: callType,
      direction: CallDirection.outgoing,
      phase: CallPhase.outgoingRinging,
      startedAt: DateTime.now().toUtc(),
    );

    try {
      final iceServers =
          await ref.read(callRepositoryProvider).getTurnCredentials();

      _webrtc = createWebRTCService();
      await _webrtc!.initialize(iceServers: iceServers);
      _wireCallbacks(peer.id);

      final offer =
          await _webrtc!.createOffer(videoEnabled: callType == CallType.video);

      ref.read(signalingServiceProvider).emitCallInitiate(
            callId: callId,
            to: peer.id,
            offer: offer,
            callType: callType.name,
          );

      // Cancel if no answer arrives within 45 s
      _ringTimeoutTimer = Timer(const Duration(seconds: 45), () {
        if (state?.phase == CallPhase.outgoingRinging) {
          _endWithReason(EndReason.timeout);
        }
      });
    } catch (_) {
      _endWithReason(EndReason.failed);
    }
  }

  /// Called when a `call:incoming` socket event arrives (also from prompt 15).
  Future<void> handleIncomingCall(Map<String, dynamic> payload) async {
    final callId = payload['call_id'] as String?;
    final from = payload['from'] as String? ?? '';

    if (state != null && state!.callId != callId) {
      // Already in a different call — tell the caller we're busy.
      ref.read(signalingServiceProvider).emitCallBusy(
            callId: callId ?? '',
            to: from,
          );
      return;
    }

    // Dedup: if we've already presented this call (e.g. via the native FCM
    // path) then ignore the duplicate to avoid a double-ring or rebuilding
    // the session in mid-ring.
    if (callId != null && _seenIncomingIds.contains(callId)) {
      return;
    }

    final fromUser =
        payload['from_user'] as Map<String, dynamic>? ?? const {};
    final peer = PeerUser.fromJson({
      'id': from.isNotEmpty
          ? from
          : fromUser['id'] as String? ?? '',
      ...fromUser,
    });

    final callType = (payload['call_type'] as String?) == 'video'
        ? CallType.video
        : CallType.audio;

    if (callId != null) _seenIncomingIds.add(callId);

    state = CallSession(
      callId: callId ?? const Uuid().v4(),
      peerUser: peer,
      callType: callType,
      direction: CallDirection.incoming,
      phase: CallPhase.incomingRinging,
      startedAt: DateTime.now().toUtc(),
      pendingOffer: payload['offer'] as Map<String, dynamic>?,
    );

    // Missed-call timeout
    _ringTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (state?.phase == CallPhase.incomingRinging) {
        _endWithReason(EndReason.missed);
      }
    });
  }

  /// Called when the native FCM/CallService layer (prompt 15) wakes the
  /// device for an incoming call before the socket has connected.
  ///
  /// The native payload uses flat keys (`call_id`, `caller_id`, `caller_name`,
  /// `caller_avatar`, `call_type`, `sdp_offer`); we normalize them into the
  /// shape the existing socket pipeline uses and forward to
  /// [handleIncomingCall], which dedups against later socket delivery.
  Future<void> handleIncomingCallFromKilledState(
    Map<String, dynamic> nativePayload,
  ) async {
    final normalized = _normalizeNativeIncomingPayload(nativePayload);
    if (normalized == null) return;
    await handleIncomingCall(normalized);
  }

  /// Convert the native FCM/CallService payload shape into the socket
  /// `call:incoming` shape consumed by [handleIncomingCall].
  ///
  /// Returns null if mandatory fields are missing.
  static Map<String, dynamic>? _normalizeNativeIncomingPayload(
    Map<String, dynamic> p,
  ) {
    final callId = p['call_id'] as String?;
    if (callId == null || callId.isEmpty) return null;

    // sdp_offer may arrive as a raw SDP string OR a JSON-encoded map. We
    // accept the string form (most common from FCM) and synthesize the
    // {sdp, type:'offer'} shape WebRTC expects.
    Map<String, dynamic>? offer;
    final sdpRaw = p['sdp_offer'];
    if (sdpRaw is String && sdpRaw.isNotEmpty) {
      offer = {'sdp': sdpRaw, 'type': 'offer'};
    } else if (sdpRaw is Map) {
      offer = sdpRaw.cast<String, dynamic>();
    }

    return {
      'call_id': callId,
      'from': p['caller_id'] as String? ?? '',
      'from_user': {
        'id': p['caller_id'] as String? ?? '',
        'name': p['caller_name'] as String? ?? 'Unknown',
        'avatar_url': ?p['caller_avatar'],
      },
      'call_type': p['call_type'] as String? ?? 'audio',
      'offer': ?offer,
      'signal_token': ?p['signal_token'],
    };
  }

  /// Accept an incoming call (callee side).
  Future<void> acceptCall() async {
    final session = state;
    if (session == null || session.phase != CallPhase.incomingRinging) {
      return;
    }

    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    // Tell the native CallService to stop ringing.
    _bridge?.acceptCall(session.callId);
    state = session.copyWith(phase: CallPhase.connecting);

    try {
      final iceServers =
          await ref.read(callRepositoryProvider).getTurnCredentials();

      _webrtc = createWebRTCService();
      await _webrtc!.initialize(iceServers: iceServers);
      _wireCallbacks(session.peerUser.id);

      final offer = session.pendingOffer;
      if (offer == null) {
        _endWithReason(EndReason.failed);
        return;
      }

      final answer = await _webrtc!.createAnswer(
        offer,
        videoEnabled: session.callType == CallType.video,
      );

      ref.read(signalingServiceProvider).emitCallAnswer(
            callId: session.callId,
            to: session.peerUser.id,
            answer: answer,
          );
    } catch (_) {
      _endWithReason(EndReason.failed);
    }
  }

  /// Decline an incoming call.
  void declineCall() {
    final session = state;
    if (session == null || session.phase != CallPhase.incomingRinging) {
      return;
    }
    // Tell the native CallService to stop ringing.
    _bridge?.declineCall(session.callId);
    ref.read(signalingServiceProvider).emitCallReject(
          callId: session.callId,
          to: session.peerUser.id,
        );
    _endWithReason(EndReason.rejected);
  }

  /// Hang up the current call from any phase.
  Future<void> endCall() async {
    final session = state;
    if (session == null) {
      return;
    }
    // Whether ringing or live, tell native to drop the service.
    _bridge?.endCall(session.callId);
    if (session.phase != CallPhase.incomingRinging) {
      ref.read(signalingServiceProvider).emitCallHangup(
            callId: session.callId,
            to: session.peerUser.id,
          );
    }
    await _teardown();
    _endWithReason(EndReason.hungUp);
  }

  // ── In-call controls ────────────────────────────────────────────────────────

  Future<void> toggleMic() async {
    final session = state;
    if (session == null) {
      return;
    }
    await _webrtc?.toggleMic();
    state = session.copyWith(isMuted: !session.isMuted);
  }

  Future<void> toggleCamera() async {
    final session = state;
    if (session == null) {
      return;
    }
    await _webrtc?.toggleCamera();
    state = session.copyWith(isCameraOff: !session.isCameraOff);
  }

  Future<void> switchCamera() async {
    await _webrtc?.switchCamera();
  }

  Future<void> toggleSpeaker() async {
    final session = state;
    if (session == null) {
      return;
    }
    final newVal = !session.isSpeakerOn;
    await _webrtc?.setSpeakerphone(newVal);
    state = session.copyWith(isSpeakerOn: newVal);
  }

  /// Downgrade a video call to audio-only without dropping the call.
  Future<void> switchToAudioOnly() async {
    final session = state;
    if (session == null) {
      return;
    }
    await _webrtc?.toggleCamera(); // disables video track
    state = session.copyWith(
      isCameraOff: true,
      showSwitchToAudioPrompt: false,
      callType: CallType.audio,
    );
  }

  void dismissSwitchToAudioPrompt() {
    final session = state;
    if (session != null) {
      state = session.copyWith(showSwitchToAudioPrompt: false);
    }
  }

  // ── Overridable factory (swap in tests) ─────────────────────────────────────

  /// Override in test subclasses to inject a mock WebRTCService.
  WebRTCService createWebRTCService() => WebRTCServiceImpl();

  // ── Native call bridge (prompt 15) ──────────────────────────────────────────

  /// Cached bridge reference (null when no provider override is registered,
  /// e.g. in unit tests that don't override nativeCallBridgeProvider).
  NativeCallBridge? _bridge;

  void _subscribeToNativeBridge() {
    final NativeCallBridge bridge;
    try {
      bridge = ref.read(nativeCallBridgeProvider);
    } catch (_) {
      // Provider may be uninitialized in unit tests — bridge stays null.
      return;
    }
    _bridge = bridge;
    _subs.add(bridge.events.listen(_handleNativeEvent));
  }

  Future<void> _handleNativeEvent(NativeCallEvent event) async {
    switch (event.kind) {
      case NativeCallEventKind.incoming:
        await handleIncomingCallFromKilledState(event.payload);
      case NativeCallEventKind.accept:
        // The user accepted via the native notification. If we already have
        // an incoming session (e.g. socket delivery arrived too), accept it.
        // Otherwise build the session first from the FCM payload and then
        // accept it.
        if (state == null) {
          await handleIncomingCallFromKilledState(event.payload);
        }
        if (state?.phase == CallPhase.incomingRinging) {
          await acceptCall();
        }
      case NativeCallEventKind.decline:
        if (state == null) {
          // Build a transient session so declineCall has something to
          // reject by id, then immediately decline it.
          await handleIncomingCallFromKilledState(event.payload);
        }
        if (state?.phase == CallPhase.incomingRinging) {
          declineCall();
        }
    }
  }

  // ── Signaling subscriptions ─────────────────────────────────────────────────

  void _subscribeToSignaling() {
    final sig = ref.read(signalingServiceProvider);

    _subs.addAll([
      sig.onCallIncoming.listen((event) async {
        await handleIncomingCall(event.json);
      }),
      sig.onCallAnswered.listen((event) async {
        await _handleCallAnswered(event.json);
      }),
      sig.onCallIce.listen((event) async {
        await _handleRemoteIce(event.json);
      }),
      sig.onCallIceRestart.listen((event) async {
        await _handleIceRestartOffer(event.json);
      }),
      sig.onCallHangup.listen(_handleRemoteHangup),
      sig.onCallRejected.listen(_handleCallRejected),
      sig.onCallBusy.listen(_handleCallBusy),
      sig.onCallMissed.listen(_handleCallMissed),
    ]);
  }

  // ── Signaling handlers ───────────────────────────────────────────────────────

  Future<void> _handleCallAnswered(Map<String, dynamic> payload) async {
    final session = state;
    if (session == null || session.phase != CallPhase.outgoingRinging) {
      return;
    }
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;

    state = session.copyWith(phase: CallPhase.connecting);

    try {
      final answer =
          payload['answer'] as Map<String, dynamic>? ?? payload;
      await _webrtc?.setRemoteDescription(answer);
    } catch (_) {
      _endWithReason(EndReason.failed);
    }
  }

  Future<void> _handleRemoteIce(Map<String, dynamic> payload) async {
    final candidate = payload['candidate'];
    if (candidate == null || _webrtc == null) {
      return;
    }
    try {
      await _webrtc!.addIceCandidate(
        candidate is Map<String, dynamic> ? candidate : {},
      );
    } catch (_) {}
  }

  Future<void> _handleIceRestartOffer(Map<String, dynamic> payload) async {
    final session = state;
    if (session == null || _webrtc == null) {
      return;
    }
    try {
      final offer = payload['offer'] as Map<String, dynamic>? ?? {};
      final answer = await _webrtc!.createAnswer(
        offer,
        videoEnabled: session.callType == CallType.video,
      );
      ref.read(signalingServiceProvider).emitCallAnswer(
            callId: session.callId,
            to: session.peerUser.id,
            answer: answer,
          );
    } catch (_) {}
  }

  void _handleRemoteHangup(CallHangupEvent event) {
    final session = state;
    if (session == null || session.callId != event.callId) {
      return;
    }
    _teardown().then((_) => _endWithReason(EndReason.hungUp));
  }

  void _handleCallRejected(CallRejectedEvent event) {
    final session = state;
    if (session == null || session.callId != event.callId) {
      return;
    }
    _teardown().then((_) => _endWithReason(EndReason.declined));
  }

  void _handleCallBusy(CallBusyEvent event) {
    final session = state;
    if (session == null || session.callId != event.callId) {
      return;
    }
    _teardown().then((_) => _endWithReason(EndReason.busy));
  }

  void _handleCallMissed(CallMissedEvent event) {
    final session = state;
    if (session == null || session.callId != event.callId) {
      return;
    }
    _endWithReason(EndReason.missed);
  }

  // ── WebRTC callbacks ─────────────────────────────────────────────────────────

  void _wireCallbacks(String peerId) {
    _webrtc!.onIceCandidate((candidateMap) {
      final session = state;
      if (session == null) {
        return;
      }
      ref.read(signalingServiceProvider).emitCallIce(
            callId: session.callId,
            to: peerId,
            candidate: candidateMap,
          );
    });

    _webrtc!.onConnectionStateChange(_handleConnectionState);
    _webrtc!.onIceConnectionStateChange(_handleIceConnectionState);
  }

  void _handleConnectionState(WebRTCConnectionState connState) {
    if (connState == WebRTCConnectionState.failed) {
      _startReconnectSequence();
    }
  }

  void _handleIceConnectionState(WebRTCIceState iceState) {
    final session = state;
    if (session == null) {
      return;
    }

    switch (iceState) {
      case WebRTCIceState.connected:
      case WebRTCIceState.completed:
        _cancelReconnectTimers();
        if (!session.isActive) {
          // First connection
          final connectedAt = DateTime.now().toUtc();
          state = session.copyWith(
            phase: CallPhase.connected,
            connectedAt: connectedAt,
          );
          _startQualityMonitor();
          _startDurationTick();
          // Ignore errors on platforms where wakelock is unavailable (tests, web).
          WakelockPlus.enable().catchError((_) {});
        } else if (session.phase == CallPhase.reconnecting) {
          // Recovered from a blip
          state = session.copyWith(phase: CallPhase.connected);
        }
      case WebRTCIceState.disconnected:
        // Start a grace timer before entering reconnecting phase
        _reconnectTimer ??= Timer(const Duration(seconds: 3), () {
          _reconnectTimer = null;
          if (state?.phase == CallPhase.connected) {
            state = state?.copyWith(phase: CallPhase.reconnecting);
            _startFailTimer();
          }
        });
      case WebRTCIceState.failed:
        _startReconnectSequence();
      default:
        break;
    }
  }

  void _startReconnectSequence() {
    final session = state;
    if (session == null) {
      return;
    }
    if (session.phase != CallPhase.reconnecting) {
      state = session.copyWith(phase: CallPhase.reconnecting);
    }
    _startFailTimer();
    _performIceRestart();
  }

  void _performIceRestart() {
    final session = state;
    if (session == null || _webrtc == null) {
      return;
    }
    _webrtc!.createIceRestartOffer().then((offer) {
      ref.read(signalingServiceProvider).emitCallIceRestart(
            callId: session.callId,
            to: session.peerUser.id,
            offer: offer,
          );
    }).catchError((_) {});
  }

  void _startFailTimer() {
    _failTimer?.cancel();
    _failTimer = Timer(const Duration(seconds: 30), () {
      if (state?.phase == CallPhase.reconnecting) {
        _teardown().then((_) => _endWithReason(EndReason.failed));
      }
    });
  }

  void _cancelReconnectTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _failTimer?.cancel();
    _failTimer = null;
  }

  // ── Quality monitoring ──────────────────────────────────────────────────────

  void _startQualityMonitor() {
    _qualityTimer?.cancel();
    _qualityTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final session = state;
      if (session == null || !session.isActive || _webrtc == null) {
        return;
      }
      final stats = await _webrtc!.getStats();
      state = session.copyWith(quality: stats.level);

      // Suggest audio-only if video FPS collapses
      if (session.callType == CallType.video &&
          !session.isCameraOff &&
          stats.videoFps != null &&
          stats.videoFps! < 5 &&
          !session.showSwitchToAudioPrompt) {
        state = state?.copyWith(showSwitchToAudioPrompt: true);
      }
    });
  }

  void _startDurationTick() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = state;
      // Trigger a state update so the UI re-reads durationSeconds.
      if (s != null && s.isActive) {
        state = s.copyWith();
      }
    });
  }

  // ── End / teardown ───────────────────────────────────────────────────────────

  void _endWithReason(EndReason reason) {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _cancelReconnectTimers();
    _qualityTimer?.cancel();
    _qualityTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;

    // Drop the dedup record so a future call to the same peer can ring again.
    final endingId = state?.callId;
    if (endingId != null) _seenIncomingIds.remove(endingId);

    state = state?.copyWith(phase: CallPhase.ended, endReason: reason);

    // Clear to null after a brief delay so the UI can show "ended" state.
    Future.delayed(const Duration(seconds: 2), () {
      if (state?.phase == CallPhase.ended ||
          state?.phase == CallPhase.failed) {
        state = null;
      }
    });
  }

  Future<void> _teardown() async {
    _qualityTimer?.cancel();
    _qualityTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    // Ignore errors on platforms where wakelock is unavailable (tests, web).
    WakelockPlus.disable().catchError((_) {});
    await _webrtc?.dispose();
    _webrtc = null;
  }

  void _cleanup() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _ringTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _failTimer?.cancel();
    _qualityTimer?.cancel();
    _durationTimer?.cancel();
    _webrtc?.dispose();
  }
}

/// The single active call session. Null when no call is in progress.
final callSessionProvider =
    NotifierProvider<CallNotifier, CallSession?>(CallNotifier.new);

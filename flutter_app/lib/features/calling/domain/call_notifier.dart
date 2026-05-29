import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/services/native_call_bridge.dart';
import '../../../core/services/signaling_service.dart';
import '../../../core/services/webrtc_service.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../auth/domain/auth_state.dart';
import '../../chat/data/message_repository.dart';
import '../../../shared/models/message.dart' show MessageType;
import '../data/call_repository.dart';
import '../data/ringback_player.dart';
import 'call_state.dart';

class CallNotifier extends Notifier<CallSession?> {
  WebRTCService? _webrtc;
  RingbackPlayer? _ringback;

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
    _subscribeToAudioInterruptions();
    // FIX 6: reconcile any interrupted calls from the previous app session.
    // Fire-and-forget; if it fails we'll retry on next launch.
    ref.read(callRepositoryProvider).syncInterruptedCalls().ignore();
    ref.onDispose(_cleanup);
    return null;
  }

  // ── FIX 5: audio interruption handling ─────────────────────────────────────
  // When a cellular call, Siri, or system alarm grabs audio focus mid-VoIP
  // call, the OS pauses our mic/speaker. Without subscribing, audio just
  // goes silent with no state update — the user sits looking at the call
  // screen wondering why nothing's happening. Subscribe to AudioSession's
  // interruption stream and end the call gracefully on `begin` events.
  //
  // We don't try to auto-resume on the `end` event because:
  //   1. The peer connection has been torn down already
  //   2. WebRTC ICE state is gone — re-establishing requires a new offer
  //   3. UX-wise, "call dropped → ask user to re-call" matches what every
  //      other VoIP app does on interruption.
  void _subscribeToAudioInterruptions() {
    // AudioSession.instance.then() — initialising the session is async.
    // We don't await; instead we hook the stream once it resolves and
    // add the subscription to _subs so _cleanup cancels it on dispose.
    AudioSession.instance.then((session) {
      if (!_isAlive) return; // dispose happened before init completed
      final sub = session.interruptionEventStream
          .listen(_handleAudioInterruption);
      _subs.add(sub);
    }).catchError((e) {
      // audio_session not available on all platforms (web, some tests).
      // Failure here is non-fatal — call interruption handling is a polish
      // feature, calls still work without it.
      debugPrint('[call] audio_session init failed (non-fatal): $e');
    });
  }

  void _handleAudioInterruption(AudioInterruptionEvent event) {
    // Only act on `begin` — `end` arrives after the interruption clears,
    // but by then we've already torn down.
    if (!event.begin) return;
    final session = state;
    if (session == null) return;
    // Only end active calls. Ringing-but-not-yet-connected calls don't have
    // open mic/speaker yet, so the interruption is harmless.
    if (session.phase != CallPhase.connected &&
        session.phase != CallPhase.reconnecting) {
      return;
    }
    debugPrint(
        '[call] audio interrupted (type=${event.type}) — ending active call');
    // Notify the peer that we're hanging up; otherwise their end shows the
    // call as ongoing until their own ICE timeout fires.
    ref.read(signalingServiceProvider).emitCallHangup(
          callId: session.callId,
          to: session.peerUser.id,
        );
    _endWithReason(EndReason.interrupted);
  }

  /// True while build() has returned but _cleanup hasn't run.
  bool _isAlive = true;

  // ── Public interface ────────────────────────────────────────────────────────

  /// Expose the live WebRTC service so screens can access renderers.
  WebRTCService? get webrtcService => _webrtc;

  /// Place an outgoing call to [peer].
  Future<void> startCall(PeerUser peer, CallType callType) async {
    if (state != null) {
      return; // only one active call at a time
    }

    // ── FIX 1: self-call guard ──────────────────────────────────────────────
    // Backend rejects self-calls with call:error, but doing so wastes a full
    // WebRTC init + offer roundtrip first. Short-circuit locally so the UI
    // doesn't flash an outgoing-call screen for a call that can't possibly
    // succeed. Uses the same auth pattern as chat_notifier (_currentUserId).
    final auth = ref.read(authNotifierProvider);
    final myUserId = auth is AuthAuthenticated ? auth.me.id : '';
    if (myUserId.isNotEmpty && peer.id == myUserId) {
      debugPrint('[call] startCall blocked: cannot call yourself');
      return;
    }

    // ── FIX 2: mic permission gate ──────────────────────────────────────────
    // All current entry points (chat_rich_screen, call_history_screen,
    // contacts_screen) check the mic permission BEFORE calling startCall, but
    // we shouldn't trust them — any future caller that forgets the check
    // would silently fail deep inside WebRTC init with an opaque error.
    // Defense in depth: re-check here and surface a human-readable failure.
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        debugPrint('[call] startCall blocked: microphone permission denied');
        // Push the outgoing call screen briefly so the UI has somewhere to
        // surface the explanatory message — without the outgoingRinging
        // transition, the global observer in app.dart never routes to
        // /call/outgoing and the errorMessage has nowhere to render.
        final transientId = 'denied-${const Uuid().v4()}';
        state = CallSession(
          callId: transientId,
          peerUser: peer,
          callType: callType,
          direction: CallDirection.outgoing,
          phase: CallPhase.outgoingRinging,
          startedAt: DateTime.now().toUtc(),
        );
        // Next microtask: flip to failed with the explanatory message. The
        // outgoing call screen's ref.listen sees this transition and shows
        // the snackbar + pops the route. ~200 ms is enough for the screen
        // to mount; longer makes the flash visible to the user.
        Future.delayed(const Duration(milliseconds: 200), () {
          if (state?.callId != transientId) return; // raced with another start
          state = state?.copyWith(
            phase: CallPhase.failed,
            endReason: EndReason.failed,
            errorMessage:
                'Microphone access is required to place a call. Enable it in your device settings.',
          );
        });
        // Auto-clear after the message has had time to surface and the
        // outgoing screen has popped (snackbar lives in the root messenger
        // so it survives the pop).
        Future.delayed(const Duration(seconds: 2, milliseconds: 200), () {
          if (state?.callId == transientId) state = null;
        });
        return;
      }
    }

    final callId = const Uuid().v4();

    // Video calls default to the loudspeaker (you hold the phone away from
    // your ear to see the screen); audio calls default to the earpiece.
    final speakerDefault = callType == CallType.video;

    state = CallSession(
      callId: callId,
      peerUser: peer,
      callType: callType,
      direction: CallDirection.outgoing,
      phase: CallPhase.outgoingRinging,
      startedAt: DateTime.now().toUtc(),
      isSpeakerOn: speakerDefault,
    );

    // ── Voice-call audio mode ────────────────────────────────────────────────
    // Hardware volume buttons should control the in-call (STREAM_VOICE_CALL)
    // stream from now until call end. For audio calls, also acquire the
    // proximity wake lock so the screen blanks when the phone is at the ear.
    _applyVoiceCallAudioMode(callType: callType, isSpeakerOn: speakerDefault);

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
    } catch (e, st) {
      // Previously swallowed silently — the user would see the outgoing
      // screen flash for ~2 s and disappear with no explanation. Now we
      // surface the real cause in the terminal so future "call vanished"
      // bugs take a minute, not an hour.
      debugPrint('[call] startCall failed: $e\n$st');
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
      // Video calls answer on the loudspeaker (see startCall).
      isSpeakerOn: callType == CallType.video,
    );

    // ── Backgrounded fallback (Option B) ───────────────────────────────────
    // When the app is foregrounded, the global call observer in app.dart
    // pushes /call/incoming and the Flutter UI handles ringing. But when
    // the app is BACKGROUNDED with a live socket, there's no Flutter UI to
    // show — so spin up the native CallService here to get the system
    // ringtone, full-screen lock-screen activity, and accept/decline
    // notification actions. CallService dedups by callId, so if the
    // parallel FCM also fires, only one ringer runs.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final isBackgrounded = lifecycle != AppLifecycleState.resumed;
    if (isBackgrounded && callId != null && callId.isNotEmpty) {
      final offerSdp = (payload['offer'] is Map)
          ? (payload['offer'] as Map)['sdp']?.toString() ?? ''
          : (payload['offer']?.toString() ?? '');
      _bridge?.startIncomingCallService({
        'call_id': callId,
        'caller_id': peer.id,
        'caller_name': peer.name,
        'caller_avatar': peer.avatarUrl ?? '',
        'call_type': callType.name,
        'sdp_offer': offerSdp,
        // signal_token is only needed by FCM cold-start; the bridged
        // path already has the offer in [pendingOffer] on the live notifier.
        'signal_token': '',
      });
    }

    // Foreground video call: warm up the camera self-view while ringing so
    // the user can check their framing before answering. Backgrounded calls
    // are handled by the native CallService and have no Flutter UI to show it.
    if (callType == CallType.video && !isBackgrounded) {
      unawaited(_startIncomingVideoPreview());
    }

    // Missed-call timeout
    _ringTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (state?.phase == CallPhase.incomingRinging) {
        _endWithReason(EndReason.missed);
      }
    });
  }

  /// Camera self-view shown while an incoming *video* call is ringing.
  /// Camera-only (the mic is requested at accept), best-effort — if the
  /// permission is denied we simply fall back to the avatar.
  Future<void> _startIncomingVideoPreview() async {
    try {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return;
      // Bail if the ring ended / was answered while the prompt was up.
      if (state?.phase != CallPhase.incomingRinging) return;
      _webrtc ??= createWebRTCService();
      await _webrtc!.startLocalPreview(video: true);
      // Nudge the UI so the incoming screen picks up the now-live renderer.
      final s = state;
      if (s != null && s.phase == CallPhase.incomingRinging) {
        state = s.copyWith();
      }
    } catch (e) {
      debugPrint('[call] incoming video preview failed: $e');
    }
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

    // Same voice-call mode as the caller: STREAM_VOICE_CALL volume + earpiece
    // by default + proximity wake lock for audio calls.
    _applyVoiceCallAudioMode(
      callType: session.callType,
      isSpeakerOn: session.isSpeakerOn,
    );

    try {
      final iceServers =
          await ref.read(callRepositoryProvider).getTurnCredentials();

      // Reuse the service created for the pre-accept video preview (if any) so
      // we keep the already-running camera/self-view instead of reacquiring it.
      _webrtc ??= createWebRTCService();
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
    } catch (e, st) {
      debugPrint('[call] acceptCall failed: $e\n$st');
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

  /// Decline an incoming call and send a quick text reply to the caller
  /// (the "Can't talk now" style chips on the incoming-call screen).
  Future<void> declineWithMessage(String text) async {
    final session = state;
    if (session == null || session.phase != CallPhase.incomingRinging) {
      return;
    }
    final peerId = session.peerUser.id;
    // Reject the call first so the caller stops ringing immediately.
    declineCall();

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    try {
      await ref.read(messageRepositoryProvider).sendMessage(
            clientId: const Uuid().v4(),
            recipientId: peerId,
            type: MessageType.text,
            content: trimmed,
          );
    } catch (e) {
      debugPrint('[call] declineWithMessage send failed: $e');
    }
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
    // _endWithReason now centralizes WebRTC teardown — no explicit await
    // here. Keeping endCall async-signatured for API stability.
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
    // Re-evaluate proximity: when speaker is on, the phone isn't at the
    // ear, so blanking the screen would be wrong. When speaker is off
    // (earpiece), enable proximity again. Video calls never enable it.
    _refreshProximity();
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
    // We just became an audio call — enable proximity if speaker is off.
    _refreshProximity();
  }

  // ── Audio-mode helpers ───────────────────────────────────────────────────

  /// Apply STREAM_VOICE_CALL volume routing + proximity wake lock when the
  /// call begins. Called once per call from startCall/acceptCall.
  void _applyVoiceCallAudioMode({
    required CallType callType,
    required bool isSpeakerOn,
  }) {
    _bridge?.setVoiceCallVolumeStream(true);
    final wantProximity = callType == CallType.audio && !isSpeakerOn;
    _bridge?.setProximityAware(wantProximity);
  }

  /// Re-evaluate the proximity wake lock against current session state. Cheap
  /// to call — the native side is idempotent.
  void _refreshProximity() {
    final session = state;
    if (session == null) return;
    final wantProximity =
        session.callType == CallType.audio && !session.isSpeakerOn;
    _bridge?.setProximityAware(wantProximity);
  }

  /// Restore default (media) volume routing + release the proximity wake lock.
  /// Called from _endWithReason for every end path so we never leave the
  /// volume buttons wired to STREAM_VOICE_CALL after a call.
  void _releaseVoiceCallAudioMode() {
    _bridge?.setVoiceCallVolumeStream(false);
    _bridge?.setProximityAware(false);
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
      case NativeCallEventKind.hangup:
        // FIX 7: user tapped the persistent in-call notification's hang-up
        // action. Only act if we still have a live session — the event can
        // race the call ending via another path.
        if (state != null) {
          await endCall();
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
      sig.onCallRinging.listen(_handleCallRinging),
      sig.onCallError.listen(_handleCallError),
      sig.onUserBlocked.listen(_handleUserBlocked),
    ]);
  }

  /// FIX 8: a block event landed (delivered to both blocker and blocked).
  /// If the active call's peer is on either side of the block, end the call
  /// immediately. If the call was connected, also notify the peer via
  /// hangup so their end isn't stuck waiting for ICE timeout.
  void _handleUserBlocked(UserBlockedEvent event) {
    final session = state;
    if (session == null) return;
    final peerId = session.peerUser.id;
    // Match if peer is the blocker OR the blocked party. Symmetric — the
    // backend publishes to both sides, but a single event reaching this
    // app could describe either direction.
    final involvesPeer = peerId == event.blockerId || peerId == event.blockedId;
    if (!involvesPeer) return;
    debugPrint(
        '[call] user blocked (blocker=${event.blockerId} blocked=${event.blockedId}) — ending active call');
    if (session.phase == CallPhase.connected ||
        session.phase == CallPhase.reconnecting) {
      ref.read(signalingServiceProvider).emitCallHangup(
            callId: session.callId,
            to: peerId,
          );
    }
    _endWithReason(EndReason.blocked);
  }

  // ── Signaling handlers ───────────────────────────────────────────────────────

  Future<void> _handleCallAnswered(Map<String, dynamic> payload) async {
    debugPrint(
        '[signal] received call:answer (session.callId=${state?.callId} phase=${state?.phase})');
    final session = state;
    if (session == null) return;

    // Two valid phases:
    //   • outgoingRinging — original answer (the callee just picked up)
    //   • reconnecting    — answer to OUR ice-restart offer (caller-only,
    //     since only the caller initiates restart now). Previously this
    //     branch was dropped, so successful peer-side restarts never made
    //     it back through and the call always died at the 30 s fail-timer.
    final isOriginalAnswer = session.phase == CallPhase.outgoingRinging;
    final isRestartAnswer = session.phase == CallPhase.reconnecting ||
        session.phase == CallPhase.connecting;
    if (!isOriginalAnswer && !isRestartAnswer) {
      return;
    }

    if (isOriginalAnswer) {
      _ringTimeoutTimer?.cancel();
      _ringTimeoutTimer = null;
      // Stop the ringback the instant the callee picks up — otherwise the
      // tone keeps playing under the live audio for a beat.
      _ringback?.stop();
      state = session.copyWith(phase: CallPhase.connecting);
    }

    try {
      final answer =
          payload['answer'] as Map<String, dynamic>? ?? payload;
      await _webrtc?.setRemoteDescription(answer);
    } catch (e, st) {
      debugPrint('[call] setRemoteDescription (answer) failed: $e\n$st');
      // For an original answer, the call hasn't connected — fail it. For a
      // restart answer, the OLD media path may still be alive; let the
      // fail-timer (or eventual ICE success) decide instead of immediately
      // killing a recoverable call.
      if (isOriginalAnswer) {
        _endWithReason(EndReason.failed);
      }
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
    } catch (e) {
      // Don't bring down the call for a single bad candidate, but log so
      // a repeating ICE-add failure (which would mean media never connects)
      // is visible during debugging.
      debugPrint('[call] addIceCandidate failed: $e');
    }
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
    } catch (e) {
      debugPrint('[call] ICE restart answer failed: $e');
    }
  }

  // Inbound signal handlers — log every one so we can see the backend's
  // decisions in the terminal. _endWithReason centralizes teardown, so we
  // no longer have to call _teardown() manually here.

  void _handleRemoteHangup(CallHangupEvent event) {
    debugPrint(
        '[signal] received call:hangup (callId=${event.callId} from=${event.fromUserId})');
    final session = state;
    if (session == null || session.callId != event.callId) {
      return;
    }
    _endWithReason(EndReason.hungUp);
  }

  void _handleCallRejected(CallRejectedEvent event) {
    debugPrint(
        '[signal] received call:rejected (callId=${event.callId} from=${event.fromUserId})');
    final session = state;
    if (session == null || session.callId != event.callId) {
      return;
    }
    _endWithReason(EndReason.declined);
  }

  void _handleCallBusy(CallBusyEvent event) {
    debugPrint('[signal] received call:busy (callId=${event.callId})');
    final session = state;
    if (session == null || session.callId != event.callId) {
      return;
    }
    _endWithReason(EndReason.busy);
  }

  void _handleCallMissed(CallMissedEvent event) {
    debugPrint('[signal] received call:missed (callId=${event.callId})');
    final session = state;
    if (session == null || session.callId != event.callId) {
      return;
    }
    _endWithReason(EndReason.missed);
  }

  /// Positive backend ack — the offer reached the callee (socket or FCM).
  /// We flip [CallSession.peerRinging] so the UI can switch its status
  /// label from "Calling" to "Ringing", and start the local ringback tone
  /// so the user *hears* something while waiting for an answer.
  void _handleCallRinging(CallRingingEvent event) {
    debugPrint('[signal] received call:ringing (callId=${event.callId}) — '
        'offer reached callee, waiting for answer');
    final session = state;
    if (session == null || session.callId != event.callId) return;
    if (session.phase != CallPhase.outgoingRinging) return;
    state = session.copyWith(peerRinging: true);
    // Lazy-create and start the ringback. Failures here are non-fatal:
    // the call still works without audible ringback.
    (_ringback ??= RingbackPlayer()).start();
  }

  /// Backend rejected the call attempt outright — for example "You can only
  /// call your contacts", "Invalid target", rate-limited, etc. Previously
  /// the Dart side wasn't listening for this at all, so the user would
  /// sit on the outgoing-call screen until our own 45 s timeout fired with
  /// no idea why the call wasn't going through.
  void _handleCallError(CallErrorEvent event) {
    debugPrint('[signal] received call:error: ${event.message}');
    final session = state;
    if (session == null) return;
    // Only react during call setup — if we're already connected, an
    // unrelated error event shouldn't terminate an active call.
    if (session.phase != CallPhase.outgoingRinging &&
        session.phase != CallPhase.incomingRinging &&
        session.phase != CallPhase.connecting) {
      return;
    }
    // Stash the human message so the outgoing screen can show it before
    // the screen pops.
    state = session.copyWith(errorMessage: event.message);
    _endWithReason(EndReason.failed);
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
          // Route audio now that media is flowing. WebRTC.initialize() forces
          // the earpiece on setup; re-assert the session's choice here so video
          // calls actually come out of the loudspeaker.
          _webrtc?.setSpeakerphone(session.isSpeakerOn).catchError((_) {});
          _startQualityMonitor();
          _startDurationTick();
          // Ignore errors on platforms where wakelock is unavailable (tests, web).
          WakelockPlus.enable().catchError((_) {});
          // FIX 7: spin up the active-call foreground service so the call
          // survives backgrounding / screen lock. The notification has a
          // hang-up action that routes back through CallActionReceiver →
          // NativeCallBus → _handleNativeEvent(hangup) → endCall().
          _bridge?.startActiveCallService(
            callId: session.callId,
            peerName: session.peerUser.name,
            callType: session.callType.name,
          );
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
    // ── Glare avoidance ─────────────────────────────────────────────────────
    // ICE failures on a bad network typically fire on BOTH peers at almost
    // the same instant. If both sides create restart offers simultaneously,
    // each gets a remote restart-offer back while sitting in
    // have-local-offer → setRemoteDescription throws
    //   "Called in wrong state: have-local-offer"
    // and ICE never recovers. By convention, only the caller (outgoing
    // direction) drives the restart; the callee just waits to receive the
    // restart offer via call:ice_restart and answers it.
    if (session.direction != CallDirection.outgoing) {
      debugPrint(
          '[call] _performIceRestart: skipping (we are callee — waiting for caller restart)');
      return;
    }
    _webrtc!.createIceRestartOffer().then((offer) {
      ref.read(signalingServiceProvider).emitCallIceRestart(
            callId: session.callId,
            to: session.peerUser.id,
            offer: offer,
          );
    }).catchError((e) {
      debugPrint('[call] createIceRestartOffer failed: $e');
    });
  }

  void _startFailTimer() {
    // ── FIX 4: re-entrancy guard ────────────────────────────────────────────
    // _handleConnectionState and _handleIceConnectionState can each fire
    // _startReconnectSequence, which calls _startFailTimer. WebRTC may
    // also emit several `failed` events in quick succession during a bad
    // network spell. Without this guard, each call cancels and restarts
    // the 30 s countdown — a persistently bad connection would keep
    // resetting forever and the call would never end. The countdown should
    // only begin once and run to completion.
    if (_failTimer?.isActive ?? false) {
      return;
    }
    _failTimer = Timer(const Duration(seconds: 30), () {
      // ── FIX 3: also act on `connecting` ─────────────────────────────────
      // Original guard was `phase == reconnecting`. If ICE fails before the
      // call ever reaches connected (callee answered but ICE handshake
      // stalls), the phase can stay in `connecting` rather than transition
      // to `reconnecting` — and the timer would fire as a no-op, leaving
      // the user stuck on the connecting screen. Accept both phases.
      final phase = state?.phase;
      if (phase == CallPhase.reconnecting || phase == CallPhase.connecting) {
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
    // Sample once immediately so the badge reflects the real connection right
    // after connecting instead of sitting on the default "good"; then keep it
    // live on a 500ms cadence — fast enough to drive the speaking indicator.
    _sampleQuality();
    _qualityTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _sampleQuality(),
    );
  }

  Future<void> _sampleQuality() async {
    final session = state;
    if (session == null || !session.isActive || _webrtc == null) {
      return;
    }
    final stats = await _webrtc!.getStats();
    state = session.copyWith(
      quality: stats.level,
      localAudioLevel: stats.localAudioLevel,
      remoteAudioLevel: stats.remoteAudioLevel,
    );

    // Suggest audio-only if video FPS collapses
    if (session.callType == CallType.video &&
        !session.isCameraOff &&
        stats.videoFps != null &&
        stats.videoFps! < 5 &&
        !session.showSwitchToAudioPrompt) {
      state = state?.copyWith(showSwitchToAudioPrompt: true);
    }
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

  /// Single canonical end-of-call path. Always tears down the WebRTC peer
  /// connection and all timers before transitioning the session to `ended`.
  /// Callers must NOT skip this — previously several paths called
  /// `_endWithReason` directly without `_teardown`, leaking the peer
  /// connection (WebRTC kept renderer logs going for the rest of the app's
  /// lifetime after a missed call / ring timeout / failed init).
  ///
  /// Fire-and-forget at the call site; the state transitions synchronously
  /// so the UI's ref.listen fires before the (async) WebRTC dispose returns.
  void _endWithReason(EndReason reason) {
    final session = state;

    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _cancelReconnectTimers();
    _qualityTimer?.cancel();
    _qualityTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    // Silence the ringback whatever the end reason — timeout, missed,
    // rejected, hung up, etc. all need the loop to stop immediately.
    _ringback?.stop();

    // Drop the dedup record so a future call to the same peer can ring again.
    final endingId = session?.callId;
    if (endingId != null) _seenIncomingIds.remove(endingId);

    debugPrint('[call] ending with reason=$reason (callId=$endingId)');

    // ── FIX 6: persist unexpectedly-interrupted connected calls ──────────────
    // If the call had actually connected (connectedAt is set) and the end
    // wasn't a clean hangup, persist a minimal record so the next app
    // launch can reconcile with the backend. ref.onDispose doesn't fire
    // on force-kill, so this is the best window we get to write to disk
    // — and even for `interrupted` (audio focus loss), the user might
    // immediately switch back and we want a durable record.
    if (session != null &&
        session.connectedAt != null &&
        _isInterruptedEnd(reason)) {
      _persistInterruptedCall(session, reason);
    }

    state = session?.copyWith(phase: CallPhase.ended, endReason: reason);

    // Restore default volume-button routing and release the proximity wake
    // lock. Has to run on every end path; if we forget here, the volume
    // buttons stay wired to STREAM_VOICE_CALL after the call (so changing
    // media volume becomes impossible until app restart).
    _releaseVoiceCallAudioMode();

    // Tear down WebRTC. Don't await — keep _endWithReason effectively
    // synchronous so timer/Listener callers don't have to. WebRTC dispose
    // is async only because Dart bindings make it so; nothing depends on
    // its completion ordering here.
    if (_webrtc != null) {
      _teardown().catchError((e) {
        debugPrint('[call] teardown after $reason threw: $e');
      });
    }

    // Clear to null after a brief delay so the UI can show "ended" state.
    Future.delayed(const Duration(seconds: 2), () {
      if (state?.phase == CallPhase.ended ||
          state?.phase == CallPhase.failed) {
        state = null;
      }
    });
  }

  /// True for end reasons that suggest the call was cut off rather than
  /// hung up cleanly — and therefore deserves a reconciliation entry.
  static bool _isInterruptedEnd(EndReason reason) {
    switch (reason) {
      case EndReason.interrupted:
      case EndReason.forceKilled:
      case EndReason.failed:
      case EndReason.blocked:
        return true;
      case EndReason.hungUp:
      case EndReason.declined:
      case EndReason.rejected:
      case EndReason.busy:
      case EndReason.missed:
      case EndReason.timeout:
        return false;
    }
  }

  /// Stash a minimal record on disk so the next app launch can sync it to
  /// the backend via [CallRepository.syncInterruptedCalls]. Best-effort —
  /// failure to persist is logged but doesn't block the end path.
  void _persistInterruptedCall(CallSession session, EndReason reason) {
    final endedAt = DateTime.now().toUtc();
    final durationSeconds = session.connectedAt == null
        ? 0
        : endedAt.difference(session.connectedAt!).inSeconds;
    ref
        .read(callRepositoryProvider)
        .stashInterruptedCall(
          callId: session.callId,
          peerUserId: session.peerUser.id,
          callType: session.callType.name,
          direction: session.direction.name,
          startedAt: session.startedAt,
          connectedAt: session.connectedAt,
          endedAt: endedAt,
          durationSeconds: durationSeconds,
          reason: reason.name,
        )
        .catchError((e) {
      debugPrint('[call] stashInterruptedCall failed (non-fatal): $e');
    });
  }

  Future<void> _teardown() async {
    _qualityTimer?.cancel();
    _qualityTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    // Ignore errors on platforms where wakelock is unavailable (tests, web).
    WakelockPlus.disable().catchError((_) {});
    // FIX 7: stop the persistent in-call notification + foreground service.
    // Always safe to call even if it was never started.
    _bridge?.stopActiveCallService();
    await _webrtc?.dispose();
    _webrtc = null;
  }

  void _cleanup() {
    _isAlive = false;
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
    _ringback?.dispose();
    _ringback = null;
  }
}

/// The single active call session. Null when no call is in progress.
final callSessionProvider =
    NotifierProvider<CallNotifier, CallSession?>(CallNotifier.new);

/// True while a full-screen call UI (active / video) is on top. The global
/// "return to call" overlay uses this to know when to show itself — it appears
/// only when a call is live but the user has navigated away from the call
/// screen. Set by ActiveCallScreen / VideoCallScreen on mount/unmount.
final callScreenVisibleProvider =
    StateProvider<bool>((_) => false);

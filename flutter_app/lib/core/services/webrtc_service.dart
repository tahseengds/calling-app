import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/call_utils.dart';

// ── Own enums (no direct flutter_webrtc dependency in callers) ────────────────

enum WebRTCIceState {
  checking,
  connected,
  completed,
  disconnected,
  failed,
  closed,
  other,
}

enum WebRTCConnectionState {
  connecting,
  connected,
  disconnected,
  failed,
  closed,
  other,
}

// ── Quality stats ─────────────────────────────────────────────────────────────

/// Quality snapshot derived from `getStats()`.
class CallQualityStats {
  final double? videoFps;
  final double? packetLossPercent;
  final int? rttMs;

  /// Normalised audio levels (0.0–1.0) for the speaking indicator.
  /// [localAudioLevel] is our own mic, [remoteAudioLevel] is the peer.
  final double localAudioLevel;
  final double remoteAudioLevel;

  const CallQualityStats({
    this.videoFps,
    this.packetLossPercent,
    this.rttMs,
    this.localAudioLevel = 0.0,
    this.remoteAudioLevel = 0.0,
  });

  /// Coarse level used by the quality badge: 'good' | 'medium' | 'poor'.
  String get level {
    if (packetLossPercent != null && packetLossPercent! > 10) {
      return 'poor';
    }
    if ((videoFps != null && videoFps! < 10) ||
        (packetLossPercent != null && packetLossPercent! > 5)) {
      return 'medium';
    }
    return 'good';
  }
}

// ── Abstract interface ────────────────────────────────────────────────────────

/// Abstract WebRTC service — swap with a mock in unit tests.
abstract class WebRTCService {
  RTCVideoRenderer get localRenderer;
  RTCVideoRenderer get remoteRenderer;

  bool get isMicOn;
  bool get isCameraOn;

  /// Initialise the peer connection with the supplied ICE server configs.
  Future<void> initialize({required List<Map<String, dynamic>> iceServers});

  /// Start a local camera self-view *before* a call is connected, without
  /// requiring a peer connection. Used to show the user their own video while
  /// an incoming call is ringing (so they can check framing before answering).
  /// Safe to call before [initialize]; the captured stream is reused when the
  /// call is later set up.
  Future<void> startLocalPreview({required bool video});

  /// Create an offer SDP (caller side). Returns `{'sdp': ..., 'type': ...}`.
  Future<Map<String, dynamic>> createOffer({required bool videoEnabled});

  /// Set the remote answer (caller side) after receiving `call:answered`.
  Future<void> setRemoteDescription(Map<String, dynamic> sdpMap);

  /// Create an answer SDP (callee side). [remoteOfferMap] is the offer from
  /// the payload. Returns `{'sdp': ..., 'type': ...}`.
  Future<Map<String, dynamic>> createAnswer(
    Map<String, dynamic> remoteOfferMap, {
    required bool videoEnabled,
  });

  /// Add a trickle ICE candidate from the remote peer.
  Future<void> addIceCandidate(Map<String, dynamic> candidateMap);

  /// Create a new offer with `iceRestart: true` for reconnection.
  Future<Map<String, dynamic>> createIceRestartOffer();

  /// Apply a remote ICE-restart answer.
  Future<void> applyIceRestartAnswer(Map<String, dynamic> sdpMap);

  // ── Callbacks ──────────────────────────────────────────────────────────────

  void onIceCandidate(
      void Function(Map<String, dynamic> candidateMap) callback);
  void onConnectionStateChange(void Function(WebRTCConnectionState) callback);
  void onIceConnectionStateChange(void Function(WebRTCIceState) callback);

  // ── Track controls ─────────────────────────────────────────────────────────

  Future<void> toggleMic();
  Future<void> toggleCamera();
  Future<void> switchCamera();
  Future<void> setSpeakerphone(bool enabled);

  // ── Stats ──────────────────────────────────────────────────────────────────

  Future<CallQualityStats> getStats();

  // ── Teardown ───────────────────────────────────────────────────────────────

  Future<void> dispose();
}

// ── Production implementation ─────────────────────────────────────────────────

class WebRTCServiceImpl implements WebRTCService {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _renderersInitialized = false;
  bool _tracksAdded = false;

  void Function(Map<String, dynamic>)? _onIceCandidate;
  void Function(WebRTCConnectionState)? _onConnectionStateChange;
  void Function(WebRTCIceState)? _onIceConnectionStateChange;

  @override
  RTCVideoRenderer get localRenderer => _localRenderer;
  @override
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;
  @override
  bool get isMicOn => _isMicOn;
  @override
  bool get isCameraOn => _isCameraOn;

  @override
  Future<void> initialize(
      {required List<Map<String, dynamic>> iceServers}) async {
    await _ensureRenderers();

    final configuration = <String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };

    _pc = await createPeerConnection(configuration);

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _onIceCandidate?.call({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _pc!.onConnectionState = (state) {
      _onConnectionStateChange?.call(_mapConnectionState(state));
    };

    _pc!.onIceConnectionState = (state) {
      _onIceConnectionStateChange?.call(_mapIceState(state));
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteRenderer.srcObject = _remoteStream;
      }
    };

    // VoIP default: route to the earpiece, not the loudspeaker. Without this
    // explicit call, flutter_webrtc on Android can leave the previous audio
    // routing state (e.g. speakerphone left on by another app or by the
    // ringback we just played) which produces a "speakerphone-by-default"
    // experience that no other phone app has. Users toggle speakerphone
    // explicitly via the in-call control.
    //
    // Video callers override this to true via setSpeakerphone(true) — the
    // call screen passes session.isSpeakerOn straight through.
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (e) {
      // Older flutter_webrtc on some OEMs throws when called before a media
      // stream exists. Non-fatal — the next setSpeakerphone() will set it.
      debugPrint('[webrtc] initial setSpeakerphoneOn(false) failed: $e');
    }
  }

  @override
  Future<void> startLocalPreview({required bool video}) async {
    await _ensureRenderers();
    // Video-only for the preview so we don't pop a mic permission prompt
    // while the call is still ringing — the mic is acquired at accept time.
    await _ensureLocalStream(audio: false, video: video);
  }

  @override
  Future<Map<String, dynamic>> createOffer(
      {required bool videoEnabled}) async {
    assert(_pc != null, 'Call initialize() before createOffer()');
    await _ensureLocalStream(audio: true, video: videoEnabled);
    await _addLocalTracksToPc();

    // Match the constraints to the actual call type. Previously this always
    // asked for both audio AND video, which made audio-only offers carry an
    // unused video m-section. That wastes SDP/ICE work and, worse, the
    // bitrate shaper in [_shapeSdp] would cap a non-existent video stream
    // — harmless but noisy on the wire.
    final constraints = <String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': videoEnabled,
    };
    final raw = await _pc!.createOffer(constraints);
    final shapedSdp = _shapeSdp(raw.sdp ?? '', videoEnabled);
    final shaped = RTCSessionDescription(shapedSdp, raw.type);
    await _pc!.setLocalDescription(shaped);
    return {'sdp': shaped.sdp, 'type': shaped.type};
  }

  @override
  Future<void> setRemoteDescription(Map<String, dynamic> sdpMap) async {
    // Defensive: caller may hand us a partial map (e.g. FCM-normalized
    // payload missing 'type'). Previously `as String` would throw on null
    // and bubble up as an unhandled-async error from the call:answered /
    // call:ice_restart handlers, dropping the call without explanation.
    final sdp = sdpMap['sdp'] as String?;
    final type = sdpMap['type'] as String?;
    if (sdp == null || sdp.isEmpty || type == null || type.isEmpty) {
      throw StateError(
          'setRemoteDescription: malformed SDP map (sdp=${sdp?.length ?? 0} chars, type=$type)');
    }
    final desc = RTCSessionDescription(sdp, type);
    await _pc!.setRemoteDescription(desc);
  }

  @override
  Future<Map<String, dynamic>> createAnswer(
    Map<String, dynamic> remoteOfferMap, {
    required bool videoEnabled,
  }) async {
    assert(_pc != null, 'Call initialize() before createAnswer()');

    // Set the remote offer first
    await setRemoteDescription(remoteOfferMap);
    await _ensureLocalStream(audio: true, video: videoEnabled);
    await _addLocalTracksToPc();

    final answerConstraints = <String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': videoEnabled,
    };
    final raw = await _pc!.createAnswer(answerConstraints);
    final shapedSdp = _shapeSdp(raw.sdp ?? '', videoEnabled);
    final shaped = RTCSessionDescription(shapedSdp, raw.type);
    await _pc!.setLocalDescription(shaped);
    return {'sdp': shaped.sdp, 'type': shaped.type};
  }

  @override
  Future<void> addIceCandidate(Map<String, dynamic> candidateMap) async {
    final candidate = RTCIceCandidate(
      candidateMap['candidate'] as String? ?? '',
      candidateMap['sdpMid'] as String?,
      candidateMap['sdpMLineIndex'] as int?,
    );
    await _pc?.addCandidate(candidate);
  }

  @override
  Future<Map<String, dynamic>> createIceRestartOffer() async {
    final pc = _pc;
    if (pc == null) {
      throw StateError('createIceRestartOffer: peer connection is null');
    }
    // Guard: only create a restart offer when the signaling state is
    // `stable`. If we're already in `have-local-offer` (or somewhere else
    // mid-handshake), creating another offer produces the WEBRTC
    // "Called in wrong state: have-local-offer" error that we observed
    // crashing live ICE-restart flows. The callee will skip restart
    // entirely (see CallNotifier._performIceRestart) so glare can't happen
    // — but this still protects against the caller racing itself across
    // multiple `failed` events.
    final sigState = await pc.getSignalingState();
    if (sigState != RTCSignalingState.RTCSignalingStateStable) {
      throw StateError(
          'createIceRestartOffer: signaling state is $sigState (need stable)');
    }
    final raw = await pc.createOffer(<String, dynamic>{'iceRestart': true});
    await pc.setLocalDescription(raw);
    return {'sdp': raw.sdp, 'type': raw.type};
  }

  @override
  Future<void> applyIceRestartAnswer(Map<String, dynamic> sdpMap) =>
      setRemoteDescription(sdpMap);

  @override
  void onIceCandidate(
      void Function(Map<String, dynamic> candidateMap) callback) {
    _onIceCandidate = callback;
  }

  @override
  void onConnectionStateChange(
      void Function(WebRTCConnectionState) callback) {
    _onConnectionStateChange = callback;
  }

  @override
  void onIceConnectionStateChange(
      void Function(WebRTCIceState) callback) {
    _onIceConnectionStateChange = callback;
  }

  @override
  Future<void> toggleMic() async {
    _isMicOn = !_isMicOn;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _isMicOn);
  }

  @override
  Future<void> toggleCamera() async {
    _isCameraOn = !_isCameraOn;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _isCameraOn);
  }

  @override
  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
    }
  }

  @override
  Future<void> setSpeakerphone(bool enabled) async {
    await Helper.setSpeakerphoneOn(enabled);
  }

  @override
  Future<CallQualityStats> getStats() async {
    if (_pc == null) {
      return const CallQualityStats();
    }
    try {
      final stats = await _pc!.getStats();
      double? fps;
      double? lossPercent;
      int? rttMs;
      double localAudio = 0.0;
      double remoteAudio = 0.0;

      for (final report in stats) {
        if (report.type == 'inbound-rtp' &&
            report.values['kind'] == 'video') {
          fps = (report.values['framesPerSecond'] as num?)?.toDouble();
          final packetsLost =
              (report.values['packetsLost'] as num?)?.toInt() ?? 0;
          final packetsReceived =
              (report.values['packetsReceived'] as num?)?.toInt() ?? 1;
          final total = packetsLost + packetsReceived;
          lossPercent = total > 0 ? packetsLost / total * 100 : 0.0;
        }
        // Remote party's voice level (what we hear).
        if (report.type == 'inbound-rtp' &&
            report.values['kind'] == 'audio') {
          final lvl = (report.values['audioLevel'] as num?)?.toDouble();
          if (lvl != null) remoteAudio = lvl.clamp(0.0, 1.0);
        }
        // Our own mic level (what we send).
        if (report.type == 'media-source' &&
            report.values['kind'] == 'audio') {
          final lvl = (report.values['audioLevel'] as num?)?.toDouble();
          if (lvl != null) localAudio = lvl.clamp(0.0, 1.0);
        }
        if (report.type == 'remote-inbound-rtp') {
          final rttSec =
              (report.values['roundTripTime'] as num?)?.toDouble() ?? 0.0;
          rttMs = (rttSec * 1000).toInt();
        }
      }

      return CallQualityStats(
        videoFps: fps,
        packetLossPercent: lossPercent,
        rttMs: rttMs,
        localAudioLevel: localAudio,
        remoteAudioLevel: remoteAudio,
      );
    } catch (_) {
      return const CallQualityStats();
    }
  }

  @override
  Future<void> dispose() async {
    _localStream?.getTracks().forEach((t) => t.stop());
    _remoteStream?.getTracks().forEach((t) => t.stop());
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    await _pc?.close();
    _pc = null;
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
    _renderersInitialized = false;
    _tracksAdded = false;
    _localStream = null;
    _remoteStream = null;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _ensureRenderers() async {
    if (_renderersInitialized) return;
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _renderersInitialized = true;
  }

  static const Map<String, dynamic> _audioConstraints = {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
  };
  static const Map<String, dynamic> _videoConstraints = {
    'facingMode': 'user',
    'width': 640,
    'height': 480,
  };

  /// Ensure the local stream exists and carries the requested track kinds.
  /// Handles the incremental case where a video-only preview stream already
  /// exists and we now need to add the mic at accept time.
  Future<void> _ensureLocalStream(
      {required bool audio, required bool video}) async {
    if (_localStream == null) {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': audio ? _audioConstraints : false,
        'video': video ? _videoConstraints : false,
      });
      _localRenderer.srcObject = _localStream;
      return;
    }

    // Stream already exists (e.g. from a pre-accept preview) — add any track
    // kinds that are now required but missing.
    if (audio && _localStream!.getAudioTracks().isEmpty) {
      final extra = await navigator.mediaDevices
          .getUserMedia({'audio': _audioConstraints, 'video': false});
      for (final t in extra.getAudioTracks()) {
        await _localStream!.addTrack(t);
      }
    }
    if (video && _localStream!.getVideoTracks().isEmpty) {
      final extra = await navigator.mediaDevices
          .getUserMedia({'audio': false, 'video': _videoConstraints});
      for (final t in extra.getVideoTracks()) {
        await _localStream!.addTrack(t);
      }
      _localRenderer.srcObject = _localStream;
    }
  }

  /// Add the current local tracks to the peer connection exactly once.
  Future<void> _addLocalTracksToPc() async {
    if (_pc == null || _tracksAdded || _localStream == null) return;
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    _tracksAdded = true;
  }

  /// Apply SDP bitrate caps and codec preferences.
  String _shapeSdp(String sdp, bool videoEnabled) {
    var result = applyBitrateCap(sdp,
        videoKbps: 800, audioKbps: 50);
    result = preferCodecs(result);
    return result;
  }

  static WebRTCIceState _mapIceState(RTCIceConnectionState state) {
    return switch (state) {
      RTCIceConnectionState.RTCIceConnectionStateChecking =>
        WebRTCIceState.checking,
      RTCIceConnectionState.RTCIceConnectionStateConnected =>
        WebRTCIceState.connected,
      RTCIceConnectionState.RTCIceConnectionStateCompleted =>
        WebRTCIceState.completed,
      RTCIceConnectionState.RTCIceConnectionStateDisconnected =>
        WebRTCIceState.disconnected,
      RTCIceConnectionState.RTCIceConnectionStateFailed =>
        WebRTCIceState.failed,
      RTCIceConnectionState.RTCIceConnectionStateClosed =>
        WebRTCIceState.closed,
      _ => WebRTCIceState.other,
    };
  }

  static WebRTCConnectionState _mapConnectionState(
      RTCPeerConnectionState state) {
    return switch (state) {
      RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
        WebRTCConnectionState.connecting,
      RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
        WebRTCConnectionState.connected,
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
        WebRTCConnectionState.disconnected,
      RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
        WebRTCConnectionState.failed,
      RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
        WebRTCConnectionState.closed,
      _ => WebRTCConnectionState.other,
    };
  }
}

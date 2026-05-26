import 'dart:async';
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

  const CallQualityStats({this.videoFps, this.packetLossPercent, this.rttMs});

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
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

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
  }

  @override
  Future<Map<String, dynamic>> createOffer(
      {required bool videoEnabled}) async {
    assert(_pc != null, 'Call initialize() before createOffer()');
    await _acquireLocalMedia(videoEnabled: videoEnabled);

    final constraints = <String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    };
    final raw = await _pc!.createOffer(constraints);
    final shapedSdp = _shapeSdp(raw.sdp ?? '', videoEnabled);
    final shaped = RTCSessionDescription(shapedSdp, raw.type);
    await _pc!.setLocalDescription(shaped);
    return {'sdp': shaped.sdp, 'type': shaped.type};
  }

  @override
  Future<void> setRemoteDescription(Map<String, dynamic> sdpMap) async {
    final desc = RTCSessionDescription(
      sdpMap['sdp'] as String,
      sdpMap['type'] as String,
    );
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
    await _acquireLocalMedia(videoEnabled: videoEnabled);

    final answerConstraints = <String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
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
    final raw =
        await _pc!.createOffer(<String, dynamic>{'iceRestart': true});
    await _pc!.setLocalDescription(raw);
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
    _localStream = null;
    _remoteStream = null;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _acquireLocalMedia({required bool videoEnabled}) async {
    if (_localStream != null) {
      return; // already acquired
    }

    final constraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': videoEnabled
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    _localRenderer.srcObject = _localStream;

    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
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

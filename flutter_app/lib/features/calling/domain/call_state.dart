// Domain models and enums for the calling feature (Prompt 14).

enum CallPhase {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  connected,
  reconnecting,
  ended,
  failed,
}

enum CallType { audio, video }

enum CallDirection { outgoing, incoming }

enum EndReason {
  hungUp,   // normal hang-up by either side
  declined, // callee declined (outgoing view)
  rejected, // we rejected (incoming view)
  busy,     // callee is busy
  missed,   // ring timeout without answer (incoming)
  failed,   // ICE / connection failure
  timeout,  // ring timeout without answer (outgoing)
}

// ── PeerUser ────────────────────────────────────────────────────────────────

class PeerUser {
  final String id;
  final String name;
  final String? avatarUrl;

  const PeerUser({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  factory PeerUser.fromJson(Map<String, dynamic> json) => PeerUser(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ??
            json['display_name'] as String? ??
            'Unknown',
        avatarUrl: json['avatar_url'] as String?,
      );
}

// ── CallRecord ──────────────────────────────────────────────────────────────

/// A historical call record returned by the API and cached in Drift.
class CallRecord {
  final String id;
  final PeerUser peerUser;
  final CallType callType;
  final CallDirection direction;
  final String status; // 'completed' | 'missed' | 'rejected' | 'failed'
  final DateTime startedAt;
  final int? durationSeconds;

  const CallRecord({
    required this.id,
    required this.peerUser,
    required this.callType,
    required this.direction,
    required this.status,
    required this.startedAt,
    this.durationSeconds,
  });

  bool get isMissed => status == 'missed';

  factory CallRecord.fromJson(Map<String, dynamic> json) {
    final otherUser =
        json['other_user'] as Map<String, dynamic>? ?? const {};
    return CallRecord(
      id: json['id'] as String,
      peerUser: PeerUser.fromJson(otherUser),
      callType: (json['call_type'] as String?) == 'video'
          ? CallType.video
          : CallType.audio,
      direction: (json['direction'] as String?) == 'outgoing'
          ? CallDirection.outgoing
          : CallDirection.incoming,
      status: json['status'] as String? ?? 'completed',
      startedAt: DateTime.parse(json['started_at'] as String),
      durationSeconds: json['duration_seconds'] as int?,
    );
  }
}

// ── CallSession ─────────────────────────────────────────────────────────────

/// Live call session — the single source of truth while a call is in progress.
class CallSession {
  final String callId;
  final PeerUser peerUser;
  final CallType callType;
  final CallDirection direction;
  final CallPhase phase;
  final bool isMuted;
  final bool isCameraOff;
  final bool isSpeakerOn;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final EndReason? endReason;

  /// Coarse quality level: 'good' | 'medium' | 'poor'.
  final String quality;

  /// When true the UI shows a "Switch to audio only?" prompt.
  final bool showSwitchToAudioPrompt;

  /// Stored for the callee to create an answer; non-null when
  /// phase == incomingRinging.
  final Map<String, dynamic>? pendingOffer;

  const CallSession({
    required this.callId,
    required this.peerUser,
    required this.callType,
    required this.direction,
    required this.phase,
    this.isMuted = false,
    this.isCameraOff = false,
    this.isSpeakerOn = false,
    required this.startedAt,
    this.connectedAt,
    this.endReason,
    this.quality = 'good',
    this.showSwitchToAudioPrompt = false,
    this.pendingOffer,
  });

  /// Wall-clock seconds since ICE connected.
  int get durationSeconds {
    if (connectedAt == null) {
      return 0;
    }
    return DateTime.now().difference(connectedAt!).inSeconds;
  }

  bool get isActive =>
      phase == CallPhase.connected || phase == CallPhase.reconnecting;

  CallSession copyWith({
    CallPhase? phase,
    CallType? callType,
    bool? isMuted,
    bool? isCameraOff,
    bool? isSpeakerOn,
    DateTime? connectedAt,
    EndReason? endReason,
    String? quality,
    bool? showSwitchToAudioPrompt,
    Map<String, dynamic>? pendingOffer,
  }) =>
      CallSession(
        callId: callId,
        peerUser: peerUser,
        callType: callType ?? this.callType,
        direction: direction,
        phase: phase ?? this.phase,
        isMuted: isMuted ?? this.isMuted,
        isCameraOff: isCameraOff ?? this.isCameraOff,
        isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
        startedAt: startedAt,
        connectedAt: connectedAt ?? this.connectedAt,
        endReason: endReason ?? this.endReason,
        quality: quality ?? this.quality,
        showSwitchToAudioPrompt:
            showSwitchToAudioPrompt ?? this.showSwitchToAudioPrompt,
        pendingOffer: pendingOffer ?? this.pendingOffer,
      );
}

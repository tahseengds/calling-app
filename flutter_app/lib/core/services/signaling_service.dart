import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import '../auth/auth_token.dart';
import '../config/app_config.dart';

// ── Event payloads ────────────────────────────────────────────────────────────

class MessageNewEvent {
  final Map<String, dynamic> json;
  const MessageNewEvent(this.json);
}

class MessageAckEvent {
  final String messageId;
  final String status; // 'delivered' | 'read'
  const MessageAckEvent({required this.messageId, required this.status});
}

class MessageDeletedEvent {
  final String messageId;
  final String conversationId;
  const MessageDeletedEvent(
      {required this.messageId, required this.conversationId});
}

/// Pushed when another user adds or removes a reaction on a message we can
/// see. The full post-mutation summary list is included so the receiver can
/// overwrite local state without recomputing — the actor's HTTP response
/// covers their own clients.
class MessageReactionEvent {
  final String messageId;
  final String conversationId;
  final String actorUserId;
  final String emoji;
  final bool added; // false ⇒ removed
  final List<Map<String, dynamic>> reactionsJson;

  const MessageReactionEvent({
    required this.messageId,
    required this.conversationId,
    required this.actorUserId,
    required this.emoji,
    required this.added,
    required this.reactionsJson,
  });
}

class TypingEvent {
  final String fromUserId;
  final String conversationId;
  final bool isTyping;
  const TypingEvent(
      {required this.fromUserId,
      required this.conversationId,
      required this.isTyping});
}

class PresenceEvent {
  final String userId;
  final String status; // 'online' | 'offline'
  final DateTime? lastSeen;
  const PresenceEvent(
      {required this.userId, required this.status, this.lastSeen});
}

// ── Call event payloads ────────────────────────────────────────────────────────

class CallIncomingEvent {
  final Map<String, dynamic> json;
  const CallIncomingEvent(this.json);
}

class CallAnsweredEvent {
  final Map<String, dynamic> json;
  const CallAnsweredEvent(this.json);
}

class CallIceEvent {
  final Map<String, dynamic> json;
  const CallIceEvent(this.json);
}

class CallIceRestartEvent {
  final Map<String, dynamic> json;
  const CallIceRestartEvent(this.json);
}

class CallHangupEvent {
  final String callId;
  final String fromUserId;
  const CallHangupEvent({required this.callId, required this.fromUserId});
}

class CallRejectedEvent {
  final String callId;
  final String fromUserId;
  const CallRejectedEvent({required this.callId, required this.fromUserId});
}

class CallBusyEvent {
  final String callId;
  const CallBusyEvent({required this.callId});
}

class CallMissedEvent {
  final String callId;
  const CallMissedEvent({required this.callId});
}

/// Backend acks a successful `call:initiate` — the offer reached the callee
/// (either via socket or FCM). Caller-side optional positive signal.
class CallRingingEvent {
  final String callId;
  const CallRingingEvent({required this.callId});
}

/// Backend rejected the call attempt for a reason that isn't busy/missed/
/// hangup — e.g. "not your contact", "invalid target", rate-limited, etc.
/// Surfaces a human message that the UI should show.
class CallErrorEvent {
  final String message;
  const CallErrorEvent({required this.message});
}

/// FIX 8: one user blocked the other. Delivered to BOTH parties so each
/// app can end any in-progress call between them. [blockerId] is the user
/// who initiated the block; [blockedId] is the user being blocked. Either
/// id may be the current user (we ended it locally) or the other party
/// (they blocked us). The CallNotifier ends the call if the active call's
/// peer is involved on either side.
class UserBlockedEvent {
  final String blockerId;
  final String blockedId;
  const UserBlockedEvent({required this.blockerId, required this.blockedId});
}

// ── SignalingService ──────────────────────────────────────────────────────────

class SignalingService {
  sio.Socket? _socket;

  final _messageNewCtrl = StreamController<MessageNewEvent>.broadcast();
  final _messageAckCtrl = StreamController<MessageAckEvent>.broadcast();
  final _messageDeletedCtrl =
      StreamController<MessageDeletedEvent>.broadcast();
  final _messageReactionCtrl =
      StreamController<MessageReactionEvent>.broadcast();
  final _typingCtrl = StreamController<TypingEvent>.broadcast();
  final _presenceCtrl = StreamController<PresenceEvent>.broadcast();

  // Call events
  final _callIncomingCtrl = StreamController<CallIncomingEvent>.broadcast();
  final _callAnsweredCtrl = StreamController<CallAnsweredEvent>.broadcast();
  final _callIceCtrl = StreamController<CallIceEvent>.broadcast();
  final _callIceRestartCtrl =
      StreamController<CallIceRestartEvent>.broadcast();
  final _callHangupCtrl = StreamController<CallHangupEvent>.broadcast();
  final _callRejectedCtrl = StreamController<CallRejectedEvent>.broadcast();
  final _callBusyCtrl = StreamController<CallBusyEvent>.broadcast();
  final _callMissedCtrl = StreamController<CallMissedEvent>.broadcast();
  final _callRingingCtrl = StreamController<CallRingingEvent>.broadcast();
  final _callErrorCtrl = StreamController<CallErrorEvent>.broadcast();
  final _userBlockedCtrl = StreamController<UserBlockedEvent>.broadcast();

  Stream<MessageNewEvent> get onMessageNew => _messageNewCtrl.stream;
  Stream<MessageAckEvent> get onMessageAck => _messageAckCtrl.stream;
  Stream<MessageDeletedEvent> get onMessageDeleted =>
      _messageDeletedCtrl.stream;
  Stream<MessageReactionEvent> get onMessageReaction =>
      _messageReactionCtrl.stream;
  Stream<TypingEvent> get onTyping => _typingCtrl.stream;
  Stream<PresenceEvent> get onPresence => _presenceCtrl.stream;

  Stream<CallIncomingEvent> get onCallIncoming => _callIncomingCtrl.stream;
  Stream<CallAnsweredEvent> get onCallAnswered => _callAnsweredCtrl.stream;
  Stream<CallIceEvent> get onCallIce => _callIceCtrl.stream;
  Stream<CallIceRestartEvent> get onCallIceRestart =>
      _callIceRestartCtrl.stream;
  Stream<CallHangupEvent> get onCallHangup => _callHangupCtrl.stream;
  Stream<CallRejectedEvent> get onCallRejected => _callRejectedCtrl.stream;
  Stream<CallBusyEvent> get onCallBusy => _callBusyCtrl.stream;
  Stream<CallMissedEvent> get onCallMissed => _callMissedCtrl.stream;
  Stream<CallRingingEvent> get onCallRinging => _callRingingCtrl.stream;
  Stream<CallErrorEvent> get onCallError => _callErrorCtrl.stream;
  Stream<UserBlockedEvent> get onUserBlocked => _userBlockedCtrl.stream;

  /// Fired on connect / reconnect — SyncService subscribes to this.
  VoidCallback? onReconnect;

  /// Last access token we connected with. Used to short-circuit redundant
  /// connect() calls (e.g. two rapid auth-state changes) so we don't
  /// dispose a healthy socket mid-handshake and replace it with an
  /// identical one.
  String? _lastConnectedToken;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String accessToken) {
    // Re-entrancy guard: if the same token is already wired up and the
    // socket is alive (or in the middle of reconnecting on its own),
    // skip the dispose/recreate. Otherwise we'd tear down a healthy
    // connection just to re-establish an identical one.
    if (_socket != null && _lastConnectedToken == accessToken) {
      return;
    }
    _socket?.dispose();
    _lastConnectedToken = accessToken;
    _socket = sio.io(
      AppConfig.signalingUrl,
      sio.OptionBuilder()
          .setPath('/signal')
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .enableReconnection()
          .setReconnectionAttempts(99999)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .setRandomizationFactor(0.5)
          .setTimeout(20000)
          .disableAutoConnect()
          .build(),
    );
    _attachListeners();
    _socket!.connect();
  }

  /// Call after a token refresh so the next reconnect uses the fresh token.
  void updateToken(String accessToken) {
    _socket?.auth = {'token': accessToken};
    _lastConnectedToken = accessToken;
  }

  void _attachListeners() {
    final s = _socket!;

    s.on('connect', (_) {
      debugPrint('[signal] socket connected (id=${s.id})');
      onReconnect?.call();
    });
    s.on('reconnect', (_) {
      debugPrint('[signal] socket reconnected (id=${s.id})');
      onReconnect?.call();
    });
    s.on('disconnect', (reason) {
      debugPrint('[signal] socket disconnected: $reason');
    });
    s.on('connect_error', (err) {
      debugPrint('[signal] socket connect_error: $err');
    });
    s.on('error', (err) {
      debugPrint('[signal] socket error: $err');
    });

    s.on('message:new', (data) {
      final map = _asMap(data);
      if (map != null) {
        _messageNewCtrl.add(MessageNewEvent(map));
      }
    });

    s.on('message:ack', (data) {
      final map = _asMap(data);
      if (map == null) return;
      // Defensive: backend occasionally emits acks missing fields during
      // race conditions (e.g. ack for a message_id we already replaced).
      // Previously the unconditional `as String` cast threw an unhandled
      // Dart exception, polluting logs without crashing the app.
      final messageId = map['message_id'] as String?;
      final status = map['status'] as String?;
      if (messageId == null || status == null) return;
      _messageAckCtrl.add(MessageAckEvent(
        messageId: messageId,
        status: status,
      ));
    });

    s.on('message:deleted', (data) {
      final map = _asMap(data);
      if (map == null) return;
      final messageId = map['message_id'] as String?;
      final conversationId = map['conversation_id'] as String?;
      if (messageId == null || conversationId == null) return;
      _messageDeletedCtrl.add(MessageDeletedEvent(
        messageId: messageId,
        conversationId: conversationId,
      ));
    });

    void emitReaction(Map<String, dynamic> map, {required bool added}) {
      final messageId = map['message_id'] as String?;
      final conversationId = map['conversation_id'] as String?;
      final actorUserId = map['user_id'] as String?;
      final emoji = map['emoji'] as String?;
      if (messageId == null ||
          conversationId == null ||
          actorUserId == null ||
          emoji == null) {
        return;
      }
      final reactions = (map['reactions'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const <Map<String, dynamic>>[];
      _messageReactionCtrl.add(MessageReactionEvent(
        messageId: messageId,
        conversationId: conversationId,
        actorUserId: actorUserId,
        emoji: emoji,
        added: added,
        reactionsJson: reactions,
      ));
    }

    s.on('message:reaction_added', (data) {
      final map = _asMap(data);
      if (map != null) emitReaction(map, added: true);
    });
    s.on('message:reaction_removed', (data) {
      final map = _asMap(data);
      if (map != null) emitReaction(map, added: false);
    });

    s.on('typing:start', (data) {
      final map = _asMap(data);
      if (map == null) return;
      final fromUserId = map['from'] as String?;
      final conversationId = map['conversation_id'] as String?;
      if (fromUserId == null || conversationId == null) return;
      _typingCtrl.add(TypingEvent(
        fromUserId: fromUserId,
        conversationId: conversationId,
        isTyping: true,
      ));
    });

    s.on('typing:stop', (data) {
      final map = _asMap(data);
      if (map == null) return;
      final fromUserId = map['from'] as String?;
      final conversationId = map['conversation_id'] as String?;
      if (fromUserId == null || conversationId == null) return;
      _typingCtrl.add(TypingEvent(
        fromUserId: fromUserId,
        conversationId: conversationId,
        isTyping: false,
      ));
    });

    s.on('presence:update', (data) {
      final map = _asMap(data);
      if (map == null) return;
      // Backend occasionally emits presence updates with null user_id
      // (e.g. for a user that was just deleted, or during socket
      // handshake). Don't propagate them — they crashed the cast.
      final userId = map['user_id'] as String?;
      final status = map['status'] as String?;
      if (userId == null || status == null) return;
      _presenceCtrl.add(PresenceEvent(
        userId: userId,
        status: status,
        lastSeen: map['last_seen'] is String
            ? DateTime.tryParse(map['last_seen'] as String)
            : null,
      ));
    });

    // ── Call events ──────────────────────────────────────────────────────────

    s.on('call:incoming', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callIncomingCtrl.add(CallIncomingEvent(map));
      }
    });

    s.on('call:answered', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callAnsweredCtrl.add(CallAnsweredEvent(map));
      }
    });

    s.on('call:ice', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callIceCtrl.add(CallIceEvent(map));
      }
    });

    s.on('call:ice_restart', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callIceRestartCtrl.add(CallIceRestartEvent(map));
      }
    });

    s.on('call:hangup', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callHangupCtrl.add(CallHangupEvent(
          callId: map['call_id'] as String? ?? '',
          fromUserId: map['from'] as String? ?? '',
        ));
      }
    });

    s.on('call:rejected', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callRejectedCtrl.add(CallRejectedEvent(
          callId: map['call_id'] as String? ?? '',
          fromUserId: map['from'] as String? ?? '',
        ));
      }
    });

    s.on('call:busy', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callBusyCtrl.add(CallBusyEvent(
          callId: map['call_id'] as String? ?? '',
        ));
      }
    });

    s.on('call:missed', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callMissedCtrl.add(CallMissedEvent(
          callId: map['call_id'] as String? ?? '',
        ));
      }
    });

    // call:ringing — backend acks that the offer reached the callee.
    // Useful as a positive signal that the outgoing call is "live" beyond
    // just "we emitted the offer".
    s.on('call:ringing', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callRingingCtrl.add(CallRingingEvent(
          callId: map['call_id'] as String? ?? '',
        ));
      }
    });

    // call:error — backend rejected the attempt outright (validation
    // failure, not-a-contact, rate limit, internal error, etc.). Carries a
    // human message that the UI should surface to the user.
    s.on('call:error', (data) {
      final map = _asMap(data);
      if (map != null) {
        _callErrorCtrl.add(CallErrorEvent(
          message: map['message'] as String? ?? 'Call failed.',
        ));
      } else if (data is String) {
        // Server might emit a bare string in some paths; tolerate it.
        _callErrorCtrl.add(CallErrorEvent(message: data));
      }
    });

    // FIX 8: user:blocked — one of the two parties in an A↔B relationship
    // has blocked the other. Delivered to both A and B so each end can
    // tear down any in-progress call between them. Payload shape matches
    // the FastAPI block-publish + Node forward chain (see
    // backend/api/app/services/contact_service.py set_blocked).
    s.on('user:blocked', (data) {
      final map = _asMap(data);
      if (map != null) {
        _userBlockedCtrl.add(UserBlockedEvent(
          blockerId: map['blocker_id'] as String? ?? '',
          blockedId: map['blocked_id'] as String? ?? '',
        ));
      }
    });
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    // Log once per dropped event — the server changing shape would otherwise
    // be invisible (events would just silently stop arriving in the UI).
    debugPrint('[signaling] dropped malformed event payload: '
        '${data?.runtimeType}');
    return null;
  }

  // ── Emit helpers ─────────────────────────────────────────────────────────

  void emitTyping({required bool isTyping, required String conversationId}) {
    _socket?.emit(
      isTyping ? 'typing:start' : 'typing:stop',
      {'conversation_id': conversationId},
    );
  }

  void emitPresence(String status) {
    _socket?.emit('presence:update', {'status': status});
  }

  void requestPresence(List<String> userIds) {
    _socket?.emit('presence:request', {'user_ids': userIds});
  }

  // ── Call emit helpers ─────────────────────────────────────────────────────
  //
  // Every emit prints whether the socket exists and is connected. When a
  // call mysteriously "doesn't go through", the first thing to check is
  // whether [_socket?.connected] was true at the moment we emitted — if it
  // was false, socket.io-client buffers locally and the server never sees
  // the event until reconnect (which may be never, e.g. on auth failure).

  void _emitCall(String event, Map<String, dynamic> payload) {
    final s = _socket;
    final connected = s?.connected ?? false;
    if (s == null) {
      debugPrint('[signal] $event DROPPED — socket is null');
      return;
    }
    if (!connected) {
      debugPrint(
          '[signal] $event queued — socket exists but not connected (will buffer until reconnect)');
    } else {
      debugPrint('[signal] $event emitting (socket.connected=true)');
    }
    s.emit(event, payload);
  }

  void emitCallInitiate({
    required String callId,
    required String to,
    required Map<String, dynamic> offer,
    required String callType,
  }) {
    _emitCall('call:initiate', {
      'call_id': callId,
      'to': to,
      'offer': offer,
      'call_type': callType,
    });
  }

  void emitCallAnswer({
    required String callId,
    required String to,
    required Map<String, dynamic> answer,
  }) {
    _emitCall('call:answer', {
      'call_id': callId,
      'to': to,
      'answer': answer,
    });
  }

  void emitCallIce({
    required String callId,
    required String to,
    required Map<String, dynamic> candidate,
  }) {
    _emitCall('call:ice', {
      'call_id': callId,
      'to': to,
      'candidate': candidate,
    });
  }

  void emitCallIceRestart({
    required String callId,
    required String to,
    required Map<String, dynamic> offer,
  }) {
    _emitCall('call:ice_restart', {
      'call_id': callId,
      'to': to,
      'offer': offer,
    });
  }

  void emitCallHangup({
    required String callId,
    required String to,
  }) {
    _emitCall('call:hangup', {'call_id': callId, 'to': to});
  }

  void emitCallReject({
    required String callId,
    required String to,
  }) {
    _emitCall('call:reject', {'call_id': callId, 'to': to});
  }

  void emitCallBusy({
    required String callId,
    required String to,
  }) {
    _emitCall('call:busy', {'call_id': callId, 'to': to});
  }

  void disconnect() {
    _socket?.disconnect();
    _lastConnectedToken = null;
  }

  void dispose() {
    _socket?.dispose();
    _lastConnectedToken = null;
    _messageNewCtrl.close();
    _messageAckCtrl.close();
    _messageDeletedCtrl.close();
    _typingCtrl.close();
    _presenceCtrl.close();
    _callIncomingCtrl.close();
    _callAnsweredCtrl.close();
    _callIceCtrl.close();
    _callIceRestartCtrl.close();
    _callHangupCtrl.close();
    _callRejectedCtrl.close();
    _callBusyCtrl.close();
    _callMissedCtrl.close();
    _callRingingCtrl.close();
    _callErrorCtrl.close();
    _userBlockedCtrl.close();
  }
}

final signalingServiceProvider = Provider<SignalingService>((ref) {
  final service = SignalingService();

  // fireImmediately so a token already restored from secure storage (cold
  // start path) actually triggers connect(). Without it, ref.listen only
  // fires on subsequent changes and the socket stays closed forever.
  ref.listen(authTokenProvider, (_, next) {
    if (next != null && !AppConfig.uiOnly) {
      service.connect(next);
    } else if (next == null) {
      service.disconnect();
    }
  }, fireImmediately: true);

  ref.onDispose(service.dispose);
  return service;
});

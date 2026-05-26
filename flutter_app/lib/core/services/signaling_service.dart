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

// ── SignalingService ──────────────────────────────────────────────────────────

class SignalingService {
  sio.Socket? _socket;

  final _messageNewCtrl = StreamController<MessageNewEvent>.broadcast();
  final _messageAckCtrl = StreamController<MessageAckEvent>.broadcast();
  final _messageDeletedCtrl =
      StreamController<MessageDeletedEvent>.broadcast();
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

  Stream<MessageNewEvent> get onMessageNew => _messageNewCtrl.stream;
  Stream<MessageAckEvent> get onMessageAck => _messageAckCtrl.stream;
  Stream<MessageDeletedEvent> get onMessageDeleted =>
      _messageDeletedCtrl.stream;
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

  /// Fired on connect / reconnect — SyncService subscribes to this.
  VoidCallback? onReconnect;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String accessToken) {
    _socket?.dispose();
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
  }

  void _attachListeners() {
    final s = _socket!;

    s.on('connect', (_) => onReconnect?.call());
    s.on('reconnect', (_) => onReconnect?.call());

    s.on('message:new', (data) {
      final map = _asMap(data);
      if (map != null) {
        _messageNewCtrl.add(MessageNewEvent(map));
      }
    });

    s.on('message:ack', (data) {
      final map = _asMap(data);
      if (map != null) {
        _messageAckCtrl.add(MessageAckEvent(
          messageId: map['message_id'] as String,
          status: map['status'] as String,
        ));
      }
    });

    s.on('message:deleted', (data) {
      final map = _asMap(data);
      if (map != null) {
        _messageDeletedCtrl.add(MessageDeletedEvent(
          messageId: map['message_id'] as String,
          conversationId: map['conversation_id'] as String,
        ));
      }
    });

    s.on('typing:start', (data) {
      final map = _asMap(data);
      if (map != null) {
        _typingCtrl.add(TypingEvent(
          fromUserId: map['from'] as String,
          conversationId: map['conversation_id'] as String,
          isTyping: true,
        ));
      }
    });

    s.on('typing:stop', (data) {
      final map = _asMap(data);
      if (map != null) {
        _typingCtrl.add(TypingEvent(
          fromUserId: map['from'] as String,
          conversationId: map['conversation_id'] as String,
          isTyping: false,
        ));
      }
    });

    s.on('presence:update', (data) {
      final map = _asMap(data);
      if (map != null) {
        _presenceCtrl.add(PresenceEvent(
          userId: map['user_id'] as String,
          status: map['status'] as String,
          lastSeen: map['last_seen'] != null
              ? DateTime.parse(map['last_seen'] as String)
              : null,
        ));
      }
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

  void emitCallInitiate({
    required String callId,
    required String to,
    required Map<String, dynamic> offer,
    required String callType,
  }) {
    _socket?.emit('call:initiate', {
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
    _socket?.emit('call:answer', {
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
    _socket?.emit('call:ice', {
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
    _socket?.emit('call:ice_restart', {
      'call_id': callId,
      'to': to,
      'offer': offer,
    });
  }

  void emitCallHangup({
    required String callId,
    required String to,
  }) {
    _socket?.emit('call:hangup', {'call_id': callId, 'to': to});
  }

  void emitCallReject({
    required String callId,
    required String to,
  }) {
    _socket?.emit('call:reject', {'call_id': callId, 'to': to});
  }

  void emitCallBusy({
    required String callId,
    required String to,
  }) {
    _socket?.emit('call:busy', {'call_id': callId, 'to': to});
  }

  void disconnect() => _socket?.disconnect();

  void dispose() {
    _socket?.dispose();
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

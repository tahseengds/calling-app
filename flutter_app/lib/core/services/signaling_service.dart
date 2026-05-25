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

// Call events — consumed by prompt 14
class CallIncomingEvent {
  final Map<String, dynamic> json;
  const CallIncomingEvent(this.json);
}

// ── SignalingService ──────────────────────────────────────────────────────────

class SignalingService {
  sio.Socket? _socket;

  final _messageNewCtrl =
      StreamController<MessageNewEvent>.broadcast();
  final _messageAckCtrl =
      StreamController<MessageAckEvent>.broadcast();
  final _messageDeletedCtrl =
      StreamController<MessageDeletedEvent>.broadcast();
  final _typingCtrl = StreamController<TypingEvent>.broadcast();
  final _presenceCtrl = StreamController<PresenceEvent>.broadcast();
  final _callIncomingCtrl =
      StreamController<CallIncomingEvent>.broadcast();

  Stream<MessageNewEvent> get onMessageNew => _messageNewCtrl.stream;
  Stream<MessageAckEvent> get onMessageAck => _messageAckCtrl.stream;
  Stream<MessageDeletedEvent> get onMessageDeleted =>
      _messageDeletedCtrl.stream;
  Stream<TypingEvent> get onTyping => _typingCtrl.stream;
  Stream<PresenceEvent> get onPresence => _presenceCtrl.stream;
  Stream<CallIncomingEvent> get onCallIncoming => _callIncomingCtrl.stream;

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
      if (map != null) _messageNewCtrl.add(MessageNewEvent(map));
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

    s.on('call:incoming', (data) {
      final map = _asMap(data);
      if (map != null) _callIncomingCtrl.add(CallIncomingEvent(map));
    });
  }

  Map<String, dynamic>? _asMap(dynamic data) =>
      data is Map<String, dynamic> ? data : null;

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

  void disconnect() => _socket?.disconnect();

  void dispose() {
    _socket?.dispose();
    _messageNewCtrl.close();
    _messageAckCtrl.close();
    _messageDeletedCtrl.close();
    _typingCtrl.close();
    _presenceCtrl.close();
    _callIncomingCtrl.close();
  }
}

final signalingServiceProvider = Provider<SignalingService>((ref) {
  final service = SignalingService();

  // Connect / disconnect in sync with the auth token.
  ref.listen(authTokenProvider, (_, next) {
    if (next != null && !AppConfig.uiOnly) {
      service.connect(next);
    } else if (next == null) {
      service.disconnect();
    }
  });

  ref.onDispose(service.dispose);
  return service;
});

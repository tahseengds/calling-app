import 'message.dart';
import 'user.dart';

class Conversation {
  final String id;
  final User otherUser;
  final String? lastMessagePreview;
  final MessageType? lastMessageType;
  final DateTime lastActivity;
  final int unreadCount;

  const Conversation({
    required this.id,
    required this.otherUser,
    this.lastMessagePreview,
    this.lastMessageType,
    required this.lastActivity,
    this.unreadCount = 0,
  });

  Conversation copyWith({User? otherUser, int? unreadCount}) => Conversation(
        id: id,
        otherUser: otherUser ?? this.otherUser,
        lastMessagePreview: lastMessagePreview,
        lastMessageType: lastMessageType,
        lastActivity: lastActivity,
        unreadCount: unreadCount ?? this.unreadCount,
      );
}

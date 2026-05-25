import 'package:flutter_riverpod/legacy.dart';

class ChatConversation {
  final String id;
  final String name;
  final String snippet;
  final String time;
  final int unreadCount;
  final bool isOnline;
  final String? attachmentType; // 'image', 'video', 'document', 'voice', 'call'
  final bool isMissedCall;

  const ChatConversation({
    required this.id,
    required this.name,
    required this.snippet,
    required this.time,
    this.unreadCount = 0,
    this.isOnline = false,
    this.attachmentType,
    this.isMissedCall = false,
  });
}

class ChatsNotifier extends StateNotifier<List<ChatConversation>> {
  ChatsNotifier() : super(_initialData);

  static const _initialData = [
    ChatConversation(
      id: 'rose',
      name: 'Grandma Rose',
      snippet: "Don't forget Sunday dinner",
      time: '2 min',
      unreadCount: 2,
      isOnline: true,
    ),
    ChatConversation(
      id: 'mike',
      name: 'Dad Mike',
      snippet: 'You: Will do, see you then',
      time: '12 min',
      isOnline: true,
    ),
    ChatConversation(
      id: 'fam',
      name: 'The Whole Family',
      snippet: 'Karen sent a photo',
      time: '1:14 PM',
      unreadCount: 5,
      attachmentType: 'image',
    ),
    ChatConversation(
      id: 'karen',
      name: 'Aunt Karen',
      snippet: '0:24 voice note',
      time: 'Yesterday',
      attachmentType: 'voice',
    ),
    ChatConversation(
      id: 'jamie',
      name: 'Cousin Jamie',
      snippet: 'You: Family-tree-2026.pdf',
      time: 'Mon',
      attachmentType: 'document',
    ),
    ChatConversation(
      id: 'pete',
      name: 'Uncle Pete',
      snippet: 'Missed video call',
      time: 'Sat',
      attachmentType: 'call',
      isMissedCall: true,
    ),
    ChatConversation(
      id: 'sarah',
      name: 'Mom Sarah',
      snippet: "How's the new place?",
      time: 'Thu',
      isOnline: true,
    ),
  ];

  void markAsRead(String id) {
    state = [
      for (final c in state)
        if (c.id == id)
          ChatConversation(
            id: c.id,
            name: c.name,
            snippet: c.snippet,
            time: c.time,
            unreadCount: 0,
            isOnline: c.isOnline,
            attachmentType: c.attachmentType,
            isMissedCall: c.isMissedCall,
          )
        else
          c
    ];
  }
}

final chatsNotifierProvider = StateNotifierProvider<ChatsNotifier, List<ChatConversation>>((ref) {
  return ChatsNotifier();
});

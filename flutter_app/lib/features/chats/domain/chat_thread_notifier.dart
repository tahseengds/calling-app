import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/app_config.dart';
import '../../../../shared/models/message.dart';

class ChatThreadState {
  final List<Message> messages;
  final bool isLoading;

  const ChatThreadState({required this.messages, this.isLoading = false});
}

class ChatThreadNotifier extends Notifier<ChatThreadState> {
  final String arg;
  ChatThreadNotifier(this.arg);

  @override
  ChatThreadState build() {
    // Populate mock messages depending on conversation ID
    return ChatThreadState(
      messages: _getInitialMessages(arg),
    );
  }

  List<Message> _getInitialMessages(String conversationId) {
    final now = DateTime.now();
    if (conversationId == 'rose') {
      return [
        Message(
          id: '1',
          conversationId: conversationId,
          senderId: 'rose',
          type: MessageType.text,
          content: 'Are you free for a quick call after dinner?',
          status: MessageStatus.read,
          createdAt: now.subtract(const Duration(minutes: 20)),
        ),
        Message(
          id: '2',
          conversationId: conversationId,
          senderId: 'current_user',
          type: MessageType.text,
          content: 'Of course! Give me 20 minutes.',
          status: MessageStatus.read,
          createdAt: now.subtract(const Duration(minutes: 19)),
        ),
        Message(
          id: '3',
          conversationId: conversationId,
          senderId: 'rose',
          type: MessageType.text,
          content: "Perfect. The kettle's already on.",
          status: MessageStatus.read,
          createdAt: now.subtract(const Duration(minutes: 18)),
        ),
      ];
    } else if (conversationId == 'mike') {
      return [
        Message(
          id: '1',
          conversationId: conversationId,
          senderId: 'mike',
          type: MessageType.text,
          content: 'Are we still on for Sunday?',
          status: MessageStatus.read,
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
        Message(
          id: '2',
          conversationId: conversationId,
          senderId: 'current_user',
          type: MessageType.text,
          content: 'Will do, see you then',
          status: MessageStatus.read,
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
      ];
    } else {
      // Unknown ID — in UI-only mode show demo messages so the chat screen
      // isn't blank during design review.  In production mode return an empty
      // list: the backend will supply real messages via the messaging feature.
      if (!AppConfig.uiOnly) return [];
      return [
        Message(
          id: '1',
          conversationId: conversationId,
          senderId: 'other',
          type: MessageType.text,
          content: 'Hello! How is it going?',
          status: MessageStatus.read,
          createdAt: now.subtract(const Duration(hours: 5)),
        ),
        Message(
          id: 'failed_msg',
          conversationId: conversationId,
          senderId: 'current_user',
          type: MessageType.text,
          content: 'This message failed to send, tap it.',
          status: MessageStatus.failed,
          createdAt: now.subtract(const Duration(minutes: 2)),
        ),
      ];
    }
  }

  void sendMessage(String text) {
    final now = DateTime.now();
    final newMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: arg,
      senderId: 'current_user',
      type: MessageType.text,
      content: text,
      status: MessageStatus.sending,
      createdAt: now,
    );

    // Add to state
    state = ChatThreadState(
      messages: [...state.messages, newMessage],
    );

    // Simulate network delay to set as delivered
    Future.delayed(const Duration(seconds: 1), () {
      state = ChatThreadState(
        messages: [
          for (final msg in state.messages)
            if (msg.id == newMessage.id)
              msg.copyWith(status: MessageStatus.delivered)
            else
              msg
        ],
      );
    });
  }

  void sendAudioMessage(int durationSeconds) {
    final now = DateTime.now();
    final newMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: arg,
      senderId: 'current_user',
      type: MessageType.audio,
      media: MediaAttachment(
        url: 'audio.m4a',
        durationSeconds: durationSeconds,
      ),
      status: MessageStatus.sending,
      createdAt: now,
    );

    state = ChatThreadState(
      messages: [...state.messages, newMessage],
    );

    Future.delayed(const Duration(seconds: 1), () {
      state = ChatThreadState(
        messages: [
          for (final msg in state.messages)
            if (msg.id == newMessage.id)
              msg.copyWith(status: MessageStatus.delivered)
            else
              msg
        ],
      );
    });
  }

  void retryMessage(String messageId) {
    // Set to sending
    state = ChatThreadState(
      messages: [
        for (final msg in state.messages)
          if (msg.id == messageId)
            msg.copyWith(status: MessageStatus.sending)
          else
            msg
      ],
    );

    // Simulate success after 1 second
    Future.delayed(const Duration(seconds: 1), () {
      state = ChatThreadState(
        messages: [
          for (final msg in state.messages)
            if (msg.id == messageId)
              msg.copyWith(status: MessageStatus.delivered)
            else
              msg
        ],
      );
    });
  }

  void deleteMessage(String messageId) {
    state = ChatThreadState(
      messages: state.messages.where((msg) => msg.id != messageId).toList(),
    );
  }
}

final chatThreadNotifierProvider = NotifierProvider.family<ChatThreadNotifier, ChatThreadState, String>(
  ChatThreadNotifier.new,
);

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/auth/domain/auth_notifier.dart';
import '../../../features/auth/domain/auth_state.dart';
import '../../../shared/models/message.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/avatar.dart';
import '../domain/chat_notifier.dart';
import '../domain/presence_provider.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/message_bubble.dart';
import 'widgets/typing_indicator.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String? contactName;

  const ChatScreen({
    super.key,
    required this.conversationId,
    this.contactName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  Message? _replyingTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = false}) {
    if (!_scrollCtrl.hasClients) return;
    final target = _scrollCtrl.position.maxScrollExtent;
    if (animated) {
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollCtrl.jumpTo(target);
    }
  }

  String get _currentUserId {
    final auth = ref.read(authNotifierProvider);
    return auth is AuthAuthenticated ? auth.me.id : '';
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(widget.conversationId));
    final notifier = ref.read(chatProvider(widget.conversationId).notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final otherUser = chatState.otherUser;
    final presenceAsync =
        ref.watch(presenceProvider(otherUser?.id ?? widget.conversationId));
    final isOnline = presenceAsync.valueOrNull == PresenceStatus.online;

    // Scroll to bottom when new message arrives.
    ref.listen(chatProvider(widget.conversationId), (prev, next) {
      if ((prev?.messages.length ?? 0) < next.messages.length) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom(animated: true));
      }
    });

    return Scaffold(
      appBar: _buildAppBar(context, otherUser, isOnline, isDark),
      body: Column(
        children: [
          // ── Message list ──────────────────────────────────────────────────
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification &&
                    _scrollCtrl.position.pixels == 0) {
                  notifier.loadOlderMessages();
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
                itemCount: chatState.messages.length +
                    (chatState.isLoadingOlder ? 1 : 0) +
                    (chatState.otherUserTyping ? 1 : 0),
                itemBuilder: (_, i) {
                  if (chatState.isLoadingOlder && i == 0) {
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final offset = chatState.isLoadingOlder ? 1 : 0;
                  final msgs = chatState.messages;

                  // Typing indicator at bottom
                  if (chatState.otherUserTyping &&
                      i == msgs.length + offset) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: const TypingIndicator(),
                        ),
                      ),
                    );
                  }

                  final msg = msgs[i - offset];
                  final isSent = msg.senderId == _currentUserId;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_showDateSeparator(msgs, i - offset))
                          _DateSeparator(date: msg.createdAt),
                        MessageBubble(
                          message: msg,
                          isSent: isSent,
                          onReply: (_) =>
                              setState(() => _replyingTo = msg),
                          onDelete: isSent
                              ? (id) => notifier.deleteMessage(id)
                              : null,
                          onRetry: msg.status == MessageStatus.failed
                              ? (id) => notifier.retryMessage(id)
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // ── Reply preview ─────────────────────────────────────────────────
          // ── Input bar ─────────────────────────────────────────────────────
          ChatInputBar(
            controller: _inputCtrl,
            focusNode: _inputFocus,
            onSend: () {
              final text = _inputCtrl.text;
              if (text.trim().isEmpty) return;
              _inputCtrl.clear();
              notifier.sendText(text, replyToId: _replyingTo?.id);
              setState(() => _replyingTo = null);
            },
            onSendMedia: (File file, MessageType type) =>
                notifier.sendMedia(file, type),
            onSendVoice: (File file, int dur) =>
                notifier.sendMedia(file, MessageType.audio),
            onTyping: notifier.onUserTyping,
            replyPreview: _replyingTo != null
                ? _ReplyBar(
                    message: _replyingTo!,
                    onCancel: () => setState(() => _replyingTo = null),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    User? otherUser,
    bool isOnline,
    bool isDark,
  ) {
    final name =
        otherUser?.name ?? widget.contactName ?? 'Chat';
    final sub = isOnline
        ? 'Online'
        : (otherUser != null
            ? 'last seen ${_relativeTime(otherUser.lastSeen)}'
            : '');

    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          if (otherUser != null) ...[
            Stack(
              children: [
                UserAvatar(
                  imageUrl: otherUser.avatarUrl,
                  displayName: name,
                  radius: 18,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBg
                              : AppColors.lightBg,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              if (sub.isNotEmpty)
                Text(sub,
                    style: TextStyle(
                        fontSize: 12,
                        color: isOnline
                            ? AppColors.success
                            : (isDark
                                ? AppColors.darkFg3
                                : AppColors.lightFg2),
                        fontWeight: FontWeight.normal)),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.videocam_rounded),
          onPressed: () => context.push(
            '/call/outgoing?name=${Uri.encodeComponent(name)}&kind=video',
          ),
        ),
        IconButton(
          icon: const Icon(Icons.call_rounded),
          onPressed: () => context.push(
            '/call/outgoing?name=${Uri.encodeComponent(name)}&kind=voice',
          ),
        ),
      ],
    );
  }

  bool _showDateSeparator(List<Message> msgs, int i) {
    if (i == 0) return true;
    final prev = msgs[i - 1].createdAt.toLocal();
    final curr = msgs[i].createdAt.toLocal();
    return prev.year != curr.year ||
        prev.month != curr.month ||
        prev.day != curr.day;
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 2) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat.MMMd().format(dt.toLocal());
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = _label(date);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: (isDark ? AppColors.darkSurface : AppColors.lightSurface)
              .withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
          ),
        ),
      ),
    );
  }

  String _label(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day) return 'Yesterday';
    return DateFormat.MMMd().format(local);
  }
}

class _ReplyBar extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;
  const _ReplyBar({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Replying',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                Text(
                  message.content ?? '📎 Media',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

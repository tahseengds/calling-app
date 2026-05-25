import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/conversation.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/avatar.dart';
import '../domain/conversation_list_notifier.dart';

class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncConvos = ref.watch(conversationListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push('/chat/search'),
          ),
        ],
      ),
      body: asyncConvos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('$e', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.read(conversationListProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (convos) {
          if (convos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 64,
                      color: isDark
                          ? AppColors.darkFg3
                          : AppColors.lightFg2),
                  const SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? AppColors.darkFg3
                          : AppColors.lightFg2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a chat from the Contacts tab',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.darkFg3
                          : AppColors.lightFg2,
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(conversationListProvider.notifier).refresh(),
            child: ListView.separated(
              itemCount: convos.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 72,
                color: isDark
                    ? AppColors.darkHairline
                    : AppColors.lightHairline,
              ),
              itemBuilder: (_, i) =>
                  _ConversationTile(conversation: convos[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/contacts'),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.edit_rounded, color: Colors.white),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final other = conversation.otherUser;
    final unread = conversation.unreadCount;
    final isOnline = other.presence == PresenceStatus.online;

    return InkWell(
      onTap: () => context.push(
        '/chat/${conversation.id}?name=${Uri.encodeComponent(other.name)}',
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar with online dot
            Stack(
              children: [
                UserAvatar(
                  imageUrl: other.avatarUrl,
                  displayName: other.name,
                  radius: 26,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBg
                              : AppColors.lightBg,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          other.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(conversation.lastActivity),
                        style: TextStyle(
                          fontSize: 12,
                          color: unread > 0
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.darkFg3
                                  : AppColors.lightFg2),
                          fontWeight: unread > 0
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessagePreview ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: unread > 0
                                ? (isDark
                                    ? AppColors.darkFg1
                                    : AppColors.lightFg1)
                                : (isDark
                                    ? AppColors.darkFg3
                                    : AppColors.lightFg2),
                            fontWeight: unread > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return DateFormat.jm().format(dt.toLocal());
    if (diff.inDays < 7) return DateFormat.E().format(dt.toLocal());
    return DateFormat('MM/dd').format(dt.toLocal());
  }
}

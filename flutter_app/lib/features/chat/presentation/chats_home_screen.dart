import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/chat/domain/conversation_list_notifier.dart';
import '../../../shared/models/conversation.dart';
import '../../../shared/models/message.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/lumio_icons.dart';

/// Polished "Messages" home screen — rich card list with filter chips,
/// attachment-type icons, missed-call coloring, animated empty state.
/// Backed by the live conversationListProvider (chat_notifier).
class ChatsHomeScreen extends ConsumerStatefulWidget {
  const ChatsHomeScreen({super.key});

  @override
  ConsumerState<ChatsHomeScreen> createState() => _ChatsHomeScreenState();
}

enum _Filter { all, online, unread }

class _ChatsHomeScreenState extends ConsumerState<ChatsHomeScreen> {
  _Filter _activeFilter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final asyncConvos = ref.watch(conversationListProvider);
    final theme = Theme.of(context);
    final lumioColors = context.lumioColors;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space2,
              ),
              child: SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Chats',
                      style: AppTextStyles.h1(color: lumioColors.fg1),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(LumioIcons.search,
                              color: lumioColors.fg1),
                          onPressed: () => context.push('/chat/search'),
                          tooltip: 'Search',
                        ),
                        const SizedBox(width: AppSpacing.space1),
                        IconButton(
                          icon: Icon(Icons.qr_code,
                              color: lumioColors.fg1),
                          onPressed: () => context.push('/qr'),
                          tooltip: 'Add friend by QR',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Filter Chips ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                AppSpacing.space1,
                AppSpacing.space4,
                AppSpacing.space3,
              ),
              child: Row(
                children: _Filter.values.map((f) {
                  final isOn = f == _activeFilter;
                  final label = _filterLabel(f);
                  return Padding(
                    padding:
                        const EdgeInsets.only(right: AppSpacing.space2),
                    child: Semantics(
                      // Custom-painted GestureDetector chip — wrap so TalkBack
                      // announces it as a selectable button, not a plain tap.
                      button: true,
                      selected: isOn,
                      label: '$label filter',
                      child: GestureDetector(
                        onTap: () => setState(() => _activeFilter = f),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isOn ? AppColors.primary : Colors.transparent,
                            border: Border.all(
                              color: isOn
                                  ? Colors.transparent
                                  : lumioColors.hairline,
                            ),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Center(
                            child: Text(
                              label,
                              style: AppTextStyles.secondaryMedium(
                                color:
                                    isOn ? Colors.white : lumioColors.fg1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ── Conversation List ─────────────────────────────────────────
            Expanded(
              child: asyncConvos.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _buildErrorState(lumioColors, e),
                data: (convos) {
                  final filtered = _applyFilter(convos);
                  if (filtered.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () => ref
                          .read(conversationListProvider.notifier)
                          .refresh(),
                      child: ListView(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height *
                                0.55,
                            child: _buildEmptyState(lumioColors),
                          ),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => ref
                        .read(conversationListProvider.notifier)
                        .refresh(),
                    child: ListView.builder(
                      padding:
                          const EdgeInsets.all(AppSpacing.space4),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        final isLast = index == filtered.length - 1;
                        return _ConversationCard(
                          conversation: c,
                          isFirst: index == 0,
                          isLast: isLast,
                          theme: theme,
                          lumioColors: lumioColors,
                          onTap: () => context.push(
                            '/chat/${c.id}?name=${Uri.encodeComponent(c.otherUser.name)}',
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/contacts'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        tooltip: 'New chat',
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(LumioIcons.message, size: 26),
      ),
    );
  }

  // ── Filter helpers ────────────────────────────────────────────────────

  String _filterLabel(_Filter f) => switch (f) {
        _Filter.all => 'All',
        _Filter.online => 'Online',
        _Filter.unread => 'Unread',
      };

  List<Conversation> _applyFilter(List<Conversation> convos) {
    return switch (_activeFilter) {
      _Filter.all => convos,
      _Filter.online => convos
          .where((c) => c.otherUser.presence == PresenceStatus.online)
          .toList(),
      _Filter.unread =>
        convos.where((c) => c.unreadCount > 0).toList(),
    };
  }

  // ── Empty / error states ──────────────────────────────────────────────

  Widget _buildEmptyState(LumioColors lumioColors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: const BoxDecoration(
                    color: Color(0x145B7CFA),
                    shape: BoxShape.circle,
                  ),
                ),
                const Icon(
                  LumioIcons.message,
                  size: 48,
                  color: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space6),
            Text(
              _activeFilter == _Filter.all
                  ? 'No chats yet'
                  : 'Nothing here',
              style: AppTextStyles.display(color: lumioColors.fg1)
                  .copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              _activeFilter == _Filter.all
                  ? 'Tap the button to start a chat with someone in your contacts.'
                  : _activeFilter == _Filter.online
                      ? 'No one is online right now.'
                      : 'You have no unread messages.',
              style: AppTextStyles.secondary(color: lumioColors.fg2),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(LumioColors lumioColors, Object err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 48, color: lumioColors.fg3),
            const SizedBox(height: AppSpacing.space3),
            Text(
              'Could not load chats',
              style: AppTextStyles.bodySemibold(color: lumioColors.fg1),
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              '$err',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.secondary(color: lumioColors.fg2),
            ),
            const SizedBox(height: AppSpacing.space4),
            ElevatedButton(
              onPressed: () => ref
                  .read(conversationListProvider.notifier)
                  .refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card widget ─────────────────────────────────────────────────────────────

class _ConversationCard extends StatelessWidget {
  final Conversation conversation;
  final bool isFirst;
  final bool isLast;
  final ThemeData theme;
  final LumioColors lumioColors;
  final VoidCallback onTap;

  const _ConversationCard({
    required this.conversation,
    required this.isFirst,
    required this.isLast,
    required this.theme,
    required this.lumioColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final isOnline = c.otherUser.presence == PresenceStatus.online;
    final attachmentKind = _attachmentKind(c.lastMessageType);
    final preview = c.lastMessagePreview?.trim().isNotEmpty == true
        ? c.lastMessagePreview!
        : _defaultPreview(c.lastMessageType);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(
          left: BorderSide(color: lumioColors.hairline),
          right: BorderSide(color: lumioColors.hairline),
          top: isFirst
              ? BorderSide(color: lumioColors.hairline)
              : BorderSide.none,
          bottom: BorderSide(color: lumioColors.hairline),
        ),
        borderRadius: BorderRadius.vertical(
          top: isFirst
              ? const Radius.circular(AppRadius.xxl)
              : Radius.zero,
          bottom: isLast
              ? const Radius.circular(AppRadius.xxl)
              : Radius.zero,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.vertical(
            top: isFirst
                ? const Radius.circular(AppRadius.xxl)
                : Radius.zero,
            bottom: isLast
                ? const Radius.circular(AppRadius.xxl)
                : Radius.zero,
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 12,
            ),
            child: Row(
              children: [
                // Avatar with online dot. clipBehavior: Clip.none is
                // required — the dot is intentionally positioned 1px
                // outside the avatar so it overlaps the edge; with the
                // default Clip.hardEdge it would get cropped to nothing.
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(
                      displayName: c.otherUser.name,
                      imageUrl: c.otherUser.avatarUrl,
                      radius: 24,
                    ),
                    if (isOnline)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.cardTheme.color ??
                                  Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                // Name + snippet
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.otherUser.name,
                        style: AppTextStyles.bodySemibold(
                          color: lumioColors.fg1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (attachmentKind != null) ...[
                            Icon(
                              _previewIcon(attachmentKind),
                              size: 14,
                              color: lumioColors.fg2,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              preview,
                              style: AppTextStyles.secondary(
                                color: lumioColors.fg2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Date + unread badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTime(c.lastActivity),
                      style: AppTextStyles.secondary(
                        color: c.unreadCount > 0
                            ? AppColors.primary
                            : lumioColors.fg2,
                      ).copyWith(
                        fontWeight: c.unreadCount > 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (c.unreadCount > 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                        ),
                        child: Text(
                          c.unreadCount > 99
                              ? '99+'
                              : c.unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Maps a MessageType to the attachment-icon string the design uses,
  /// or null for plain text (which renders without an icon).
  static String? _attachmentKind(MessageType? type) => switch (type) {
        MessageType.image => 'image',
        MessageType.video => 'video',
        MessageType.audio => 'voice',
        MessageType.file => 'document',
        MessageType.text || null => null,
      };

  /// Fallback text when a media message has no caption.
  static String _defaultPreview(MessageType? type) => switch (type) {
        MessageType.image => 'Photo',
        MessageType.video => 'Video',
        MessageType.audio => 'Voice note',
        MessageType.file => 'File',
        MessageType.text || null => '',
      };

  static IconData _previewIcon(String kind) => switch (kind) {
        'image' => LumioIcons.camera,
        'video' => LumioIcons.video,
        'document' => LumioIcons.attach,
        'voice' => LumioIcons.mic,
        'call' => LumioIcons.phone,
        _ => LumioIcons.message,
      };

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';

    final sameDay = now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;
    if (sameDay) return DateFormat.jm().format(local);

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == local.year &&
        yesterday.month == local.month &&
        yesterday.day == local.day;
    if (isYesterday) return 'Yesterday';

    if (diff.inDays < 7) return DateFormat.E().format(local);
    return DateFormat('MM/dd').format(local);
  }
}

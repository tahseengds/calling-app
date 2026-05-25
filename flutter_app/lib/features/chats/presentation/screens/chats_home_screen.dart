import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../domain/chats_notifier.dart';
import '../../../shell/ui/shell_screen.dart';

class ChatsHomeScreen extends ConsumerStatefulWidget {
  const ChatsHomeScreen({super.key});

  @override
  ConsumerState<ChatsHomeScreen> createState() => _ChatsHomeScreenState();
}

class _ChatsHomeScreenState extends ConsumerState<ChatsHomeScreen> {
  String _activeFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(chatsNotifierProvider);
    final theme = Theme.of(context);
    final lumioColors = context.lumioColors;

    // Filter conversations
    List<ChatConversation> filteredList = conversations;
    if (_activeFilter == 'Online') {
      filteredList = conversations.where((c) => c.isOnline).toList();
    } else if (_activeFilter == 'Unread') {
      filteredList = conversations.where((c) => c.unreadCount > 0).toList();
    }

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
                          icon: Icon(LumioIcons.search, color: lumioColors.fg1),
                          onPressed: () => context.push('/chat/search'),
                          tooltip: 'Search',
                        ),
                        const SizedBox(width: AppSpacing.space1),
                        GestureDetector(
                          onTap: () {
                            // Focus profile tab in shell
                            ref.read(shellTabProvider.notifier).state = 3;
                          },
                          child: const CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.transparent,
                            child: UserAvatar(
                              displayName: 'You',
                              radius: 18,
                            ),
                          ),
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
                children: ['All', 'Online', 'Unread'].map((item) {
                  final isOn = item == _activeFilter;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.space2),
                    child: GestureDetector(
                      onTap: () => setState(() => _activeFilter = item),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.space4,
                        ),
                        decoration: BoxDecoration(
                          color: isOn ? AppColors.primary : Colors.transparent,
                          border: Border.all(
                            color: isOn ? Colors.transparent : lumioColors.hairline,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Center(
                          child: Text(
                            item,
                            style: AppTextStyles.secondaryMedium(
                              color: isOn ? Colors.white : lumioColors.fg1,
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
              child: filteredList.isEmpty
                  ? _buildEmptyState(lumioColors)
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.space4),
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final c = filteredList[index];
                        final isLast = index == filteredList.length - 1;
                        return Container(
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color,
                            border: Border(
                              left: BorderSide(color: lumioColors.hairline),
                              right: BorderSide(color: lumioColors.hairline),
                              top: index == 0
                                  ? BorderSide(color: lumioColors.hairline)
                                  : BorderSide.none,
                              bottom: BorderSide(color: lumioColors.hairline),
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: index == 0
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
                                top: index == 0
                                    ? const Radius.circular(AppRadius.xxl)
                                    : Radius.zero,
                                bottom: isLast
                                    ? const Radius.circular(AppRadius.xxl)
                                    : Radius.zero,
                              ),
                              onTap: () {
                                ref.read(chatsNotifierProvider.notifier).markAsRead(c.id);
                                context.push('/chat/${c.id}');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    // Avatar
                                    Stack(
                                      children: [
                                        UserAvatar(
                                          displayName: c.name,
                                          radius: 24,
                                        ),
                                        if (c.isOnline)
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
                                                  color: theme.cardTheme.color ?? Colors.transparent,
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
                                            c.name,
                                            style: AppTextStyles.bodySemibold(
                                              color: lumioColors.fg1,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              if (c.attachmentType != null) ...[
                                                _buildPreviewIcon(c.attachmentType!, lumioColors.fg2),
                                                const SizedBox(width: 6),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  c.snippet,
                                                  style: AppTextStyles.secondary(
                                                    color: c.isMissedCall ? AppColors.danger : lumioColors.fg2,
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
                                          c.time,
                                          style: AppTextStyles.secondary(
                                            color: c.unreadCount > 0 ? AppColors.primary : lumioColors.fg2,
                                          ).copyWith(
                                            fontWeight: c.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
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
                                              borderRadius: BorderRadius.circular(AppRadius.pill),
                                            ),
                                            constraints: const BoxConstraints(
                                              minWidth: 20,
                                            ),
                                            child: Text(
                                              c.unreadCount.toString(),
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
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Focus Family (Contacts) tab in Shell
          ref.read(shellTabProvider.notifier).state = 2;
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(LumioIcons.message, size: 26),
      ),
    );
  }

  Widget _buildPreviewIcon(String kind, Color color) {
    IconData iconData;
    switch (kind) {
      case 'image':
        iconData = LumioIcons.camera;
        break;
      case 'video':
        iconData = LumioIcons.video;
        break;
      case 'document':
        iconData = LumioIcons.attach;
        break;
      case 'voice':
        iconData = LumioIcons.mic;
        break;
      case 'call':
        iconData = LumioIcons.phone;
        break;
      default:
        iconData = LumioIcons.message;
    }
    return Icon(iconData, size: 14, color: color);
  }

  Widget _buildEmptyState(LumioColors lumioColors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Custom SVG illustration style glow
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
              'No chats yet',
              style: AppTextStyles.display(color: lumioColors.fg1).copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Add a family member to begin.',
              style: AppTextStyles.secondary(color: lumioColors.fg2),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}



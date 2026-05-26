import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/chat/data/conversation_repository.dart';
import '../../../features/chat/domain/conversation_list_notifier.dart';
import '../../../features/contacts/domain/contacts_notifier.dart';
import '../../../shared/models/conversation.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/lumio_icons.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _navigating = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<User> _matchedContacts(List<User> contacts) {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return contacts
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            (u.phone ?? '').contains(q) ||
            (u.email ?? '').toLowerCase().contains(q))
        .toList();
  }

  List<Conversation> _matchedConversations(List<Conversation> convos) {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return convos
        .where((c) =>
            c.otherUser.name.toLowerCase().contains(q) ||
            (c.lastMessagePreview?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  Future<void> _openChat(String userId, String? knownConvId) async {
    if (_navigating) return;
    setState(() => _navigating = true);
    try {
      final convId = knownConvId ??
          await ref
              .read(conversationRepositoryProvider)
              .getOrCreateConversation(userId);
      if (mounted) context.push('/chat/$convId');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open conversation')),
        );
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lumioColors = context.lumioColors;

    final contacts = ref.watch(contactsNotifierProvider).contacts;
    final convoAsync = ref.watch(conversationListProvider);
    final convos = convoAsync.value ?? [];

    final matchedContacts = _matchedContacts(contacts);
    final matchedConvos = _matchedConversations(convos);
    final hasResults = matchedContacts.isNotEmpty || matchedConvos.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Search bar ────────────────────────────────────────────────
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: lumioColors.hairline)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(LumioIcons.back, color: lumioColors.fg1),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: lumioColors.surfaceLo,
                        border: Border.all(color: lumioColors.hairline),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        children: [
                          Icon(LumioIcons.search,
                              size: 18, color: lumioColors.fg2),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              autofocus: true,
                              onChanged: (val) =>
                                  setState(() => _query = val.trim()),
                              style: AppTextStyles.body(color: lumioColors.fg1)
                                  .copyWith(fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Search chats and people',
                                hintStyle:
                                    AppTextStyles.body(color: lumioColors.fg2)
                                        .copyWith(fontSize: 15),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: lumioColors.hairlineStrong,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  LumioIcons.close,
                                  size: 14,
                                  color: theme.scaffoldBackgroundColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: _query.isEmpty
                    ? _buildEmptyPrompt(lumioColors)
                    : (!hasResults
                        ? _buildNoResults(lumioColors)
                        : _buildResults(
                            lumioColors, theme, matchedContacts, matchedConvos)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPrompt(LumioColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
        child: Text(
          "Find people by name, or any conversation you've had.",
          style: AppTextStyles.secondary(color: colors.fg2),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildResults(
    LumioColors colors,
    ThemeData theme,
    List<User> contacts,
    List<Conversation> convos,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── People ──────────────────────────────────────────────────────
        if (contacts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'PEOPLE · ${contacts.length}',
              style: AppTextStyles.caption(color: colors.fg2).copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              border: Border.all(color: colors.hairline),
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
            child: Column(
              children: List.generate(contacts.length, (i) {
                final u = contacts[i];
                final isLast = i == contacts.length - 1;
                return Column(
                  children: [
                    ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          UserAvatar(displayName: u.name, imageUrl: u.avatarUrl, radius: 22),
                          if (u.presence == PresenceStatus.online)
                            Positioned(
                              right: -1,
                              bottom: -1,
                              child: Container(
                                width: 12,
                                height: 12,
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
                      title: _highlighted(u.name, _query,
                          colors.fg1, AppTextStyles.bodySemibold(color: colors.fg1).copyWith(fontSize: 15)),
                      subtitle: Text(u.email ?? u.phone ?? '',
                          style: AppTextStyles.secondary(color: colors.fg2)
                              .copyWith(fontSize: 13)),
                      trailing: Material(
                        color: colors.surfaceLo,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _openChat(u.id, null),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(LumioIcons.message,
                                size: 18, color: AppColors.primary),
                          ),
                        ),
                      ),
                    ),
                    if (!isLast) Divider(height: 1, color: colors.hairline),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── Conversations ────────────────────────────────────────────────
        if (convos.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'CONVERSATIONS · ${convos.length}',
              style: AppTextStyles.caption(color: colors.fg2).copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              border: Border.all(color: colors.hairline),
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
            child: Column(
              children: List.generate(convos.length, (i) {
                final c = convos[i];
                final isLast = i == convos.length - 1;
                return Column(
                  children: [
                    ListTile(
                      leading: UserAvatar(
                        displayName: c.otherUser.name,
                        imageUrl: c.otherUser.avatarUrl,
                        radius: 22,
                      ),
                      title: Text(
                        c.otherUser.name,
                        style: AppTextStyles.bodySemibold(color: colors.fg1)
                            .copyWith(fontSize: 15),
                      ),
                      subtitle: c.lastMessagePreview != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _highlighted(
                                c.lastMessagePreview!,
                                _query,
                                colors.fg2,
                                TextStyle(fontSize: 13, color: colors.fg2),
                              ),
                            )
                          : null,
                      onTap: () => context.push('/chat/${c.id}?name=${Uri.encodeComponent(c.otherUser.name)}'),
                    ),
                    if (!isLast) Divider(height: 1, color: colors.hairline),
                  ],
                );
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNoResults(LumioColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colors.surfaceLo,
                border: Border.all(color: colors.hairline),
                shape: BoxShape.circle,
              ),
              child: Icon(LumioIcons.search, size: 36, color: colors.fg2),
            ),
            const SizedBox(height: 20),
            Text(
              'No results for "$_query"',
              style: AppTextStyles.display(color: colors.fg1)
                  .copyWith(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different word, or check your spelling.',
              style: AppTextStyles.secondary(color: colors.fg2),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _highlighted(String text, String term, Color baseColor, TextStyle base) {
    if (term.isEmpty) return Text(text, style: base, maxLines: 1, overflow: TextOverflow.ellipsis);
    final lower = text.toLowerCase();
    final idx = lower.indexOf(term.toLowerCase());
    if (idx < 0) return Text(text, style: base, maxLines: 1, overflow: TextOverflow.ellipsis);

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: base, children: [
        TextSpan(text: text.substring(0, idx)),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              text.substring(idx, idx + term.length),
              style: base.copyWith(
                  fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
        ),
        TextSpan(text: text.substring(idx + term.length)),
      ]),
    );
  }
}

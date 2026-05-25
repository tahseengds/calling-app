import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/lumio_icons.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Mock static data to search
  final _contacts = [
    {'id': 'rose', 'name': 'Grandma Rose', 'sub': '+1 (415) 555 · 0142', 'online': true},
    {'id': 'mike', 'name': 'Dad Mike', 'sub': '+1 (415) 555 · 0044', 'online': true},
    {'id': 'karen', 'name': 'Aunt Karen', 'sub': '+1 (415) 555 · 0244', 'online': false},
    {'id': 'jamie', 'name': 'Cousin Jamie', 'sub': '+1 (415) 555 · 0344', 'online': false},
  ];

  final _messages = [
    {'from': 'Grandma Rose', 'snippet': "Don't forget Sunday dinner", 'when': '2 min', 'convoId': 'rose'},
    {'from': 'Dad Mike', 'snippet': 'Family dinner at 7?', 'when': 'Tue', 'convoId': 'mike'},
    {'from': 'Aunt Karen', 'snippet': 'I brought enough for dinner left', 'when': 'Sun', 'convoId': 'karen'},
    {'from': 'Cousin Jamie', 'snippet': 'Family-tree-2026.pdf is here', 'when': 'Mon', 'convoId': 'jamie'},
  ];

  final _recentSearches = ['birthday party', 'sunday dinner', 'cousin jamie'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lumioColors = context.lumioColors;

    // Filter contacts and messages
    final matchedContacts = _contacts.where((c) {
      return c['name'].toString().toLowerCase().contains(_query.toLowerCase()) ||
          c['sub'].toString().contains(_query);
    }).toList();

    final matchedMessages = _messages.where((m) {
      return m['from'].toString().toLowerCase().contains(_query.toLowerCase()) ||
          m['snippet'].toString().toLowerCase().contains(_query.toLowerCase());
    }).toList();

    final hasResults = matchedContacts.isNotEmpty || matchedMessages.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Focused Search Bar ─────────────────────────────────────────
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
                          Icon(LumioIcons.search, size: 18, color: lumioColors.fg2),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              autofocus: true,
                              onChanged: (val) {
                                setState(() {
                                  _query = val.trim();
                                });
                              },
                              style: AppTextStyles.body(color: lumioColors.fg1).copyWith(fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Search chats and people',
                                hintStyle: AppTextStyles.body(color: lumioColors.fg2).copyWith(fontSize: 15),
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
                                setState(() {
                                  _query = '';
                                });
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

            // ── Search Results / Initial / Empty Body ──────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: _query.isEmpty
                    ? _buildInitialState(lumioColors)
                    : (!hasResults
                        ? _buildEmptyState(lumioColors)
                        : _buildResultsState(lumioColors, theme, matchedContacts, matchedMessages)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialState(LumioColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'RECENT SEARCHES',
            style: AppTextStyles.caption(color: colors.fg2).copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            border: Border.all(color: colors.hairline),
            borderRadius: BorderRadius.circular(AppRadius.xxl),
          ),
          child: Column(
            children: _recentSearches.map((rec) {
              final index = _recentSearches.indexOf(rec);
              final isLast = index == _recentSearches.length - 1;
              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.surfaceLo,
                        border: Border.all(color: colors.hairline),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(LumioIcons.history, size: 18, color: colors.fg2),
                    ),
                    title: Text(
                      rec,
                      style: AppTextStyles.bodyMedium(color: colors.fg1).copyWith(fontSize: 15),
                    ),
                    trailing: Transform.rotate(
                      angle: -0.785, // rotate -45 degrees for arrow link
                      child: Icon(Icons.arrow_upward, size: 16, color: colors.fg2),
                    ),
                    onTap: () {
                      _searchCtrl.text = rec;
                      setState(() {
                        _query = rec;
                      });
                    },
                  ),
                  if (!isLast) Divider(height: 1, color: colors.hairline),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Find people by name, or any message you've sent or received.",
              style: AppTextStyles.secondary(color: colors.fg2),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsState(
    LumioColors colors,
    ThemeData theme,
    List<Map<String, dynamic>> matchedContacts,
    List<Map<String, dynamic>> matchedMessages,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contacts heading
        if (matchedContacts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'FAMILY · ${matchedContacts.length}',
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
              children: matchedContacts.map((c) {
                final index = matchedContacts.indexOf(c);
                final isLast = index == matchedContacts.length - 1;
                return Column(
                  children: [
                    ListTile(
                      leading: Stack(
                        children: [
                          UserAvatar(
                            displayName: c['name'] as String,
                            radius: 22,
                          ),
                          if (c['online'] as bool)
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
                                    color: theme.cardTheme.color ?? Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        c['name'] as String,
                        style: AppTextStyles.bodySemibold(color: colors.fg1).copyWith(fontSize: 15),
                      ),
                      subtitle: Text(
                        c['sub'] as String,
                        style: AppTextStyles.secondary(color: colors.fg2).copyWith(fontSize: 13),
                      ),
                      trailing: Material(
                        color: colors.surfaceLo,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => context.push('/chat/${c['id']}'),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(LumioIcons.message, size: 18, color: AppColors.primary),
                          ),
                        ),
                      ),
                    ),
                    if (!isLast) Divider(height: 1, color: colors.hairline),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Messages heading
        if (matchedMessages.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'MESSAGES · ${matchedMessages.length}',
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
              children: matchedMessages.map((m) {
                final index = matchedMessages.indexOf(m);
                final isLast = index == matchedMessages.length - 1;
                return Column(
                  children: [
                    ListTile(
                      leading: UserAvatar(
                        displayName: m['from'] as String,
                        radius: 18,
                      ),
                      title: Text(
                        m['from'] as String,
                        style: AppTextStyles.bodySemibold(color: colors.fg1).copyWith(fontSize: 14),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _buildHighlightedText(m['snippet'] as String, _query, colors.fg2, colors.fg1),
                      ),
                      trailing: Text(
                        m['when'] as String,
                        style: AppTextStyles.caption(color: colors.fg2).copyWith(fontSize: 11),
                      ),
                      onTap: () => context.push('/chat/${m['convoId']}'),
                    ),
                    if (!isLast) Divider(height: 1, color: colors.hairline),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHighlightedText(String text, String term, Color normalColor, Color textColor) {
    if (term.isEmpty) {
      return Text(text, style: TextStyle(color: normalColor, fontSize: 13));
    }
    final lowercaseText = text.toLowerCase();
    final lowercaseTerm = term.toLowerCase();
    final index = lowercaseText.indexOf(lowercaseTerm);
    if (index < 0) {
      return Text(text, style: TextStyle(color: normalColor, fontSize: 13));
    }

    final before = text.substring(0, index);
    final match = text.substring(index, index + term.length);
    final after = text.substring(index + term.length);

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(color: normalColor, fontSize: 13),
        children: [
          TextSpan(text: before),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                match,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }

  Widget _buildEmptyState(LumioColors colors) {
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
              style: AppTextStyles.display(color: colors.fg1).copyWith(fontSize: 20),
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
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_colors.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/avatar.dart';
import '../domain/contacts_notifier.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<User> _filtered(List<User> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            u.phone.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contactsNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered(state.contacts);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  children: [
                    Text(
                      'Family',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => context.push('/contacts/add'),
                      icon: const Icon(Icons.person_add_outlined),
                      color: AppColors.primary,
                      tooltip: 'Add family member',
                    ),
                  ],
                ),
              ),
            ),

            // ── Search bar ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: _PillSearchBar(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),

            // ── Loading ──────────────────────────────────────────────────
            if (state.isLoading && state.contacts.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                ),
              )

            // ── Error ────────────────────────────────────────────────────
            else if (state.error != null && state.contacts.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_outlined,
                          size: 48,
                          color: isDark ? AppColors.darkFg3 : AppColors.lightFg2),
                      const SizedBox(height: 16),
                      Text(
                        'Could not load contacts',
                        style: TextStyle(
                          color:
                              isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () =>
                            ref.read(contactsNotifierProvider.notifier).load(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )

            // ── Empty state ──────────────────────────────────────────────
            else if (filtered.isEmpty && !state.isLoading)
              SliverFillRemaining(
                child: _EmptyState(
                  isSearching: _query.isNotEmpty,
                  onAdd: () => context.push('/contacts/add'),
                ),
              )

            // ── Contact list ─────────────────────────────────────────────
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final user = filtered[i];
                    return _ContactRow(
                      user: user,
                      onRemove: () => ref
                          .read(contactsNotifierProvider.notifier)
                          .removeContact(user.id),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Pill search bar ──────────────────────────────────────────────────────────

class _PillSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _PillSearchBar({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceLo : AppColors.lightSurfaceLo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 15,
          color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
        ),
        decoration: InputDecoration(
          hintText: 'Search family…',
          hintStyle: TextStyle(
            color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
            fontSize: 15,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
            size: 20,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

// ── Contact row ──────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  final User user;
  final VoidCallback onRemove;

  const _ContactRow({required this.user, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = user.presence == PresenceStatus.online;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: () => _showRemoveDialog(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar with presence dot
                Stack(
                  children: [
                    UserAvatar(
                      displayName: user.name,
                      imageUrl: user.avatarUrl,
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
                                  ? AppColors.darkSurface
                                  : AppColors.lightSurface,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                // Name + phone
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.phone,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                        ),
                      ),
                    ],
                  ),
                ),
                // Action buttons
                _ActionIcon(
                  icon: Icons.chat_bubble_outline,
                  tooltip: 'Message',
                  onTap: () {
                    // TODO prompt 13 — open chat
                  },
                ),
                const SizedBox(width: 4),
                _ActionIcon(
                  icon: Icons.phone_outlined,
                  tooltip: 'Call',
                  onTap: () {
                    // TODO prompt 15 — initiate call
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRemoveDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove family member?'),
        content: Text('${user.name} will be removed from your family list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onRemove();
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isSearching;
  final VoidCallback onAdd;

  const _EmptyState({required this.isSearching, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearching ? Icons.search_off : Icons.people_outline,
              size: 72,
              color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
            ),
            const SizedBox(height: 20),
            Text(
              isSearching
                  ? 'No results for that search'
                  : 'No family members yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (!isSearching) ...[
              Text(
                'Add your first family member\nto get started.',
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Add family member'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

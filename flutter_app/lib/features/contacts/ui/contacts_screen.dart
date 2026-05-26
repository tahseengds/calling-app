import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../domain/contacts_notifier.dart';
import '../../chat/data/conversation_repository.dart';
import '../../shell/ui/shell_screen.dart';
import '../../calling/domain/call_notifier.dart';
import '../../calling/domain/call_state.dart';
import '../../calling/presentation/widgets/permission_denied_screen.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  static const int _contactsTabIndex = 2;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _retryIfNeeded() {
    final state = ref.read(contactsNotifierProvider);
    if (!state.isLoading && (state.error != null || state.contacts.isEmpty)) {
      ref.read(contactsNotifierProvider.notifier).load();
    }
  }

  /// Permission-gated outgoing call. Mirrors the helpers in chat_rich_screen
  /// and call_history_screen so behaviour is consistent across entry points:
  /// mic required for any call; camera optional for video (denial downgrades
  /// to audio). The global call observer in app.dart picks up the new
  /// CallSession and pushes /call/outgoing — we just have to start it.
  Future<void> _placeCall(User other, CallType callType) async {
    var micStatus = await Permission.microphone.status;
    if (micStatus.isPermanentlyDenied) {
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const PermissionDeniedScreen(
              type: PermissionDeniedType.microphone),
        ));
      }
      return;
    }
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) return;
    }

    if (callType == CallType.video) {
      var camStatus = await Permission.camera.status;
      if (camStatus.isPermanentlyDenied) {
        if (mounted) {
          await Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const PermissionDeniedScreen(
                type: PermissionDeniedType.camera),
          ));
        }
        return;
      }
      if (!camStatus.isGranted) {
        camStatus = await Permission.camera.request();
        if (!camStatus.isGranted) callType = CallType.audio;
      }
    }

    if (!mounted) return;
    ref.read(callSessionProvider.notifier).startCall(
          PeerUser(
            id: other.id,
            name: other.name,
            avatarUrl: other.avatarUrl,
          ),
          callType,
        );
  }

  List<User> _filtered(List<User> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            (u.email ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // Auto-retry when the user switches to this tab: the contacts notifier
    // auto-loads on construction (mounted eagerly by IndexedStack), so a
    // failure right after login leaves the screen stuck on the retry button
    // until the user taps it. Re-trigger load whenever the contacts tab
    // becomes active and the previous attempt failed.
    ref.listen<int>(shellTabProvider, (prev, next) {
      if (next == _contactsTabIndex && prev != _contactsTabIndex) {
        _retryIfNeeded();
      }
    });

    final state = ref.watch(contactsNotifierProvider);
    final colors = context.lumioColors;
    final theme = Theme.of(context);
    final filtered = _filtered(state.contacts);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            Container(
              height: 64,
              padding: const EdgeInsets.only(left: 20, right: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Family',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.01,
                      color: colors.fg1,
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.push('/contacts/add'),
                    icon: Icon(LumioIcons.add, color: colors.fg1),
                    tooltip: 'Add family member',
                  ),
                ],
              ),
            ),

            // ── Search bar ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _PillSearchBar(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),

            // ── Content ──────────────────────────────────────────────────
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildContent(state, filtered, colors, theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ContactsState state, List<User> filtered, LumioColors colors, ThemeData theme) {
    if (state.isLoading && state.contacts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    Future<void> onRefresh() =>
        ref.read(contactsNotifierProvider.notifier).load();

    if (state.error != null && state.contacts.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LumioIcons.wifiOff, size: 48, color: colors.fg3),
                    const SizedBox(height: 16),
                    Text('Could not load contacts', style: TextStyle(color: colors.fg2)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: onRefresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (filtered.isEmpty && !state.isLoading) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: _EmptyState(
                isSearching: _query.isNotEmpty,
                onAdd: () => context.push('/contacts/add'),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ListView.separated(
          // AlwaysScrollableScrollPhysics enables pull-to-refresh even when
          // the list is short enough not to scroll on its own.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 1,
            color: colors.hairline,
          ),
          itemBuilder: (context, i) {
            final user = filtered[i];
            return _ContactRow(
              user: user,
              onRemove: () => ref
                  .read(contactsNotifierProvider.notifier)
                  .removeContact(user.id),
              onCallAudio: () => _placeCall(user, CallType.audio),
              onMessage: () async {
                try {
                  final convId = await ref
                      .read(conversationRepositoryProvider)
                      .getOrCreateConversation(user.id);
                  if (context.mounted) {
                    context.push('/chat/$convId?name=${Uri.encodeComponent(user.name)}');
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Could not open conversation')),
                    );
                  }
                }
              },
            );
          },
        ),
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
    final colors = context.lumioColors;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surfaceLo,
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 15,
          color: colors.fg1,
        ),
        decoration: InputDecoration(
          hintText: 'Search family',
          hintStyle: TextStyle(
            color: colors.fg3,
            fontSize: 15,
          ),
          prefixIcon: Icon(
            LumioIcons.search,
            color: colors.fg3,
            size: 20,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: colors.fg3,
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
  final VoidCallback onMessage;
  final VoidCallback onCallAudio;

  const _ContactRow({
    required this.user,
    required this.onRemove,
    required this.onMessage,
    required this.onCallAudio,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isOnline = user.presence == PresenceStatus.online;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: () => _showRemoveDialog(context),
        onTap: onMessage,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              // Avatar with presence dot. clipBehavior: Clip.none keeps
              // the dot visible — it's positioned 1px outside the avatar.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    displayName: user.name,
                    imageUrl: user.avatarUrl,
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
                            color: Theme.of(context).cardTheme.color ?? Colors.transparent,
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
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.fg1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.fg2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconButton(
                    icon: LumioIcons.message,
                    color: colors.fg1,
                    onTap: onMessage,
                  ),
                  const SizedBox(width: 4),
                  _IconButton(
                    icon: LumioIcons.phone,
                    color: AppColors.primary,
                    onTap: onCallAudio,
                  ),
                ],
              ),
            ],
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

class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _IconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: color),
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
    final colors = context.lumioColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearching ? LumioIcons.search : LumioIcons.people,
              size: 72,
              color: colors.fg3,
            ),
            const SizedBox(height: 20),
            Text(
              isSearching
                  ? 'No results for that search'
                  : 'No family yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.fg1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (!isSearching) ...[
              Text(
                'Add your family members to start chatting.',
                style: TextStyle(
                  fontSize: 15,
                  color: colors.fg2,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FlButton(
                label: 'Add family member',
                width: 220,
                onPressed: onAdd,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

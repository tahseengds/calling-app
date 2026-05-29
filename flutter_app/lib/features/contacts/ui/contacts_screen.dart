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
import '../../calling/domain/call_notifier.dart';
import '../../calling/domain/call_state.dart';
import '../../calling/presentation/widgets/permission_denied_screen.dart';

/// Family contacts. Pushed from the chats home "new chat" FAB (and from
/// any other future entry point). Tap a row to start a chat; long-press
/// to remove; tap the call icon to start a voice call.
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

  /// Permission-gated outgoing call. Mirrors the helpers in chat_rich_screen
  /// and call_history_screen so behaviour is consistent across entry points:
  /// mic required for any call; camera optional for video (denial downgrades
  /// to audio). The global call observer in app.dart picks up the new
  /// CallSession and pushes /call/outgoing — we just have to start it.
  Future<void> _placeCall(User other, CallType callType) async {
    var micStatus = await Permission.microphone.status;
    if (micStatus.isPermanentlyDenied) {
      if (!mounted) return;
      // Auto-retry: the gate pops `true` once mic is granted on return.
      final granted = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PermissionDeniedScreen(
            type: PermissionDeniedType.microphone),
      ));
      if (granted != true) return;
      micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) return;
    }
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) return;
    }

    if (callType == CallType.video) {
      var camStatus = await Permission.camera.status;
      if (camStatus.isPermanentlyDenied) {
        if (!mounted) return;
        final granted =
            await Navigator.of(context).push<bool>(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const PermissionDeniedScreen(
              type: PermissionDeniedType.camera),
        ));
        if (granted == true) {
          camStatus = await Permission.camera.status;
        } else {
          return;
        }
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
    final state = ref.watch(contactsNotifierProvider);
    final colors = context.lumioColors;
    final theme = Theme.of(context);
    final filtered = _filtered(state.contacts);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LumioIcons.back, color: colors.fg1),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Family',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: colors.fg1,
            letterSpacing: -0.01,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => context.push('/contacts/add'),
            icon: Icon(LumioIcons.add, color: colors.fg1),
            tooltip: 'Add family member',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── Search bar ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _PillSearchBar(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),

            // ── Content ──────────────────────────────────────────────────
            Expanded(
              child: _buildContent(state, filtered, colors, theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    ContactsState state,
    List<User> filtered,
    LumioColors colors,
    ThemeData theme,
  ) {
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
                    Text('Could not load contacts',
                        style: TextStyle(color: colors.fg2)),
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
      child: ListView.separated(
        // AlwaysScrollableScrollPhysics enables pull-to-refresh even when
        // the list is short enough not to scroll on its own.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: filtered.length,
        // Indented divider so it doesn't run under the avatar — gives the
        // list a contacts-app look instead of a card grid.
        separatorBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(left: 76),
          child: Divider(
            height: 1,
            thickness: 1,
            color: colors.hairline,
          ),
        ),
        itemBuilder: (context, i) {
          final user = filtered[i];
          return _ContactRow(
            user: user,
            onRemove: () async {
              final messenger = ScaffoldMessenger.of(context);
              await ref
                  .read(contactsNotifierProvider.notifier)
                  .removeContact(user.id);
              messenger.showSnackBar(
                SnackBar(content: Text('Removed ${user.name}')),
              );
            },
            onCallAudio: () => _placeCall(user, CallType.audio),
            onMessage: () async {
              try {
                final convId = await ref
                    .read(conversationRepositoryProvider)
                    .getOrCreateConversation(user.id);
                if (context.mounted) {
                  context.push(
                      '/chat/$convId?name=${Uri.encodeComponent(user.name)}');
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
    );
  }
}

// ── Pill search bar ──────────────────────────────────────────────────────────

class _PillSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _PillSearchBar({
    required this.controller,
    required this.onChanged,
  });

  @override
  State<_PillSearchBar> createState() => _PillSearchBarState();
}

class _PillSearchBarState extends State<_PillSearchBar> {
  @override
  void initState() {
    super.initState();
    // Rebuild when the clear-suffix should appear/disappear, without
    // forcing every parent to rebuild on every keystroke.
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colors.surfaceLo,
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        style: TextStyle(
          fontSize: 15,
          color: colors.fg1,
        ),
        textAlignVertical: TextAlignVertical.center,
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
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: colors.fg3,
                  tooltip: 'Clear',
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                )
              : null,
          filled: false,
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
    final theme = Theme.of(context);
    final isOnline = user.presence == PresenceStatus.online;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: () => _showRemoveDialog(context),
        onTap: onMessage,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                            color: theme.scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // Name + email
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
                    if ((user.email ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.email!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.fg2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action buttons — message (subtle) + call (primary).
              _IconButton(
                icon: LumioIcons.message,
                color: colors.fg1,
                tooltip: 'Message',
                onTap: onMessage,
              ),
              _IconButton(
                icon: LumioIcons.phone,
                color: AppColors.primary,
                tooltip: 'Call',
                onTap: onCallAudio,
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
  final String tooltip;
  final VoidCallback onTap;

  const _IconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
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
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: color),
          ),
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
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0x145B7CFA),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSearching ? LumioIcons.search : LumioIcons.people,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isSearching ? 'No matches' : 'No family yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.fg1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (!isSearching) ...[
              Text(
                'Add your family members by email to start chatting.',
                style: TextStyle(
                  fontSize: 15,
                  color: colors.fg2,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
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

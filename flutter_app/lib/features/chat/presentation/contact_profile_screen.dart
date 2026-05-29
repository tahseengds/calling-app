// contact_profile_screen.dart — WhatsApp-style contact info page.
//
// Opened by tapping the avatar/name in the chat header. Reads the live
// `chatProvider(conversationId)` for the other user + the loaded message
// window (used to surface shared media), and `contactsNotifierProvider`
// for the contact's email. Offers quick actions (message / audio / video),
// a shared-media strip, an info section, and block / remove.

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/calling/domain/call_notifier.dart';
import '../../../features/calling/domain/call_state.dart' show CallType, PeerUser;
import '../../../features/calling/presentation/widgets/permission_denied_screen.dart';
import '../../../features/contacts/domain/contacts_notifier.dart';
import '../../../shared/models/message.dart';
import '../../../shared/models/user.dart' as user_model;
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/error_snackbar.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../domain/chat_notifier.dart';
import 'media_gallery_screen.dart';

class ContactProfileScreen extends ConsumerStatefulWidget {
  final String conversationId;

  /// Fallback display name, in case the chat state hasn't hydrated the other
  /// user yet (e.g. a cold deep-link straight into this screen).
  final String? contactName;

  const ContactProfileScreen({
    super.key,
    required this.conversationId,
    this.contactName,
  });

  /// Convenience launcher used from the chat header.
  static Future<void> open(
    BuildContext context, {
    required String conversationId,
    String? contactName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContactProfileScreen(
          conversationId: conversationId,
          contactName: contactName,
        ),
      ),
    );
  }

  @override
  ConsumerState<ContactProfileScreen> createState() =>
      _ContactProfileScreenState();
}

class _ContactProfileScreenState extends ConsumerState<ContactProfileScreen> {
  // ── Helpers ────────────────────────────────────────────────────────────────

  bool _isOnline(user_model.User? u) =>
      u?.presence == user_model.PresenceStatus.online;

  /// Friendly "last seen" string (mirrors the chat header formatting).
  String _relativeLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  /// Email isn't carried on the chat-state user (the chat notifier builds it
  /// without an email), so resolve it from the contacts list by id.
  String? _resolveEmail(user_model.User? other, List<user_model.User> contacts) {
    if (other == null) return null;
    for (final c in contacts) {
      if (c.id == other.id) return c.email;
    }
    return other.email;
  }

  /// Shared photos & videos from the loaded message window, newest first.
  List<Message> _mediaMessages(List<Message> messages) {
    final media = messages
        .where((m) =>
            !m.isDeleted &&
            m.media != null &&
            (m.media!.url.isNotEmpty) &&
            (m.type == MessageType.image || m.type == MessageType.video))
        .toList();
    media.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return media;
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Return to the chat (we were pushed from it).
  void _openChat() => Navigator.of(context).maybePop();

  /// Place a call, mirroring the chat screen's permission handling so the
  /// flow is identical no matter where the call is started from.
  Future<void> _placeCall(user_model.User other, CallType callType) async {
    var micStatus = await Permission.microphone.status;
    if (micStatus.isPermanentlyDenied) {
      if (!mounted) return;
      final granted = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            const PermissionDeniedScreen(type: PermissionDeniedType.microphone),
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
          builder: (_) =>
              const PermissionDeniedScreen(type: PermissionDeniedType.camera),
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
          PeerUser(id: other.id, name: other.name, avatarUrl: other.avatarUrl),
          callType,
        );
  }

  /// Open the avatar full-screen (only when there's a real photo to show).
  void _viewAvatar(user_model.User other) {
    final url = other.avatarUrl;
    if (url == null || url.isEmpty) return;
    MediaGalleryScreen.open(
      context,
      items: [GalleryMediaItem(url: url, isVideo: false)],
      sender: other.name,
    );
  }

  void _openMedia(List<Message> media, int index) {
    MediaGalleryScreen.open(
      context,
      items: media
          .map((m) => GalleryMediaItem(
                url: m.media!.url,
                isVideo: m.type == MessageType.video,
              ))
          .toList(),
      initialIndex: index,
    );
  }

  void _copyEmail(String email) {
    Clipboard.setData(ClipboardData(text: email));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Email copied to clipboard')),
    );
  }

  void _confirmBlock(user_model.User other) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Block ${other.name}?'),
        content: const Text(
          'They won\'t be able to message or call you, and any ongoing call '
          'will end. You can unblock them later from Privacy → Blocked '
          'contacts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _runContactAction(
                () => ref
                    .read(contactsNotifierProvider.notifier)
                    .blockContact(other.id),
                'Blocked ${other.name}',
              );
            },
            child:
                const Text('Block', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(user_model.User other) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove family member?'),
        content: Text('${other.name} will be removed from your family list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _runContactAction(
                () => ref
                    .read(contactsNotifierProvider.notifier)
                    .removeContact(other.id),
                'Removed ${other.name}',
              );
            },
            child: const Text('Remove',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  /// Runs a block/remove action, confirms with a snackbar, then leaves both
  /// this screen and the underlying chat (the conversation no longer makes
  /// sense once the contact is gone).
  Future<void> _runContactAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      if (!mounted) return;
      // Pop the profile, then the chat beneath it.
      navigator.pop();
      navigator.maybePop();
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Something went wrong');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final theme = Theme.of(context);
    final chatState = ref.watch(chatProvider(widget.conversationId));
    final contacts = ref.watch(contactsNotifierProvider).contacts;

    final other = chatState.otherUser;
    final name = other?.name ?? widget.contactName ?? 'Contact';
    final online = _isOnline(other);
    final email = _resolveEmail(other, contacts);
    final media = _mediaMessages(chatState.messages);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LumioIcons.back, color: colors.fg1),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Contact info', style: AppTextStyles.h2(color: colors.fg1)),
        shape: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.space10),
        children: [
          _buildHeader(colors, name, online, email, other),
          const SizedBox(height: AppSpacing.space4),
          if (other != null)
            _buildQuickActions(other),
          const SizedBox(height: AppSpacing.space6),
          if (email != null && email.isNotEmpty)
            _buildInfoSection(colors, email),
          if (email != null && email.isNotEmpty)
            const SizedBox(height: AppSpacing.space6),
          _buildMediaSection(colors, media),
          const SizedBox(height: AppSpacing.space6),
          _buildEncryptionNote(colors),
          const SizedBox(height: AppSpacing.space6),
          if (other != null) _buildDangerZone(colors, other),
        ],
      ),
    );
  }

  Widget _buildHeader(
    LumioColors colors,
    String name,
    bool online,
    String? email,
    user_model.User? other,
  ) {
    final subtitle = online
        ? 'Online'
        : (other != null ? 'Last seen ${_relativeLastSeen(other.lastSeen)}' : '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space6,
        AppSpacing.space4,
        0,
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: other == null ? null : () => _viewAvatar(other),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(
                  displayName: name,
                  imageUrl: other?.avatarUrl,
                  radius: 56,
                ),
                if (online)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            name,
            textAlign: TextAlign.center,
            style: AppTextStyles.h1(color: colors.fg1),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space1),
            Text(
              subtitle,
              style: AppTextStyles.secondary(
                color: online ? AppColors.success : colors.fg2,
              ),
            ),
          ],
          if (email != null && email.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space1),
            Text(email, style: AppTextStyles.caption(color: colors.fg3)),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions(user_model.User other) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _QuickAction(
            icon: LumioIcons.message,
            label: 'Message',
            onTap: _openChat,
          ),
          _QuickAction(
            icon: LumioIcons.phone,
            label: 'Audio',
            onTap: () => _placeCall(other, CallType.audio),
          ),
          _QuickAction(
            icon: LumioIcons.video,
            label: 'Video',
            onTap: () => _placeCall(other, CallType.video),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(LumioColors colors, String email) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          leading: Icon(LumioIcons.mail, color: colors.fg2, size: 22),
          title: Text('Email', style: AppTextStyles.caption(color: colors.fg3)),
          subtitle: Text(email, style: AppTextStyles.body(color: colors.fg1)),
          trailing: IconButton(
            icon: Icon(LucideIcons.copy, color: colors.fg3, size: 18),
            tooltip: 'Copy',
            onPressed: () => _copyEmail(email),
          ),
          onTap: () => _copyEmail(email),
        ),
      ),
    );
  }

  Widget _buildMediaSection(LumioColors colors, List<Message> media) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.space2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MEDIA, LINKS & DOCS',
                  style: AppTextStyles.captionSemibold(color: colors.fg3)
                      .copyWith(letterSpacing: 0.8),
                ),
                if (media.isNotEmpty)
                  GestureDetector(
                    onTap: () => _openMedia(media, 0),
                    child: Row(
                      children: [
                        Text(
                          '${media.length}',
                          style: AppTextStyles.caption(color: colors.fg2),
                        ),
                        Icon(LumioIcons.chevronRight,
                            color: colors.fg3, size: 18),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (media.isEmpty)
            Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.space6,
                  horizontal: AppSpacing.space4,
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.image, color: colors.fg3, size: 20),
                    const SizedBox(width: AppSpacing.space3),
                    Expanded(
                      child: Text(
                        'No media shared yet',
                        style: AppTextStyles.secondary(color: colors.fg2),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: media.length > 9 ? 9 : media.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.space2),
                itemBuilder: (context, i) {
                  // The last visible tile becomes a "+N more" overlay when
                  // there are more items than we render inline.
                  final isOverflowTile = i == 8 && media.length > 9;
                  return _MediaThumb(
                    message: media[i],
                    overflowCount: isOverflowTile ? media.length - 9 : 0,
                    onTap: () => _openMedia(media, i),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEncryptionNote(LumioColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LumioIcons.lock, color: colors.fg3, size: 14),
          const SizedBox(width: AppSpacing.space2),
          Flexible(
            child: Text(
              'Messages and calls are kept private to your family.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(color: colors.fg3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone(LumioColors colors, user_model.User other) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          children: [
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              leading: Icon(LumioIcons.block, color: AppColors.danger),
              title: Text(
                'Block ${other.name}',
                style: AppTextStyles.bodySemibold(color: AppColors.danger),
              ),
              onTap: () => _confirmBlock(other),
            ),
            Divider(height: 1, indent: 56, color: colors.hairline),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              leading: Icon(LucideIcons.trash2, color: AppColors.danger),
              title: Text(
                'Remove contact',
                style: AppTextStyles.bodySemibold(color: AppColors.danger),
              ),
              onTap: () => _confirmRemove(other),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular icon button + label used in the quick-actions row.
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.primaryPill,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(label, style: AppTextStyles.caption(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

/// A single square media thumbnail. Renders the network/local image (or a
/// video's poster) and, for the last visible tile, an optional "+N" overlay.
class _MediaThumb extends StatelessWidget {
  final Message message;
  final int overflowCount;
  final VoidCallback onTap;

  const _MediaThumb({
    required this.message,
    required this.overflowCount,
    required this.onTap,
  });

  bool _isNetwork(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final media = message.media!;
    final isVideo = message.type == MessageType.video;
    // Videos prefer their poster; images use the media itself.
    final src = isVideo
        ? (media.thumbnailUrl?.isNotEmpty == true ? media.thumbnailUrl! : media.url)
        : media.url;

    Widget image;
    if (_isNetwork(src)) {
      image = CachedNetworkImage(
        imageUrl: src,
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        memCacheWidth: 252, // 84 × 3 for hi-DPI
        placeholder: (_, _) => Container(color: colors.surfaceHi),
        errorWidget: (_, _, _) => Container(
          color: colors.surfaceHi,
          child: Icon(LucideIcons.image, color: colors.fg3, size: 20),
        ),
      );
    } else {
      final path = src.startsWith('file://') ? Uri.parse(src).toFilePath() : src;
      image = Image.file(
        File(path),
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: colors.surfaceHi,
          child: Icon(LucideIcons.image, color: colors.fg3, size: 20),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: 84,
          height: 84,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              if (isVideo && overflowCount == 0)
                const Center(
                  child: Icon(LucideIcons.circlePlay,
                      color: Colors.white, size: 26),
                ),
              if (overflowCount > 0)
                Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  alignment: Alignment.center,
                  child: Text(
                    '+$overflowCount',
                    style: AppTextStyles.bodySemibold(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

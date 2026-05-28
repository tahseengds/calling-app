// chat_rich_screen.dart — UI redesigned to match HTML spec.
// Backend-wired version: reads/writes through chatProvider (chat_notifier)
// instead of chatThreadNotifierProvider (mock).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sound/flutter_sound.dart' hide PlayerState;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/domain/auth_notifier.dart';
import '../../../features/auth/domain/auth_state.dart';
import '../../../features/calling/domain/call_notifier.dart';
import '../../../features/calling/domain/call_state.dart'
    show CallType, PeerUser;
import '../../../features/calling/presentation/widgets/permission_denied_screen.dart';
import '../../../features/chat/domain/chat_notifier.dart';
import '../../../shared/models/message.dart';
import '../../../shared/models/user.dart' as user_model;
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/lumio_icons.dart';

// ─── Design tokens (from HTML spec) ──────────────────────────────────────────
// These mirror the CSS values used in the reference mockup so any future
// theme update only needs to touch this one block.

class _T {
  _T._();

  // Status colour for read receipts (not in AppColors).
  static const Color readTick = Color(0xFF7CC1FF);

  // Bubble: failed-send styling
  static const Color failedBubbleBg     = Color(0x2EFF6B6B); // 18 % opacity
  static const Color failedBubbleBorder = Color(0xFFFF6B6B);

  // Bubble: reply-preview inner block
  static const Color replyPreviewBg     = Color(0x24FFFFFF); // 14 % white
  static const Color replyPreviewBorder = Colors.white;

  // Typing-dot size
  static const double dotSize = 7.0;

  // Bubble corner radii
  static const double bigR  = 20.0;
  static const double tailR =  5.0; // the "tail" corner
}

// ─── ChatRichScreen ───────────────────────────────────────────────────────────

class ChatRichScreen extends ConsumerStatefulWidget {
  final String conversationId;
  /// Display name passed by the caller (e.g. from the contacts list).
  /// Takes priority over the hardcoded mock-ID switch so real UUID-based
  /// conversations show the correct name instead of the generic "Contact".
  final String? contactName;

  const ChatRichScreen({
    super.key,
    required this.conversationId,
    this.contactName,
  });

  @override
  ConsumerState<ChatRichScreen> createState() => _ChatRichScreenState();
}

class _ChatRichScreenState extends ConsumerState<ChatRichScreen> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  Message? _replyingTo;

  /// Refreshes relative timestamps ("Just now", "2m ago", app-bar "last seen…")
  /// while the screen is open. Without this they freeze at the value they had
  /// when the row was first built. 30 s strikes a balance: the "Just now" →
  /// absolute-time switch (at 2 minutes) lags by at most one tick, while the
  /// setState cost is negligible (ListView.builder only rebuilds visible rows).
  Timer? _clockTicker;

  /// Resolve the other user's display name. Prefers live data from the chat
  /// state, falls back to the contactName the caller passed (e.g. from
  /// conversation list), then a generic placeholder.
  String _otherName(user_model.User? other) =>
      other?.name ?? widget.contactName ?? 'Chat';

  /// Live presence flag — true when the other user is currently online.
  bool _isOnline(user_model.User? other) =>
      other?.presence == user_model.PresenceStatus.online;

  /// Authenticated user's id — used to decide which messages are "mine".
  /// Returns empty string in UI-only mode or before sign-in completes;
  /// in that case nothing will be marked mine, which is the correct
  /// fallback (the user shouldn't see this screen at all without auth).
  String get _currentUserId {
    final auth = ref.read(authNotifierProvider);
    return auth is AuthAuthenticated ? auth.me.id : '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    _clockTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _enterReplyMode(Message msg) {
    HapticFeedback.selectionClick();
    setState(() => _replyingTo = msg);
    FocusScope.of(context).requestFocus(_inputFocus);
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  /// Permission-gated outgoing call. Mirrors the helpers in chat_screen and
  /// call_history_screen so behaviour is consistent across entry points:
  /// mic required for any call; camera optional for video (denial downgrades
  /// to audio). Permanent denial routes to PermissionDeniedScreen.
  Future<void> _placeCall(user_model.User other, CallType callType) async {
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

  /// Friendly "last seen" string for the app bar subtitle.
  String _relativeLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 2) return 'recently';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(dt.toLocal());
  }

  /// Scroll to the newest message. The list is rendered with `reverse: true`
  /// so the newest message lives at scroll offset 0 — no max-extent estimation
  /// dance, just go to the top of the (visually inverted) viewport.
  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    ref
        .read(chatProvider(widget.conversationId).notifier)
        .sendText(text, replyToId: _replyingTo?.id);
    _inputCtrl.clear();
    _cancelReply();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _sendAudioMessage(File file, int duration) {
    if (duration < 1) {
      // Discard sub-second clips — likely an accidental tap on the mic.
      file.delete().catchError((_) => file);
      return;
    }
    // Pass the recorded duration so the optimistic bubble shows the real
    // length immediately — without it, the audio bubble would default to
    // 1s until the server response with the ffprobe-normalized value
    // overwrites it.
    ref.read(chatProvider(widget.conversationId).notifier).sendMedia(
          file,
          MessageType.audio,
          replyToId: _replyingTo?.id,
          durationSeconds: duration,
        );
    _cancelReply();
  }

  // ── Attachment pickers ─────────────────────────────────────────────────────

  /// Pick an image from the gallery, compress, send.
  Future<void> _attachImageFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      // Pre-resize on-device — saves bandwidth + the backend's WebP step
      // is faster on a smaller bitmap.
      maxWidth: 2560,
      imageQuality: 85,
    );
    if (picked == null) return;
    await _sendImageFile(File(picked.path));
  }

  /// Capture from the camera, compress, send.
  Future<void> _attachImageFromCamera() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required.')),
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2560,
      imageQuality: 85,
    );
    if (picked == null) return;
    await _sendImageFile(File(picked.path));
  }

  Future<void> _sendImageFile(File source) async {
    File toUpload = source;
    // flutter_image_compress can shave another 30–60 % off without visible
    // loss. Fall back to the picker's output if compression fails.
    try {
      final dir = await getTemporaryDirectory();
      final target =
          '${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        source.path,
        target,
        minWidth: 2560,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      if (compressed != null) {
        toUpload = File(compressed.path);
      }
    } catch (_) {
      // Use the picker's output as-is.
    }
    if (!mounted) return;
    ref
        .read(chatProvider(widget.conversationId).notifier)
        .sendMedia(toUpload, MessageType.image, replyToId: _replyingTo?.id);
    _cancelReply();
  }

  Future<void> _attachVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      // Cap absurdly-long picks so the upload doesn't take forever; the
      // backend still enforces its own 150 MB limit.
      maxDuration: const Duration(minutes: 10),
    );
    if (picked == null) return;
    if (!mounted) return;
    ref
        .read(chatProvider(widget.conversationId).notifier)
        .sendMedia(File(picked.path), MessageType.video,
            replyToId: _replyingTo?.id);
    _cancelReply();
  }

  Future<void> _attachDocument() async {
    // file_picker 12+ — pickFile returns a single PlatformFile.
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return;
    final path = picked.path;
    if (path == null) return;
    if (!mounted) return;
    ref
        .read(chatProvider(widget.conversationId).notifier)
        .sendMedia(File(path), MessageType.file, replyToId: _replyingTo?.id);
    _cancelReply();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(widget.conversationId));
    final lumioColors = context.lumioColors;
    final theme       = Theme.of(context);
    final other       = chatState.otherUser;

    // Auto-scroll to bottom when a new message arrives.
    ref.listen(chatProvider(widget.conversationId), (prev, next) {
      if ((prev?.messages.length ?? 0) < next.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(lumioColors, theme, other),
      body: Column(
        children: [
          Expanded(
            child: chatState.messages.isEmpty && !chatState.otherUserTyping
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: AppTextStyles.body(color: lumioColors.fg2),
                    ),
                  )
                : _buildMessageList(
                    chatState.messages,
                    chatState.otherUserTyping,
                    lumioColors,
                    other,
                  ),
          ),
          if (_replyingTo != null)
            _buildReplyPreviewBar(lumioColors, theme, other),
          _ChatInputBar(
            controller: _inputCtrl,
            focusNode: _inputFocus,
            onSend: _sendMessage,
            onRecordAudio: _sendAudioMessage,
            onAttach: () => _showAttachmentSheet(context),
            onChanged: () => ref
                .read(chatProvider(widget.conversationId).notifier)
                .onUserTyping(),
            lumioColors: lumioColors,
            theme: theme,
          ),
        ],
      ),
    );
  }

  /// Icon shown next to the body line for non-text messages. Returns null
  /// for text so we don't waste pixels on a chat-bubble icon when the
  /// caption itself already tells the user what they're replying to.
  IconData? _replyTypeIcon(MessageType type) => switch (type) {
        MessageType.image => Icons.image_outlined,
        MessageType.video => Icons.play_circle_outline_rounded,
        MessageType.audio => Icons.mic_none_rounded,
        MessageType.file => Icons.insert_drive_file_outlined,
        MessageType.text => null,
      };

  /// Source URL for the small square thumbnail on the right side of the
  /// preview bar. Videos prefer their poster (thumbnailUrl); images use the
  /// media itself. Returns null when there's nothing visual to show, so the
  /// bar collapses to the icon+text variant.
  String? _replyThumbnailUrl(Message msg) {
    final media = msg.media;
    if (media == null) return null;
    if (msg.type == MessageType.video) {
      return media.thumbnailUrl?.isNotEmpty == true ? media.thumbnailUrl : null;
    }
    if (msg.type == MessageType.image) return media.url;
    return null;
  }

  /// Human label for the body line of the reply preview bar. Caption wins
  /// when present (e.g. "Sunset!" on a photo); otherwise we fall back to the
  /// media type so the user at least sees *what kind* of message they're
  /// replying to rather than the previous "Attachment" placeholder.
  String _replyBodyLabel(Message msg) {
    final caption = msg.content?.trim();
    if (caption != null && caption.isNotEmpty) return caption;
    return switch (msg.type) {
      MessageType.image => 'Photo',
      MessageType.video => 'Video',
      MessageType.audio => 'Voice note',
      MessageType.file => 'File',
      MessageType.text => '',
    };
  }

  Widget _buildReplyPreviewBar(
      LumioColors c, ThemeData t, user_model.User? other) {
    final isDark = t.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF222B42) : const Color(0xFFF8FAFE);
    final border = isDark ? const Color(0xFF37425E) : const Color(0xFFE3E7F0);

    final replySender =
        _replyingTo!.senderId == _currentUserId ? 'You' : _otherName(other);
    final replyText = _replyBodyLabel(_replyingTo!);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  replySender,
                  style: AppTextStyles.bodySemibold(color: AppColors.primary).copyWith(fontSize: 13),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyTypeIcon(_replyingTo!.type) != null) ...[
                      Icon(
                        _replyTypeIcon(_replyingTo!.type),
                        size: 13,
                        color: c.fg2,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        replyText,
                        style: AppTextStyles.body(color: c.fg2)
                            .copyWith(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_replyThumbnailUrl(_replyingTo!) != null) ...[
            const SizedBox(width: 8),
            _ReplyThumbnail(url: _replyThumbnailUrl(_replyingTo!)!),
          ],
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: c.fg2),
            tooltip: 'Back',
            onPressed: _cancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
    LumioColors colors,
    ThemeData theme,
    user_model.User? other,
  ) {
    final name = _otherName(other);
    final online = _isOnline(other);
    final subtitle = online
        ? 'online'
        : (other != null
            ? 'last seen ${_relativeLastSeen(other.lastSeen)}'
            : '');
    return AppBar(
      backgroundColor: theme.scaffoldBackgroundColor,
      elevation: 0,
      leadingWidth: 48,
      leading: IconButton(
        icon: Icon(LumioIcons.back, color: colors.fg1),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          // Avatar with online dot
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(
                displayName: name,
                imageUrl: other?.avatarUrl,
                radius: 18,
              ),
              if (online)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 10,
                    height: 10,
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
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.bodySemibold(color: colors.fg1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: AppTextStyles.secondary(
                      color: online ? AppColors.success : colors.fg2,
                    ).copyWith(fontSize: 12),
                  ),
              ],
          ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(LumioIcons.phone, color: colors.fg1, size: 22),
          tooltip: 'Voice Call',
          onPressed: other == null
              ? null
              : () => _placeCall(other, CallType.audio),
        ),
        IconButton(
          icon: Icon(LumioIcons.video, color: colors.fg1, size: 22),
          tooltip: 'Video Call',
          onPressed: other == null
              ? null
              : () => _placeCall(other, CallType.video),
        ),
        const SizedBox(width: 4),
      ],
      shape: Border(bottom: BorderSide(color: colors.hairline)),
    );
  }

  // ── Message list ────────────────────────────────────────────────────────────

  Widget _buildMessageList(
    List<Message> messages,
    bool otherUserTyping,
    LumioColors colors,
    user_model.User? other,
  ) {
    // Build items: inject date separators between day boundaries.
    final items = <_ListItem>[];
    DateTime? lastDate;

    for (final msg in messages) {
      final msgDate = DateUtils.dateOnly(msg.createdAt);
      if (lastDate == null || msgDate != lastDate) {
        items.add(_ListItem.separator(msgDate));
        lastDate = msgDate;
      }
      items.add(_ListItem.message(msg));
    }

    // Live typing indicator — only when the remote peer is composing.
    if (otherUserTyping) {
      items.add(_ListItem.typing());
    }

    final myId = _currentUserId;

    // Render reversed: ListView's index 0 sits at the visual bottom of the
    // viewport, so the newest message is on screen the moment the chat opens
    // — no post-frame scroll dance, no estimated-extent jitter. The items
    // list is built oldest→newest, so reversing makes [0] = newest.
    final reversedItems = items.reversed.toList(growable: false);

    return ListView.builder(
      controller: _scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      itemCount: reversedItems.length,
      itemBuilder: (context, i) {
        final item = reversedItems[i];
        return switch (item.kind) {
          _ItemKind.separator => _DateSeparator(
              date:   item.date!,
              colors: colors,
            ),
          _ItemKind.typing => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _TypingIndicator(colors: colors),
            ),
          _ItemKind.message => _MessageRow(
              msg:            item.msg!,
              mine:           item.msg!.senderId == myId,
              myUserId:       myId,
              colors:         colors,
              conversationId: widget.conversationId,
              onRetry: (id) => ref
                  .read(chatProvider(widget.conversationId).notifier)
                  .retryMessage(id),
              onDelete: (id) => ref
                  .read(chatProvider(widget.conversationId).notifier)
                  .deleteMessage(id),
              onShowContext: (msg, mine, topOffset) =>
                  _showContextMenu(context, msg, mine, topOffset),
              onSwipeReply: () => _enterReplyMode(item.msg!),
              onToggleReaction: (id, emoji) => ref
                  .read(chatProvider(widget.conversationId).notifier)
                  .toggleReaction(id, emoji),
            ),
        };
      },
    );
  }

  // ── Bottom sheets ───────────────────────────────────────────────────────────

  void _showContextMenu(BuildContext context, Message msg, bool mine, double topOffset) {
    final c = context.lumioColors;
    final t = Theme.of(context);

    showGeneralDialog(
      context: context,
      pageBuilder: (context, anim1, anim2) {
        return _ContextMenuOverlay(
          msg: msg,
          mine: mine,
          colors: c,
          theme: t,
          topOffset: topOffset,
          onDelete: () {
            ref
                .read(chatProvider(widget.conversationId).notifier)
                .deleteMessage(msg.id);
          },
          onReact: (emoji) {
            ref
                .read(chatProvider(widget.conversationId).notifier)
                .toggleReaction(msg.id, emoji);
          },
        );
      },
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0x8C0A101E), // rgba(10, 16, 30, 0.55)
      transitionBuilder: (context, anim1, anim2, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3 * anim1.value, sigmaY: 3 * anim1.value),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 240),
    );
  }

  void _showAttachmentSheet(BuildContext context) {
    final c = context.lumioColors;
    final t = Theme.of(context);
    
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.cardTheme.color ?? t.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetHandle(colors: c),
              const SizedBox(height: 12),
              Text(
                'Send something',
                style: AppTextStyles.bodySemibold(color: c.fg1).copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.01,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose where the file comes from.',
                style: AppTextStyles.body(color: c.fg2).copyWith(fontSize: 13),
              ),
              const SizedBox(height: 18),
              _AttachListItem(
                icon: Icons.image_outlined,
                title: 'Photo',
                subtitle: 'Pick one from your gallery.',
                color: AppColors.primary,
                c: c,
                onTap: () {
                  Navigator.of(context).pop();
                  _attachImageFromGallery();
                },
              ),
              const SizedBox(height: 10),
              _AttachListItem(
                icon: Icons.play_circle_outline_rounded,
                title: 'Video',
                subtitle: 'Send a video from your gallery.',
                color: AppColors.danger,
                c: c,
                onTap: () {
                  Navigator.of(context).pop();
                  _attachVideo();
                },
              ),
              const SizedBox(height: 10),
              _AttachListItem(
                icon: Icons.camera_alt_outlined,
                title: 'Camera',
                subtitle: 'Take a new photo.',
                color: AppColors.success,
                c: c,
                onTap: () {
                  Navigator.of(context).pop();
                  _attachImageFromCamera();
                },
              ),
              const SizedBox(height: 10),
              _AttachListItem(
                icon: Icons.insert_drive_file_outlined,
                title: 'Document',
                subtitle: 'Share a file, like a PDF.',
                color: const Color(0xFFF0A93B),
                c: c,
                onTap: () {
                  Navigator.of(context).pop();
                  _attachDocument();
                },
              ),
              const SizedBox(height: 14),
              Text(
                'Tap outside to cancel.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption(color: c.fg3).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── List item model ──────────────────────────────────────────────────────────

enum _ItemKind { message, separator, typing }

class _ListItem {
  final _ItemKind kind;
  final Message?  msg;
  final DateTime? date;

  const _ListItem._({required this.kind, this.msg, this.date});

  factory _ListItem.message(Message m)   => _ListItem._(kind: _ItemKind.message,   msg: m);
  factory _ListItem.separator(DateTime d) => _ListItem._(kind: _ItemKind.separator, date: d);
  factory _ListItem.typing()              => _ListItem._(kind: _ItemKind.typing);
}

// ─── Date separator ───────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date, required this.colors});

  final DateTime    date;
  final LumioColors colors;

  String get _label {
    final now = DateTime.now();
    if (DateUtils.isSameDay(date, now))               return 'Today';
    if (DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('MMMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            // slightly elevated surface so it floats above the chat bg
            color:        colors.surfaceLo,
            borderRadius: BorderRadius.circular(999),
            border:       Border.all(color: colors.hairline),
          ),
          child: Text(
            _label,
            style: AppTextStyles.caption(color: colors.fg2).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Typing indicator ─────────────────────────────────────────────────────────
// Three dots with a staggered bob animation, exactly as in the HTML mockup.

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.colors});
  final LumioColors colors;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>>   _anims;

  // Matches the CSS animation values from the HTML spec:
  //   duration 1.1 s, delays 0 / 0.15 / 0.3 s
  static const Duration _period = Duration(milliseconds: 1100);
  static const List<Duration> _delays = [
    Duration.zero,
    Duration(milliseconds: 150),
    Duration(milliseconds: 300),
  ];

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) {
      final ctrl = AnimationController(vsync: this, duration: _period);
      Future.delayed(_delays[i], () {
        if (mounted) ctrl.repeat();
      });
      return ctrl;
    });
    _anims = _ctrls.map((c) {
      return TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0, end: -5), weight: 35),
        TweenSequenceItem(tween: Tween(begin: -5, end: 0),  weight: 35),
        TweenSequenceItem(tween: ConstantTween(0),           weight: 30),
      ]).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut));
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: const BorderRadius.only(
            topLeft:     Radius.circular(_T.bigR),
            topRight:    Radius.circular(_T.bigR),
            bottomRight: Radius.circular(_T.bigR),
            bottomLeft:  Radius.circular(_T.tailR),
          ),
          border: Border.all(color: colors.hairline),
          boxShadow: const [
            BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _anims[i],
              builder: (_, _) => Transform.translate(
                offset: Offset(0, _anims[i].value),
                child: Container(
                  width:  _T.dotSize,
                  height: _T.dotSize,
                  margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                  decoration: BoxDecoration(
                    color: colors.fg2,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─── Message row ──────────────────────────────────────────────────────────────

class _SwipeToReplyWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipe;

  const _SwipeToReplyWrapper({required this.child, required this.onSwipe});

  @override
  State<_SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<_SwipeToReplyWrapper> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _ctrl.addListener(() {
      setState(() {
        _dragOffset = _dragOffset * (1 - _ctrl.value);
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.primaryDelta! > 0 || _dragOffset > 0) {
          setState(() {
            _dragOffset += details.primaryDelta!;
            if (_dragOffset < 0) _dragOffset = 0;
            if (_dragOffset > 60) _dragOffset = 60 + (_dragOffset - 60) * 0.2;
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset > 40) {
          widget.onSwipe();
        }
        _ctrl.forward(from: 0);
      },
      child: Transform.translate(
        offset: Offset(_dragOffset, 0),
        child: widget.child,
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.msg,
    required this.mine,
    required this.myUserId,
    required this.colors,
    required this.conversationId,
    required this.onRetry,
    required this.onDelete,
    required this.onShowContext,
    required this.onSwipeReply,
    required this.onToggleReaction,
  });

  final Message     msg;
  final bool        mine;
  final String      myUserId;
  final LumioColors colors;
  final String      conversationId;
  final void Function(String id)              onRetry;
  final void Function(String id)              onDelete;
  final void Function(Message msg, bool mine, double topOffset) onShowContext;
  final VoidCallback                          onSwipeReply;
  final void Function(String messageId, String emoji) onToggleReaction;

  bool get _isDeleted => msg.isDeleted;
  ReplyPreview? get _replyTo => msg.replyTo;
  bool get _isFailed => msg.status == MessageStatus.failed;

  @override
  Widget build(BuildContext context) {
    return _SwipeToReplyWrapper(
      onSwipe: onSwipeReply,
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // ── Bubble ───────────────────────────────────────────────────
              Builder(
                builder: (bubbleContext) {
                  // Deleted bubbles have no actionable context (reply/copy/
                  // forward/delete are all meaningless on a tombstone). Failed
                  // bubbles use long-press to open the retry/delete sheet via
                  // onTap instead.
                  final canShowContext = !_isFailed && !_isDeleted;
                  return GestureDetector(
                    onLongPress: canShowContext ? () {
                      final box = bubbleContext.findRenderObject() as RenderBox?;
                      final offset = box?.localToGlobal(Offset.zero).dy ?? MediaQuery.of(bubbleContext).size.height / 2;
                      onShowContext(msg, mine, offset);
                    } : null,
                    onTap: _isFailed ? () => _showFailedSheet(context) : null,
                    child: _isDeleted
                        ? _DeletedBubble(mine: mine, colors: colors)
                        : _Bubble(
                            mine:    mine,
                            msg:     msg,
                            replyTo: _replyTo,
                            colors:  colors,
                          ),
                  );
                }
              ),
              // ── Reaction chips ─────────────────────────────────────────────
              if (!_isDeleted && msg.reactions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _ReactionChipRow(
                    reactions: msg.reactions,
                    myUserId: myUserId,
                    colors: colors,
                    onTap: (emoji) => onToggleReaction(msg.id, emoji),
                  ),
                ),
              const SizedBox(height: 4),

              // ── Timestamp + status ────────────────────────────────────────
              _Timestamp(
                time:   msg.createdAt,
                mine:   mine,
                status: msg.status,
                colors: colors,
                onRetry: _isFailed ? () => onRetry(msg.id) : null,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _showFailedSheet(BuildContext context) {
    final colors = context.lumioColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetHandle(colors: colors),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    "THIS MESSAGE COULDN'T SEND",
                    style: AppTextStyles.caption(color: colors.fg2).copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              _SheetOptionList(colors: colors, children: [
                _SheetOption(
                  icon:  LumioIcons.history,
                  label: 'Retry',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.of(context).pop();
                    onRetry(msg.id);
                  },
                ),
                _SheetOption(
                  icon:  Icons.delete_outline,
                  label: 'Delete',
                  color: AppColors.danger,
                  onTap: () {
                    Navigator.of(context).pop();
                    onDelete(msg.id);
                  },
                ),
              ]),
              const SizedBox(height: 10),
              _CancelButton(colors: colors, onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Reply-bar thumbnail ─────────────────────────────────────────────────────
// 40×40 square shown on the right of the swipe-to-reply preview bar so the
// composer can see *which* photo/video they're replying to, not just "Photo".

class _ReplyThumbnail extends StatelessWidget {
  const _ReplyThumbnail({required this.url});
  final String url;

  bool get _isLocal => !url.startsWith('http://') && !url.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_isLocal) {
      child = Image.file(
        File(url.startsWith('file://') ? Uri.parse(url).toFilePath() : url),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0x33000000)),
      );
    } else {
      child = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => const ColoredBox(color: Color(0x22000000)),
        errorWidget: (_, _, _) => const ColoredBox(color: Color(0x33000000)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 40, height: 40, child: child),
    );
  }
}

// ─── Reaction chips ──────────────────────────────────────────────────────────
// Rendered under each bubble. One chip per distinct emoji, count omitted when
// it's a single reaction. Tapping a chip toggles the current user's own
// reaction for that emoji (matches WhatsApp/iMessage interaction).

class _ReactionChipRow extends StatelessWidget {
  const _ReactionChipRow({
    required this.reactions,
    required this.myUserId,
    required this.colors,
    required this.onTap,
  });

  final List<ReactionSummary> reactions;
  final String myUserId;
  final LumioColors colors;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions.map((r) {
        final mine = r.reactedByUser(myUserId);
        return _ReactionChip(
          emoji: r.emoji,
          count: r.count,
          mine: mine,
          colors: colors,
          onTap: () => onTap(r.emoji),
        );
      }).toList(growable: false),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.colors,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool mine;
  final LumioColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = mine
        ? AppColors.primary.withValues(alpha: 0.18)
        : (isDark ? const Color(0xFF222B42) : Colors.white);
    final border = mine
        ? AppColors.primary.withValues(alpha: 0.55)
        : colors.hairline;
    final countColor = mine ? AppColors.primary : colors.fg2;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            if (count > 1) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: AppTextStyles.caption(color: countColor).copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Bubble variants ──────────────────────────────────────────────────────────

// Normal / failed bubble
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.mine,
    required this.msg,
    required this.colors,
    this.replyTo,
  });

  final bool        mine;
  final Message     msg;
  final LumioColors colors;
  final ReplyPreview? replyTo;

  bool get _isFailed => msg.status == MessageStatus.failed;
  bool get _isAudio => msg.type == MessageType.audio;
  bool get _isImage => msg.type == MessageType.image;
  bool get _isVideo => msg.type == MessageType.video;
  bool get _isFile  => msg.type == MessageType.file;
  bool get _isVisualMedia => _isImage || _isVideo;
  bool get _hasCaption => (msg.content?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final Color bg = _isFailed
        ? _T.failedBubbleBg
        : mine
            ? AppColors.primary
            : (Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor);

    final Color fg = (mine || _isFailed) ? Colors.white : colors.fg1;

    final BorderSide side = _isFailed
        ? const BorderSide(color: _T.failedBubbleBorder)
        : mine
            ? BorderSide.none
            : BorderSide(color: colors.hairline);

    final radius = _bubbleRadius(mine);

    // Image/video bubbles get a small uniform inset so the preview's clipped
    // corners sit just inside the bubble outline. Reply-preview and caption
    // both demand the existing 6/10 padding layout. Plain text/audio/file
    // keep the original 14/10 padding.
    final EdgeInsets bubblePadding = _isVisualMedia && replyTo == null
        ? const EdgeInsets.all(4)
        : replyTo != null
            ? const EdgeInsets.fromLTRB(6, 6, 6, 10)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);

    return Container(
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: radius,
        border:       Border.fromBorderSide(side),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      padding: bubblePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Reply preview ─────────────────────────────────────────────
          if (replyTo != null) ...[
            _ReplyPreview(
              senderName: replyTo!.senderName,
              content:    replyTo!.text,
              mine:       mine,
              colors:     colors,
            ),
            const SizedBox(height: 8),
          ],
          // ── Body: image / video / file / audio / text ─────────────────
          if (_isVisualMedia)
            _MediaVisualContent(
              msg: msg,
              fgColor: fg,
              innerRadius: BorderRadius.circular(_T.bigR - 6),
            )
          else if (_isFile)
            _FileMessageContent(msg: msg, fgColor: fg)
          else
            Padding(
              padding: replyTo != null
                  ? const EdgeInsets.symmetric(horizontal: 8)
                  : EdgeInsets.zero,
              child: _isAudio
                  ? _AudioMessageContent(
                      audioUrl: msg.media?.url,
                      durationSeconds: msg.media?.durationSeconds ?? 0,
                      fgColor: fg,
                    )
                  : Text(
                      msg.content ?? '',
                      style: AppTextStyles.body(color: fg),
                    ),
            ),
          // ── Optional caption under image / video ──────────────────────
          if (_isVisualMedia && _hasCaption) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
              child: Text(
                msg.content ?? '',
                style: AppTextStyles.body(color: fg),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Visual media (image / video) bubble content ────────────────────────────
// Renders the optimistic local file (for not-yet-uploaded messages) or the
// remote URL (once the server has it). Videos overlay a play badge on top of
// the first-frame thumbnail when available, falling back to a solid tile.

class _MediaVisualContent extends StatelessWidget {
  const _MediaVisualContent({
    required this.msg,
    required this.fgColor,
    required this.innerRadius,
  });

  final Message msg;
  final Color fgColor;
  final BorderRadius innerRadius;

  bool get _isVideo => msg.type == MessageType.video;

  /// Choose the best image source: thumbnail for videos (when present),
  /// otherwise the media's primary url. Returns null if the message has no
  /// media attached yet (shouldn't normally happen for sent media).
  String? get _previewUrl {
    final media = msg.media;
    if (media == null) return null;
    if (_isVideo && media.thumbnailUrl != null && media.thumbnailUrl!.isNotEmpty) {
      return media.thumbnailUrl;
    }
    return media.url;
  }

  bool _isLocalPath(String url) =>
      !url.startsWith('http://') && !url.startsWith('https://');

  Widget _buildPreview(BuildContext context) {
    final url = _previewUrl;
    // Constrain to a reasonable preview size — the bubble already caps width
    // to 78% of the screen, this caps height so a tall portrait doesn't push
    // the whole list off-screen.
    final maxH = MediaQuery.of(context).size.height * 0.42;

    Widget child;
    if (url == null) {
      child = _MediaPlaceholder(isVideo: _isVideo);
    } else if (_isLocalPath(url)) {
      child = Image.file(
        File(url.startsWith('file://') ? Uri.parse(url).toFilePath() : url),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _MediaPlaceholder(isVideo: _isVideo),
      );
    } else {
      child = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => _MediaLoading(isVideo: _isVideo),
        errorWidget: (_, _, _) => _MediaPlaceholder(isVideo: _isVideo),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH, minHeight: 120, minWidth: 160),
      child: ClipRRect(
        borderRadius: innerRadius,
        child: AspectRatio(
          aspectRatio: _aspectRatio(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (_isVideo)
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x80000000),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              if (msg.status == MessageStatus.sending)
                const Positioned(
                  right: 6,
                  bottom: 6,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _aspectRatio() {
    final w = msg.media?.width;
    final h = msg.media?.height;
    if (w != null && h != null && w > 0 && h > 0) {
      // Clamp so very-tall or very-wide media stays usable in the list.
      return (w / h).clamp(0.6, 1.8);
    }
    return 4 / 3;
  }

  @override
  Widget build(BuildContext context) {
    return _buildPreview(context);
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.isVideo});
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x33000000),
      child: Center(
        child: Icon(
          isVideo ? Icons.movie_outlined : Icons.broken_image_outlined,
          color: Colors.white70,
          size: 36,
        ),
      ),
    );
  }
}

class _MediaLoading extends StatelessWidget {
  const _MediaLoading({required this.isVideo});
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x22000000),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        ),
      ),
    );
  }
}

// ─── File / document bubble content ─────────────────────────────────────────

class _FileMessageContent extends StatelessWidget {
  const _FileMessageContent({required this.msg, required this.fgColor});

  final Message msg;
  final Color fgColor;

  String get _fileName {
    final url = msg.media?.url ?? '';
    if (url.isEmpty) return 'Attachment';
    final cleaned = url.split('?').first;
    final segment = cleaned.split(RegExp(r'[\\/]')).last;
    return segment.isEmpty ? 'Attachment' : segment;
  }

  String? get _sizeLabel {
    final bytes = msg.media?.sizeBytes;
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final subColor = fgColor.withValues(alpha: 0.75);
    final size = _sizeLabel;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_outlined, color: fgColor, size: 28),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySemibold(color: fgColor).copyWith(fontSize: 14),
              ),
              if (size != null)
                Text(
                  size,
                  style: AppTextStyles.caption(color: subColor).copyWith(fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AudioMessageContent extends StatefulWidget {
  /// URL of the uploaded voice note, or a local file path for optimistic
  /// (not-yet-synced) outgoing messages. Null if the bubble is rendered
  /// before media has been attached (treated as an unplayable placeholder).
  final String? audioUrl;
  final int durationSeconds;
  final Color fgColor;

  const _AudioMessageContent({
    required this.audioUrl,
    required this.durationSeconds,
    required this.fgColor,
  });

  @override
  State<_AudioMessageContent> createState() => _AudioMessageContentState();
}

class _AudioMessageContentState extends State<_AudioMessageContent> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  Duration _position = Duration.zero;
  Duration? _trueDuration; // populated by the player once metadata loads
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _isPlaying = s == PlayerState.playing;
        if (s == PlayerState.completed) {
          _position = Duration.zero;
        }
      });
    });
    _positionSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _trueDuration = d);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return;
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    if (_player.state == PlayerState.paused) {
      await _player.resume();
      return;
    }
    // First play (or replay after completion). Pick the right source: a
    // file:// or absolute path is treated as a local file (optimistic UI
    // path), anything else as a remote URL.
    final source = (url.startsWith('http://') || url.startsWith('https://'))
        ? UrlSource(url)
        : DeviceFileSource(url.startsWith('file://')
            ? Uri.parse(url).toFilePath()
            : url);
    await _player.play(source);
  }

  Duration get _totalDuration =>
      _trueDuration ??
      Duration(seconds: widget.durationSeconds > 0 ? widget.durationSeconds : 1);

  double get _progress {
    final total = _totalDuration.inMilliseconds;
    if (total <= 0) return 0.0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fgColor;
    final unplayable = widget.audioUrl == null || widget.audioUrl!.isEmpty;
    // While idle, show the message's total length. While playing/paused, show
    // the current playhead — matches how every other messaging app does it.
    final displayDuration = (_isPlaying || _position > Duration.zero)
        ? _position
        : _totalDuration;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: unplayable ? null : _togglePlay,
          child: Opacity(
            opacity: unplayable ? 0.5 : 1.0,
            child: Icon(
              _isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: fg,
              size: 32,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: LinearProgressIndicator(
            value: _progress,
            backgroundColor: fg.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(fg),
            borderRadius: BorderRadius.circular(2),
            minHeight: 4,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            _fmt(displayDuration),
            style: AppTextStyles.bodySemibold(color: fg).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// Deleted-message pill — dashed outline, italic label, no-entry icon
class _DeletedBubble extends StatelessWidget {
  const _DeletedBubble({required this.mine, required this.colors});
  final bool        mine;
  final LumioColors colors;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color:        colors.hairlineStrong,
        radius:       20,
        dashLength:   5,
        gapLength:    4,
        strokeWidth:  1.2,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.not_interested_rounded, size: 14, color: colors.fg2),
            const SizedBox(width: 8),
            Text(
              'This message was deleted',
              style: AppTextStyles.body(color: colors.fg2).copyWith(
                fontStyle: FontStyle.italic,
                fontSize:  14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reply preview block shown inside a sent bubble
class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({
    required this.senderName,
    required this.content,
    required this.mine,
    required this.colors,
  });

  final String      senderName;
  final String      content;
  final bool        mine;
  final LumioColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: mine ? _T.replyPreviewBg : colors.surfaceLo,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: mine ? _T.replyPreviewBorder : AppColors.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            senderName,
            style: AppTextStyles.caption(
              color: mine ? Colors.white.withValues(alpha: 0.9) : AppColors.primary,
            ).copyWith(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption(
              color: mine ? Colors.white.withValues(alpha: 0.8) : colors.fg2,
            ).copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Timestamp + status row ───────────────────────────────────────────────────

class _Timestamp extends StatelessWidget {
  const _Timestamp({
    required this.time,
    required this.mine,
    required this.status,
    required this.colors,
    this.onRetry,
  });

  final DateTime    time;
  final bool        mine;
  final MessageStatus status;
  final LumioColors colors;
  final VoidCallback? onRetry;

  bool get _isFailed => status == MessageStatus.failed;

  String get _label {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 2) return 'Just now';
    return DateFormat('h:mm a').format(time);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _label,
          style: AppTextStyles.caption(
            color: _isFailed ? AppColors.danger : colors.fg2,
          ).copyWith(
            fontSize:   11,
            fontWeight: _isFailed ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        if (mine) ...[
          const SizedBox(width: 4),
          _MessageStatusIcon(status: status, defaultColor: colors.fg2),
        ],
        // "Retry" tappable label — only on failed, in the timestamp row
        if (_isFailed && onRetry != null) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              'Retry',
              style: AppTextStyles.caption(color: AppColors.danger).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Status icon ──────────────────────────────────────────────────────────────

class _MessageStatusIcon extends StatelessWidget {
  const _MessageStatusIcon({
    required this.status,
    required this.defaultColor,
  });

  final MessageStatus status;
  final Color         defaultColor;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      // Sending — thin circle outline (matches the HTML SVG circle)
      MessageStatus.sending => SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.4,
            color:       defaultColor.withValues(alpha: 0.55),
          ),
        ),
      // Sent — single tick
      MessageStatus.sent => _SingleTick(color: defaultColor.withValues(alpha: 0.55)),
      // Delivered — double tick, dimmed
      MessageStatus.delivered => _DoubleTick(color: defaultColor.withValues(alpha: 0.55)),
      // Read — double tick, accent blue
      MessageStatus.read => const _DoubleTick(color: _T.readTick),
      // Failed — warning triangle (HTML: triangle with ! inside)
      MessageStatus.failed => const Icon(
          Icons.warning_rounded,
          size:  12,
          color: AppColors.danger,
        ),
    };
  }
}

// Single check (✓)
class _SingleTick extends StatelessWidget {
  const _SingleTick({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(LumioIcons.check, size: 12, color: color);
  }
}

// Double check (✓✓) — overlapping two check icons, same technique as the HTML
// which stacks two polylines with a horizontal offset.
class _DoubleTick extends StatelessWidget {
  const _DoubleTick({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, child: Icon(LumioIcons.check, size: 12, color: color)),
          Positioned(left: 5, child: Icon(LumioIcons.check, size: 12, color: color)),
        ],
      ),
    );
  }
}

// ─── Bubble radius helper ─────────────────────────────────────────────────────
// Matches exactly the CSS border-radius values in the HTML spec:
//   sent:     20px 20px 6px 20px  (TL TR BR BL) → bottom-right is tail
//   received: 20px 20px 20px 6px  (TL TR BR BL) → bottom-left  is tail

BorderRadius _bubbleRadius(bool mine) => mine
    ? const BorderRadius.only(
        topLeft:     Radius.circular(_T.bigR),
        topRight:    Radius.circular(_T.bigR),
        bottomLeft:  Radius.circular(_T.bigR),
        bottomRight: Radius.circular(_T.tailR),
      )
    : const BorderRadius.only(
        topLeft:     Radius.circular(_T.bigR),
        topRight:    Radius.circular(_T.bigR),
        bottomLeft:  Radius.circular(_T.tailR),
        bottomRight: Radius.circular(_T.bigR),
      );

// ─── Dashed border painter ────────────────────────────────────────────────────
// Flutter has no built-in dashed-border support; this CustomPainter draws
// the rounded-rectangle dashed outline used by the deleted-message bubble.

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
    required this.strokeWidth,
  });

  final Color  color;
  final double radius;
  final double dashLength;
  final double gapLength;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = strokeWidth
      ..style       = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
          size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );

    final path         = Path()..addRRect(rrect);
    final metrics      = path.computeMetrics().first;
    final totalLength  = metrics.length;

    double dist = 0;
    bool   draw = true;

    while (dist < totalLength) {
      final segLen = draw ? dashLength : gapLength;
      if (draw) {
        canvas.drawPath(
          metrics.extractPath(dist, math.min(dist + segLen, totalLength)),
          paint,
        );
      }
      dist += segLen;
      draw  = !draw;
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color       != color       ||
      old.radius      != radius      ||
      old.dashLength  != dashLength  ||
      old.gapLength   != gapLength   ||
      old.strokeWidth != strokeWidth;
}

// ─── Chat input bar ───────────────────────────────────────────────────────────
// Layout:
//
//   ┌─────────────────────────────────────┐  ┌───────┐
//   │  [TextField…………………………………………] [📎] │  │ 🎤/➤ │
//   └─────────────────────────────────────┘  └───────┘
//          ← pill (flex 1) →                  ← 48 px ──┘
//
// The attach button sits INSIDE the pill on the right.
// The mic/send button is a standalone 48-px circle OUTSIDE the pill.
// When the text field has content the send icon fades in; mic fades out.

class _ChatInputBar extends StatefulWidget {
  const _ChatInputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onRecordAudio,
    required this.onAttach,
    required this.lumioColors,
    required this.theme,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode    focusNode;
  final VoidCallback onSend;
  /// Fires when a voice note completes (not cancelled). The first argument
  /// is the recorded .aac file; the second is its duration in whole seconds.
  /// Callers are responsible for uploading and deleting the file.
  final void Function(File file, int seconds) onRecordAudio;
  final VoidCallback onAttach;
  final LumioColors  lumioColors;
  final ThemeData    theme;

  /// Fired on every text change so the parent can emit typing events to
  /// the realtime layer. Chat-notifier's onUserTyping is self-debouncing,
  /// so it's safe to call on every keystroke.
  final VoidCallback? onChanged;

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar>
    with TickerProviderStateMixin {
  late final AnimationController _iconCtrl;
  late final Animation<double>   _sendOpacity;
  late final Animation<double>   _micOpacity;

  // Recording animations
  late final AnimationController _pulseCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _trashCtrl;

  bool _hasText = false;

  // Recording state
  final GlobalKey _micKey = GlobalKey();
  bool _isRecording = false;
  bool _isCancelling = false;
  double _dragOffset = 0.0;
  int _recordSeconds = 0;
  Timer? _timer;

  // Audio recorder. Pre-warmed in initState (when mic permission is already
  // granted) so the hold-to-record gesture captures instantly instead of
  // paying the permission + codec-init cost on the first press.
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderOpen = false;
  String? _currentRecordingPath;
  String? _tempDirPath;

  @override
  void initState() {
    super.initState();
    _iconCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
    _sendOpacity = CurvedAnimation(parent: _iconCtrl,               curve: Curves.easeOut);
    _micOpacity  = CurvedAnimation(parent: ReverseAnimation(_iconCtrl), curve: Curves.easeOut);

    _pulseCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _trashCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 450))..repeat(reverse: true);

    widget.controller.addListener(_onTextChanged);
    _prewarmRecorder();
  }

  /// Resolve the temp directory and open the recorder ahead of the first
  /// press. We only open the recorder when the mic permission is already
  /// granted — opening a chat shouldn't pop a permission dialog.
  Future<void> _prewarmRecorder() async {
    try {
      _tempDirPath = (await getTemporaryDirectory()).path;
    } catch (_) {}
    try {
      if (await Permission.microphone.isGranted && !_recorderOpen) {
        await _recorder.openRecorder();
        _recorderOpen = true;
      }
    } catch (e) {
      debugPrint('[chat] recorder prewarm failed: $e');
    }
  }

  void _onTextChanged() {
    // Always notify the parent on each keystroke so realtime "typing"
    // events propagate. The notifier debounces internally.
    widget.onChanged?.call();

    final has = widget.controller.text.trim().isNotEmpty;
    if (has == _hasText) return;
    setState(() => _hasText = has);
    has ? _iconCtrl.forward() : _iconCtrl.reverse();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _timer?.cancel();
    // Best-effort: stop and close the recorder if dispose interrupts a hold.
    if (_recorderOpen) {
      _recorder.closeRecorder().catchError((_) {});
      _recorderOpen = false;
    }
    _iconCtrl.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _trashCtrl.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    // Instant tactile feedback the moment the hold registers — before any
    // async permission/codec work — so the press never feels laggy.
    HapticFeedback.lightImpact();

    // Fast path: the recorder is usually pre-warmed and permission already
    // granted, so we skip straight to startRecorder. Only pop the permission
    // dialog when we genuinely don't have access yet.
    if (!await Permission.microphone.isGranted) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        // Surface the failure so the long-press doesn't just do nothing.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone access is required to record a voice note.'),
            ),
          );
        }
        return;
      }
    }

    try {
      if (!_recorderOpen) {
        await _recorder.openRecorder();
        _recorderOpen = true;
      }
      final dirPath = _tempDirPath ??= (await getTemporaryDirectory()).path;
      final path =
          '$dirPath/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _recorder.startRecorder(toFile: path, codec: Codec.aacADTS);
      _currentRecordingPath = path;
    } catch (e) {
      // If the recorder can't start (codec, hardware, etc.), tell the user
      // instead of failing silently. They'll see the long-press did nothing
      // otherwise.
      debugPrint('[chat] recorder startup failed: $e');
      _currentRecordingPath = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start the recorder. Try again.'),
          ),
        );
      }
      return;
    }

    if (!mounted) {
      // Widget was unmounted while permissions were pending; tear down.
      await _recorder.stopRecorder().catchError((_) => null);
      return;
    }

    setState(() {
      _isRecording = true;
      _isCancelling = false;
      _dragOffset = 0.0;
      _recordSeconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  void _updateRecording(LongPressMoveUpdateDetails details) {
    setState(() {
      _dragOffset = details.offsetFromOrigin.dx;
      if (_dragOffset > 0) _dragOffset = 0; // Don't drag right
      _isCancelling = _dragOffset < -100;
    });
  }

  Future<void> _endRecording() async {
    _timer?.cancel();
    final wasCancelling = _isCancelling;
    final seconds = _recordSeconds;
    final path = _currentRecordingPath;
    _currentRecordingPath = null;

    if (mounted) {
      setState(() {
        _isRecording = false;
        _isCancelling = false;
        _dragOffset = 0.0;
        _recordSeconds = 0;
      });
    }

    if (!_recorderOpen) return;
    try {
      await _recorder.stopRecorder();
    } catch (_) {
      return;
    }

    if (path == null) return;
    final file = File(path);
    if (wasCancelling || seconds < 1) {
      // Discard cancelled or near-zero clips.
      file.delete().catchError((_) => file);
      return;
    }
    if (!await file.exists()) return;
    widget.onRecordAudio(file, seconds);
  }

  // ── Constants (documented in class-level comment above) ────────────────────
  static const double _kIconBtn    = 36.0;
  static const double _kIconSz     = 20.0;
  static const double _kSendBtn    = 48.0;
  static const double _kRecBtn     = 56.0;
  static const double _kPillRadius = 24.0;

  String get _formattedTime {
    final mins = (_recordSeconds ~/ 60).toString();
    final secs = (_recordSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.lumioColors;
    final t = widget.theme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, thickness: 0.5, color: c.hairline),
        ColoredBox(
          color: t.scaffoldBackgroundColor,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: _isRecording ? _buildRecordingBar(c, t) : _buildIdleBar(c, t),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdleBar(LumioColors c, ThemeData t) {
    return Row(
      key: const ValueKey('idle'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _buildPill(c, t)),
        const SizedBox(width: 8),
        _buildIdleMicButton(c),
      ],
    );
  }

  Widget _buildPill(LumioColors c, ThemeData t) {
    return Material(
      color: t.cardTheme.color ?? t.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kPillRadius),
        side: BorderSide(color: c.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Text field ──────────────────────────────────────────────────
            Expanded(
              child: TextField(
                controller:          widget.controller,
                focusNode:           widget.focusNode,
                textCapitalization:  TextCapitalization.sentences,
                style:               AppTextStyles.body(color: c.fg1),
                minLines:            1,
                maxLines:            5,
                textInputAction:     TextInputAction.newline,
                decoration: InputDecoration(
                  hintText:       'Message…',
                  hintStyle:      AppTextStyles.body(color: c.fg2),
                  border:         InputBorder.none,
                  enabledBorder:  InputBorder.none,
                  focusedBorder:  InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                ),
              ),
            ),

            // ── In-pill attach button ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: Transform.rotate(
                angle: math.pi / 4,
                child: _PillIconButton(
                  icon:    Icons.attach_file_rounded,
                  color:   c.fg2,
                  size:    _kIconBtn,
                  iconSz:  _kIconSz,
                  onTap:   widget.onAttach,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleMicButton(LumioColors c) {
    // RawGestureDetector with a short-duration long-press so hold-to-record
    // engages quickly. The default GestureDetector long-press is ~500ms, which
    // (on top of recorder init) is what made starting a voice note feel laggy.
    return RawGestureDetector(
      key: _micKey,
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (r) => r.onTap = _hasText ? widget.onSend : null,
        ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(
            duration: const Duration(milliseconds: 180),
          ),
          (r) {
            r.onLongPressStart = _hasText ? null : (_) => _startRecording();
            r.onLongPressMoveUpdate = _hasText ? null : _updateRecording;
            r.onLongPressEnd = _hasText ? null : (_) => _endRecording();
            r.onLongPressCancel = _hasText ? null : _endRecording;
          },
        ),
      },
      child: Material(
        color:           AppColors.primary,
        shape:           const CircleBorder(),
        clipBehavior:    Clip.antiAlias,
        shadowColor:     AppColors.primary.withValues(alpha: 0.32),
        elevation:       6,
        child: SizedBox(
          width:  _kSendBtn,
          height: _kSendBtn,
          child: Stack(
            alignment: Alignment.center,
            children: [
              FadeTransition(
                opacity: _micOpacity,
                child: const Icon(Icons.mic_rounded, color: Colors.white, size: _kIconSz + 2),
              ),
              FadeTransition(
                opacity: _sendOpacity,
                child: Icon(LumioIcons.send, color: Colors.white, size: _kIconSz),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingBar(LumioColors c, ThemeData t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF222B42) : Colors.white; // rgb(34, 43, 66) : rgb(255, 255, 255)
    final fgColor = isDark ? const Color(0xFFF2F4F8) : const Color(0xFF1A2235); // fg1
    final hintColor = isDark ? const Color(0xFF9AA3B8) : const Color(0xFF6B7488); // fg2
    
    return SizedBox(
      key: const ValueKey('recording'),
      height: _kRecBtn,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Background pill
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.only(left: 14, right: 76),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: c.hairline),
                boxShadow: [
                  BoxShadow(color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0x051A2235), offset: const Offset(0, 1)),
                ],
              ),
              child: _isCancelling ? _buildCancelContent(c) : _buildRecordingContent(c, fgColor, hintColor),
            ),
          ),
          
          // Floating Mic Button
          Positioned(
            right: 0,
            child: Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: GestureDetector(
                key: _micKey,
                onLongPressStart: (_) => _startRecording(),
                onLongPressMoveUpdate: _updateRecording,
                onLongPressEnd: (_) => _endRecording(),
                onLongPressCancel: _endRecording,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: _kRecBtn,
                  height: _kRecBtn,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isCancelling ? AppColors.danger : AppColors.primary,
                    border: Border.all(color: t.scaffoldBackgroundColor, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: _isCancelling ? AppColors.danger.withValues(alpha: 0.22) : AppColors.primary.withValues(alpha: 0.22),
                        spreadRadius: 6,
                      ),
                      BoxShadow(
                        color: _isCancelling ? AppColors.danger.withValues(alpha: 0.42) : AppColors.primary.withValues(alpha: 0.38),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(Icons.mic_rounded, color: Colors.white, size: _kIconSz + 2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingContent(LumioColors c, Color fgColor, Color hintColor) {
    return Row(
      children: [
        // Pulsing red dot
        FadeTransition(
          opacity: _pulseCtrl,
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.danger,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Timer
        SizedBox(
          width: 44,
          child: Text(
            _formattedTime,
            style: AppTextStyles.bodySemibold(color: fgColor).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        // Slide to cancel shimmer
        Expanded(
          child: Center(
            child: AnimatedBuilder(
              animation: _shimmerCtrl,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.5 + 0.5 * math.sin(_shimmerCtrl.value * math.pi),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_left_rounded, color: hintColor, size: 16),
                      const SizedBox(width: 4),
                      Text('Slide to cancel', style: AppTextStyles.bodyMedium(color: hintColor).copyWith(fontSize: 14)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCancelContent(LumioColors c) {
    return Row(
      children: [
        // Bouncing trash icon
        AnimatedBuilder(
          animation: _trashCtrl,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, -2 * math.sin(_trashCtrl.value * math.pi)),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger.withValues(alpha: 0.22),
                  border: Border.all(color: AppColors.danger, width: 2),
                ),
                child: const Center(
                  child: Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Release to cancel',
            style: AppTextStyles.bodySemibold(color: AppColors.danger).copyWith(fontSize: 15),
          ),
        ),
      ],
    );
  }
}

// Small tappable icon inside the input pill
class _PillIconButton extends StatelessWidget {
  const _PillIconButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.iconSz,
    required this.onTap,
  });

  final IconData     icon;
  final Color        color;
  final double       size;
  final double       iconSz;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:           Colors.transparent,
      shape:           const CircleBorder(),
      clipBehavior:    Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width:  size,
          height: size,
          child: Center(child: Icon(icon, color: color, size: iconSz)),
        ),
      ),
    );
  }
}

// ─── Shared bottom-sheet widgets ──────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle({required this.colors});
  final LumioColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color:        colors.hairlineStrong,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _SheetOptionList extends StatelessWidget {
  const _SheetOptionList({required this.colors, required this.children});
  final LumioColors  colors;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border:       Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  final Color?       color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).iconTheme.color;
    return ListTile(
      leading: Icon(icon, color: c),
      title:   Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w500)),
      onTap:   onTap,
      dense:   true,
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.colors, required this.onTap});
  final LumioColors  colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize:     const Size(double.infinity, 48),
        shape:           const StadiumBorder(),
        side:            BorderSide(color: colors.hairlineStrong),
        foregroundColor: colors.fg1,
      ),
      onPressed: onTap,
      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Attachment sheet item ────────────────────────────────────────────────────

class _AttachListItem extends StatelessWidget {
  const _AttachListItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.c,
    required this.onTap,
  });

  final IconData     icon;
  final String       title;
  final String       subtitle;
  final Color        color;
  final LumioColors  c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surfaceLo,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.133),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Icon(icon, color: color, size: 26),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodySemibold(color: c.fg1).copyWith(
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.caption(color: c.fg2).copyWith(
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.fg2, size: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Floating Context Menu ───────────────────────────────────────────────────

class _ContextMenuOverlay extends StatelessWidget {
  final Message msg;
  final bool mine;
  final LumioColors colors;
  final ThemeData theme;
  final VoidCallback onDelete;
  final void Function(String emoji) onReact;
  final double topOffset;

  const _ContextMenuOverlay({
    required this.msg,
    required this.mine,
    required this.colors,
    required this.theme,
    required this.onDelete,
    required this.onReact,
    required this.topOffset,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    
    // Tokens derived from HTML spec
    final menuBg = isDark ? const Color(0xFF222B42) : Colors.white; 
    final fg = isDark ? const Color(0xFFF2F4F8) : const Color(0xFF1A2235);
    final border = isDark ? const Color(0xFF37425E) : const Color(0xFFE3E7F0);

    // Calculate a safe top position so it doesn't overflow screen
    final screenH = MediaQuery.of(context).size.height;
    final padding = MediaQuery.of(context).padding;
    double top = topOffset - 58; // 58 = approx height of emoji pill + spacing
    if (top < padding.top + 10) {
      top = padding.top + 10;
    }
    // Approx total height of context menu is ~350px. Prevent bottom overflow.
    if (top + 350 > screenH - padding.bottom) {
      top = screenH - padding.bottom - 350;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dismiss area
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            top: top,
            left: 14,
            right: 14,
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
              // Emoji Reaction Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: menuBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: border),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 32, offset: Offset(0, 12)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final emoji in ['❤️', '👍', '😂', '😮', '😢'])
                      _ReactionPillButton(
                        onTap: () {
                          Navigator.of(context).pop();
                          onReact(emoji);
                        },
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    _ReactionPillButton(
                      onTap: () async {
                        final picked = await _showEmojiPickerSheet(context);
                        if (picked != null) {
                          if (context.mounted) Navigator.of(context).pop();
                          onReact(picked);
                        }
                      },
                      child: Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? const Color(0xFF1F273C) : const Color(0xFFF8FAFE),
                          border: Border.all(color: border),
                        ),
                        child: Icon(Icons.add, color: isDark ? const Color(0xFF9AA3B8) : const Color(0xFF6B7488), size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Highlighted Message Bubble Clone
              _Bubble(mine: mine, msg: msg, colors: colors),
              const SizedBox(height: 12),

              // Action List
              Container(
                width: 220,
                decoration: BoxDecoration(
                  color: menuBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 40, offset: Offset(0, 16)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ContextMenuAction(
                      icon: Icons.reply_rounded, 
                      label: 'Reply', 
                      color: fg, 
                      border: border, 
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    _ContextMenuAction(
                      icon: Icons.copy_rounded, 
                      label: 'Copy', 
                      color: fg, 
                      border: border, 
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    _ContextMenuAction(
                      icon: Icons.shortcut_rounded, 
                      label: 'Forward', 
                      color: fg, 
                      border: border, 
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    if (mine)
                      _ContextMenuAction(
                        icon: Icons.delete_outline_rounded, 
                        label: 'Delete', 
                        color: AppColors.danger, 
                        border: Colors.transparent, 
                        onTap: () {
                          Navigator.of(context).pop();
                          onDelete();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],));
  }
}

/// Wraps a reaction-pill child in a fixed-size tappable hit area. Visual size
/// stays the same as before; this only ensures fingers actually land on a
/// gesture handler instead of inert Text.
class _ReactionPillButton extends StatelessWidget {
  const _ReactionPillButton({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Curated extra-emoji picker shown when the user taps the "+" on the
/// reaction pill. Keeps things small — a real emoji-picker package would
/// add MBs to the bundle for a marginal UX improvement on a tap-to-react.
Future<String?> _showEmojiPickerSheet(BuildContext context) {
  const grid = <String>[
    '❤️', '👍', '👎', '😂', '😮', '😢', '🔥', '🎉',
    '🙏', '👏', '💯', '🤔', '😍', '😎', '😡', '🤝',
    '✅', '❌', '🥳', '👀', '🫡', '💪', '🙌', '😴',
  ];
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).cardTheme.color,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
    ),
    builder: (sheetContext) {
      final c = sheetContext.lumioColors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetHandle(colors: c),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Pick a reaction',
                  style: AppTextStyles.bodySemibold(color: c.fg1).copyWith(
                    fontSize: 16,
                  ),
                ),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 8,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final emoji in grid)
                    InkWell(
                      onTap: () => Navigator.of(sheetContext).pop(emoji),
                      borderRadius: BorderRadius.circular(8),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ContextMenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color border;
  final VoidCallback onTap;

  const _ContextMenuAction({
    required this.icon, 
    required this.label, 
    required this.color, 
    required this.border, 
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 14),
                Text(
                  label, 
                  style: AppTextStyles.bodySemibold(color: color).copyWith(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// chat_rich_screen.dart — UI redesigned to match HTML spec
// Status: UI-only. TODO comments mark where backend wiring belongs.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/message.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../domain/chat_thread_notifier.dart';

// ─── Design tokens (from HTML spec) ──────────────────────────────────────────
// These mirror the CSS values used in the reference mockup so any future
// theme update only needs to touch this one block.

class _T {
  _T._();

  // Primary — same as AppColors.primary (rgb 91 124 250)
  static const Color primary = Color(0xFF5B7CFA);

  // Status colours
  static const Color success     = Color(0xFF34C77B); // online dot
  static const Color danger      = Color(0xFFFF6B6B); // failed message
  static const Color readTick    = Color(0xFF7CC1FF); // double-tick when read

  // Bubble: failed-send styling
  static const Color failedBubbleBg     = Color(0x2EFF6B6B); // 18 % opacity
  static const Color failedBubbleBorder = Color(0xFFFF6B6B);

  // Bubble: reply-preview inner block
  static const Color replyPreviewBg     = Color(0x24FFFFFF); // 14 % white
  static const Color replyPreviewBorder = Colors.white;

  // Date-separator
  static const Color separatorFg = Color(0xFF9AA3B8); // dark-mode value;
                                                        // light overridden via theme

  // Typing-dot size
  static const double dotSize = 7.0;

  // Bubble corner radii
  static const double bigR  = 20.0;
  static const double tailR =  5.0; // the "tail" corner

  // Input-bar geometry (see _ChatInputBar for explanation)
  static const double pillRadius  = 24.0;
  static const double sendBtnSize = 48.0;
  static const double pillVPad    =  6.0;
  static const double pillHPad    = 14.0;
  static const double iconBtnSize = 36.0;
  static const double iconSize    = 20.0;
}

// ─── ChatRichScreen ───────────────────────────────────────────────────────────

class ChatRichScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatRichScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatRichScreen> createState() => _ChatRichScreenState();
}

class _ChatRichScreenState extends ConsumerState<ChatRichScreen> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  Message? _replyingTo;

  // TODO(backend): derive from real user/presence data
  String get _otherName => switch (widget.conversationId) {
        'rose' => 'Grandma Rose',
        'mike' => 'Dad Mike',
        'fam'  => 'The Whole Family',
        _      => 'Family Member',
      };

  bool get _isOnline =>
      widget.conversationId == 'rose' || widget.conversationId == 'mike';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
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

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    // TODO(backend): pass message to notifier, including _replyingTo data
    ref
        .read(chatThreadNotifierProvider(widget.conversationId).notifier)
        .sendMessage(text);
    _inputCtrl.clear();
    _cancelReply();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _sendAudioMessage(int duration) {
    if (duration == 0) return;
    ref
        .read(chatThreadNotifierProvider(widget.conversationId).notifier)
        .sendAudioMessage(duration);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    final threadState =
        ref.watch(chatThreadNotifierProvider(widget.conversationId));
    final lumioColors = context.lumioColors;
    final theme       = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(lumioColors, theme),
      body: Column(
        children: [
          Expanded(
            child: threadState.messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: AppTextStyles.body(color: lumioColors.fg2),
                    ),
                  )
                : _buildMessageList(threadState.messages, lumioColors),
          ),
          if (_replyingTo != null) _buildReplyPreviewBar(lumioColors, theme),
          _ChatInputBar(
            controller: _inputCtrl,
            focusNode: _inputFocus,
            onSend: _sendMessage,
            onRecordAudio: _sendAudioMessage,
            onAttach: () => _showAttachmentSheet(context),
            onEmoji:  () {}, // TODO(backend): open emoji picker
            lumioColors: lumioColors,
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreviewBar(LumioColors c, ThemeData t) {
    final isDark = t.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF222B42) : const Color(0xFFF8FAFE);
    final border = isDark ? const Color(0xFF37425E) : const Color(0xFFE3E7F0);
    
    final replySender = _replyingTo!.senderId == 'current_user' ? 'You' : _otherName;
    final replyText = _replyingTo!.content ?? 'Attachment';

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
              color: _T.primary,
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
                  style: AppTextStyles.bodySemibold(color: _T.primary).copyWith(fontSize: 13),
                ),
                Text(
                  replyText,
                  style: AppTextStyles.body(color: c.fg2).copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: c.fg2),
            onPressed: _cancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(LumioColors colors, ThemeData theme) {
    return AppBar(
      backgroundColor: theme.scaffoldBackgroundColor,
      elevation: 0,
      leadingWidth: 48,
      leading: IconButton(
        icon: Icon(LumioIcons.back, color: colors.fg1),
        // go_router: context.pop();
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          // Avatar with online dot
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(displayName: _otherName, radius: 18),
              if (_isOnline)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _T.success,
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
                  _otherName,
                  style: AppTextStyles.bodySemibold(color: colors.fg1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isOnline ? 'online' : 'last seen 2h ago',
                  style: AppTextStyles.secondary(
                    color: _isOnline ? _T.success : colors.fg2,
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
          // go_router: context.push('/call/outgoing?kind=voice&name=...');
          onPressed: () => Navigator.of(context).pushNamed(
            '/call/outgoing',
            arguments: {'kind': 'voice', 'name': _otherName},
          ),
        ),
        IconButton(
          icon: Icon(LumioIcons.video, color: colors.fg1, size: 22),
          tooltip: 'Video Call',
          // go_router: context.push('/call/outgoing?kind=video&name=...');
          onPressed: () => Navigator.of(context).pushNamed(
            '/call/outgoing',
            arguments: {'kind': 'video', 'name': _otherName},
          ),
        ),
        const SizedBox(width: 4),
      ],
      shape: Border(bottom: BorderSide(color: colors.hairline)),
    );
  }

  // ── Message list ────────────────────────────────────────────────────────────

  Widget _buildMessageList(List<Message> messages, LumioColors colors) {
    // Build items: inject date separators between day boundaries.
    // TODO(backend): grouping logic can be driven by server-provided timestamps.
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

    // TODO(backend): show typing indicator when remote peer is composing.
    // For now it's always visible as a demo; remove the line below and
    // replace with a real presence stream.
    items.add(_ListItem.typing());

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
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
              mine:           item.msg!.senderId == 'current_user',
              colors:         colors,
              conversationId: widget.conversationId,
              onRetry: (id) => ref
                  .read(chatThreadNotifierProvider(widget.conversationId)
                      .notifier)
                  .retryMessage(id),
              onDelete: (id) => ref
                  .read(chatThreadNotifierProvider(widget.conversationId)
                      .notifier)
                  .deleteMessage(id),
              onShowContext: (msg, mine, topOffset) =>
                  _showContextMenu(context, msg, mine, topOffset),
              onSwipeReply: () => _enterReplyMode(item.msg!),
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
                .read(chatThreadNotifierProvider(widget.conversationId).notifier)
                .deleteMessage(msg.id);
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
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 10),
              _AttachListItem(
                icon: Icons.play_circle_outline_rounded,
                title: 'Video',
                subtitle: 'Send a video from your gallery.',
                color: AppColors.danger,
                c: c,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 10),
              _AttachListItem(
                icon: Icons.camera_alt_outlined,
                title: 'Camera',
                subtitle: 'Take a new photo or video.',
                color: AppColors.success,
                c: c,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 10),
              _AttachListItem(
                icon: Icons.insert_drive_file_outlined,
                title: 'Document',
                subtitle: 'Share a file, like a PDF.',
                color: const Color(0xFFF0A93B),
                c: c,
                onTap: () => Navigator.of(context).pop(),
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
    for (final c in _ctrls) c.dispose();
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
              builder: (_, __) => Transform.translate(
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
    required this.colors,
    required this.conversationId,
    required this.onRetry,
    required this.onDelete,
    required this.onShowContext,
    required this.onSwipeReply,
  });

  final Message     msg;
  final bool        mine;
  final LumioColors colors;
  final String      conversationId;
  final void Function(String id)              onRetry;
  final void Function(String id)              onDelete;
  final void Function(Message msg, bool mine, double topOffset) onShowContext;
  final VoidCallback                          onSwipeReply;

  // TODO(backend): expose isDeleted and replyTo on the Message model.
  // For now we read them defensively.
  bool get _isDeleted => (msg as dynamic).isDeleted == true;
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
                  return GestureDetector(
                    onLongPress: _isFailed ? null : () {
                      final box = bubbleContext.findRenderObject() as RenderBox?;
                      final offset = box?.localToGlobal(Offset.zero).dy ?? MediaQuery.of(bubbleContext).size.height / 2;
                      onShowContext(msg, mine, offset);
                    },
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

  @override
  Widget build(BuildContext context) {
    final Color bg = _isFailed
        ? _T.failedBubbleBg
        : mine
            ? _T.primary
            : (Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor);

    final Color fg = (mine || _isFailed) ? Colors.white : colors.fg1;

    final BorderSide side = _isFailed
        ? const BorderSide(color: _T.failedBubbleBorder)
        : mine
            ? BorderSide.none
            : BorderSide(color: colors.hairline);

    final radius = _bubbleRadius(mine);

    return Container(
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: radius,
        border:       Border.fromBorderSide(side),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      // Extra top padding only when there's a reply preview block
      padding: replyTo != null
          ? const EdgeInsets.fromLTRB(6, 6, 6, 10)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          // ── Message text or Audio ─────────────────────────────────────
          Padding(
            padding: replyTo != null
                ? const EdgeInsets.symmetric(horizontal: 8)
                : EdgeInsets.zero,
            child: _isAudio 
                ? _AudioMessageContent(
                    durationSeconds: msg.media?.durationSeconds ?? 0,
                    fgColor: fg,
                  )
                : Text(
                    msg.content ?? '',
                    style: AppTextStyles.body(color: fg),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AudioMessageContent extends StatefulWidget {
  final int durationSeconds;
  final Color fgColor;

  const _AudioMessageContent({
    required this.durationSeconds,
    required this.fgColor,
  });

  @override
  State<_AudioMessageContent> createState() => _AudioMessageContentState();
}

class _AudioMessageContentState extends State<_AudioMessageContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    // Default duration to 1s if 0 to prevent AnimationController issues
    final duration = widget.durationSeconds > 0 ? widget.durationSeconds : 1;
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: duration),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _isPlaying = false;
            _ctrl.reset();
          });
        }
      });
  }

  @override
  void didUpdateWidget(covariant _AudioMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.durationSeconds != widget.durationSeconds) {
      final duration = widget.durationSeconds > 0 ? widget.durationSeconds : 1;
      _ctrl.duration = Duration(seconds: duration);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _ctrl.forward();
      } else {
        _ctrl.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fgColor;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: Icon(
            _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
            color: fg,
            size: 32,
          ),
        ),
        const SizedBox(width: 8),
        // Playback progress bar
        SizedBox(
          width: 80,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              return LinearProgressIndicator(
                value: _ctrl.value,
                backgroundColor: fg.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(fg),
                borderRadius: BorderRadius.circular(2),
                minHeight: 4,
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            // Show current elapsed time during playback, else total time
            final currentSecs = _isPlaying 
                ? (widget.durationSeconds * _ctrl.value).floor() 
                : widget.durationSeconds;
            final time = '${currentSecs ~/ 60}:${(currentSecs % 60).toString().padLeft(2, '0')}';
            return SizedBox(
              width: 32,
              child: Text(
                time,
                style: AppTextStyles.bodySemibold(color: fg).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: 13,
                ),
              ),
            );
          },
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
            color: mine ? _T.replyPreviewBorder : _T.primary,
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
              color: mine ? Colors.white.withOpacity(0.9) : _T.primary,
            ).copyWith(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption(
              color: mine ? Colors.white.withOpacity(0.8) : colors.fg2,
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
            color: _isFailed ? _T.danger : colors.fg2,
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
              style: AppTextStyles.caption(color: _T.danger).copyWith(
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
            color:       defaultColor.withOpacity(0.55),
          ),
        ),
      // Sent — single tick
      MessageStatus.sent => _SingleTick(color: defaultColor.withOpacity(0.55)),
      // Delivered — double tick, dimmed
      MessageStatus.delivered => _DoubleTick(color: defaultColor.withOpacity(0.55)),
      // Read — double tick, accent blue
      MessageStatus.read => const _DoubleTick(color: _T.readTick),
      // Failed — warning triangle (HTML: triangle with ! inside)
      MessageStatus.failed => const Icon(
          Icons.warning_rounded,
          size:  12,
          color: _T.danger,
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
// Layout (from the HTML spec):
//
//   ┌─────────────────────────────────────┐  ┌───────┐
//   │  [TextField……………………………] [😊] [📎] │  │ 🎤/➤ │
//   └─────────────────────────────────────┘  └───────┘
//          ← pill (flex 1) →                  ← 48 px ──┘
//
// The emoji and attach buttons sit INSIDE the pill on the right.
// The mic/send button is a standalone 48-px circle OUTSIDE the pill.
// When the text field has content the send icon fades in; mic fades out.

class _ChatInputBar extends StatefulWidget {
  const _ChatInputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onRecordAudio,
    required this.onAttach,
    required this.onEmoji,
    required this.lumioColors,
    required this.theme,
  });

  final TextEditingController controller;
  final FocusNode    focusNode;
  final VoidCallback onSend;
  final void Function(int) onRecordAudio;
  final VoidCallback onAttach;
  final VoidCallback onEmoji;
  final LumioColors  lumioColors;
  final ThemeData    theme;

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
  }

  void _onTextChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has == _hasText) return;
    setState(() => _hasText = has);
    has ? _iconCtrl.forward() : _iconCtrl.reverse();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _timer?.cancel();
    _iconCtrl.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _trashCtrl.dispose();
    super.dispose();
  }

  void _startRecording() {
    HapticFeedback.lightImpact();
    setState(() {
      _isRecording = true;
      _isCancelling = false;
      _dragOffset = 0.0;
      _recordSeconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _recordSeconds++);
    });
  }

  void _updateRecording(LongPressMoveUpdateDetails details) {
    setState(() {
      _dragOffset = details.offsetFromOrigin.dx;
      if (_dragOffset > 0) _dragOffset = 0; // Don't drag right
      _isCancelling = _dragOffset < -100;
    });
  }

  void _endRecording() {
    _timer?.cancel();
    if (!_isCancelling && _isRecording) {
      widget.onRecordAudio(_recordSeconds);
    }
    setState(() {
      _isRecording = false;
      _isCancelling = false;
      _dragOffset = 0.0;
      _recordSeconds = 0;
    });
  }

  // ── Constants (documented in class-level comment above) ────────────────────
  static const double _kPillVPad   =  6.0;
  static const double _kPillHPad   = 14.0;
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
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.04))),
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

            // ── In-pill icon buttons ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Emoji
                  _PillIconButton(
                    icon:    LumioIcons.smile,
                    color:   c.fg2,
                    size:    _kIconBtn,
                    iconSz:  _kIconSz,
                    onTap:   widget.onEmoji,
                  ),
                  const SizedBox(width: 2),
                  // Attach
                  Transform.rotate(
                    angle: math.pi / 4,
                    child: _PillIconButton(
                      icon:    Icons.attach_file_rounded,
                      color:   c.fg2,
                      size:    _kIconBtn,
                      iconSz:  _kIconSz,
                      onTap:   widget.onAttach,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleMicButton(LumioColors c) {
    return GestureDetector(
      key: _micKey,
      onTap: _hasText ? widget.onSend : null,
      onLongPressStart: _hasText ? null : (_) => _startRecording(),
      onLongPressMoveUpdate: _hasText ? null : _updateRecording,
      onLongPressEnd: _hasText ? null : (_) => _endRecording(),
      onLongPressCancel: _hasText ? null : _endRecording,
      child: Material(
        color:           _T.primary,
        shape:           const CircleBorder(),
        clipBehavior:    Clip.antiAlias,
        shadowColor:     _T.primary.withOpacity(0.32),
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
    
    return Container(
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
                  BoxShadow(color: isDark ? Colors.white.withOpacity(0.04) : const Color(0x051A2235), offset: const Offset(0, 1)),
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
                    color: _isCancelling ? AppColors.danger : _T.primary,
                    border: Border.all(color: t.scaffoldBackgroundColor, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: _isCancelling ? AppColors.danger.withOpacity(0.22) : _T.primary.withOpacity(0.22),
                        spreadRadius: 6,
                      ),
                      BoxShadow(
                        color: _isCancelling ? AppColors.danger.withOpacity(0.42) : _T.primary.withOpacity(0.38),
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
                  color: AppColors.danger.withOpacity(0.22),
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

// ─── Reaction bar ─────────────────────────────────────────────────────────────

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({required this.emoji, required this.onTap});
  final String       emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 44, height: 44,
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
      ),
    );
  }
}

class _ReactionAddButton extends StatelessWidget {
  const _ReactionAddButton({required this.colors, required this.onTap});
  final LumioColors  colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color:  colors.surfaceLo,
          shape:  BoxShape.circle,
          border: Border.all(color: colors.hairline),
        ),
        child: Icon(Icons.add, size: 20, color: colors.fg2),
      ),
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
                color: color.withOpacity(0.133),
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
  final double topOffset;

  const _ContextMenuOverlay({
    required this.msg,
    required this.mine,
    required this.colors,
    required this.theme,
    required this.onDelete,
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(emoji, style: const TextStyle(fontSize: 18)),
                      ),
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? const Color(0xFF1F273C) : const Color(0xFFF8FAFE),
                        border: Border.all(color: border),
                      ),
                      child: Icon(Icons.add, color: isDark ? const Color(0xFF9AA3B8) : const Color(0xFF6B7488), size: 20),
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
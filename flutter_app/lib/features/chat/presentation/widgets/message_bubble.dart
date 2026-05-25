import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/message.dart';
import 'media_message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isSent;
  final void Function(Message)? onReply;
  final void Function(String)? onDelete;
  final void Function(String)? onRetry;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSent,
    this.onReply,
    this.onDelete,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) return _DeletedBubble(isSent: isSent);

    return GestureDetector(
      onLongPress: () => _showMenu(context),
      child: Align(
        alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
        child: _BubbleContainer(
          isSent: isSent,
          failed: message.status == MessageStatus.failed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.replyTo != null) _ReplyPreviewBlock(message.replyTo!),
              _buildBody(),
              const SizedBox(height: 3),
              _MetaRow(message: message, isSent: isSent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (message.type == MessageType.text) {
      return Text(
        message.content ?? '',
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: isSent ? Colors.white : null,
        ),
      );
    }
    return MediaMessage(message: message, isSent: isSent);
  }

  void _showMenu(BuildContext context) {
    final actions = <_MenuAction>[
      if (onReply != null) _MenuAction('Reply', Icons.reply_rounded),
      if (message.type == MessageType.text && message.content != null)
        _MenuAction('Copy', Icons.copy_rounded),
      if (isSent && onDelete != null)
        _MenuAction('Delete', Icons.delete_outline_rounded, danger: true),
    ];
    if (actions.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final a in actions)
              ListTile(
                leading: Icon(
                  a.icon,
                  color: a.danger ? AppColors.danger : null,
                ),
                title: Text(
                  a.label,
                  style: TextStyle(
                      color: a.danger ? AppColors.danger : null),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (a.label == 'Reply') onReply?.call(message);
                  if (a.label == 'Copy') {
                    Clipboard.setData(
                        ClipboardData(text: message.content!));
                  }
                  if (a.label == 'Delete') onDelete?.call(message.id);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _BubbleContainer extends StatelessWidget {
  final bool isSent;
  final bool failed;
  final Widget child;
  const _BubbleContainer(
      {required this.isSent, required this.failed, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    if (failed) {
      bg = AppColors.danger.withValues(alpha: 0.15);
    } else if (isSent) {
      bg = AppColors.primary;
    } else {
      bg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    }

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isSent ? 20 : 5),
      bottomRight: Radius.circular(isSent ? 5 : 20),
    );

    final border = failed
        ? Border.all(color: AppColors.danger.withValues(alpha: 0.5))
        : null;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );
  }
}

class _MetaRow extends StatelessWidget {
  final Message message;
  final bool isSent;
  const _MetaRow({required this.message, required this.isSent});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.jm().format(message.createdAt.toLocal());
    final metaColor = isSent
        ? Colors.white.withValues(alpha: 0.7)
        : (Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkFg3
            : AppColors.lightFg2);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(time,
            style: TextStyle(fontSize: 11, color: metaColor)),
        if (isSent) ...[
          const SizedBox(width: 4),
          _StatusTick(status: message.status),
        ],
      ],
    );
  }
}

class _StatusTick extends StatelessWidget {
  final MessageStatus status;
  const _StatusTick({required this.status});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      MessageStatus.sending => Icon(Icons.access_time_rounded,
          size: 13, color: Colors.white.withValues(alpha: 0.6)),
      MessageStatus.sent => Icon(Icons.done_rounded,
          size: 14, color: Colors.white.withValues(alpha: 0.8)),
      MessageStatus.delivered => Icon(Icons.done_all_rounded,
          size: 14, color: Colors.white.withValues(alpha: 0.8)),
      MessageStatus.read =>
        const Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF7CC1FF)),
      MessageStatus.failed => const Icon(Icons.error_outline_rounded,
          size: 14, color: AppColors.danger),
    };
  }
}

class _ReplyPreviewBlock extends StatelessWidget {
  final ReplyPreview reply;
  const _ReplyPreviewBlock(this.reply);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Colors.white, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            reply.senderName,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
          Text(
            reply.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

class _DeletedBubble extends StatelessWidget {
  final bool isSent;
  const _DeletedBubble({required this.isSent});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceLo
              : AppColors.lightSurfaceLo,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded,
                size: 14,
                color: isDark ? AppColors.darkFg3 : AppColors.lightFg2),
            const SizedBox(width: 6),
            Text(
              'This message was deleted',
              style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color:
                      isDark ? AppColors.darkFg3 : AppColors.lightFg2),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuAction {
  final String label;
  final IconData icon;
  final bool danger;
  const _MenuAction(this.label, this.icon, {this.danger = false});
}

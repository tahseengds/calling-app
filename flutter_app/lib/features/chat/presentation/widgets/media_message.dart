import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/message.dart';
import 'voice_note_player.dart';

class MediaMessage extends StatelessWidget {
  final Message message;
  final bool isSent;

  const MediaMessage({
    super.key,
    required this.message,
    required this.isSent,
  });

  @override
  Widget build(BuildContext context) {
    return switch (message.type) {
      MessageType.image => _ImageMessage(message: message),
      MessageType.video => _VideoMessage(message: message),
      MessageType.audio => VoiceNotePlayer(
          url: message.media!.url,
          durationSeconds: message.media!.durationSeconds,
          isSent: isSent,
        ),
      MessageType.file => _FileMessage(message: message, isSent: isSent),
      MessageType.text => const SizedBox.shrink(),
    };
  }
}

// ── Image ─────────────────────────────────────────────────────────────────────

class _ImageMessage extends StatelessWidget {
  final Message message;
  const _ImageMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final url = message.media!.url;
    final thumb = message.media!.thumbnailUrl ?? url;
    return GestureDetector(
      onTap: () => context.push(
        '/media?kind=image'
        '&url=${Uri.encodeComponent(url)}'
        '&sender=${Uri.encodeComponent(message.senderId)}'
        '&when=${Uri.encodeComponent(message.createdAt.toIso8601String())}',
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: thumb,
          width: 220,
          height: 180,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 220,
            height: 180,
            color: Colors.black12,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            width: 220,
            height: 180,
            color: Colors.black12,
            child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
          ),
        ),
      ),
    );
  }
}

// ── Video ─────────────────────────────────────────────────────────────────────

class _VideoMessage extends StatelessWidget {
  final Message message;
  const _VideoMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final thumb = message.media!.thumbnailUrl;
    final url = message.media!.url;
    return GestureDetector(
      onTap: () => context.push(
        '/media?kind=video'
        '&url=${Uri.encodeComponent(url)}'
        '&sender=${Uri.encodeComponent(message.senderId)}'
        '&when=${Uri.encodeComponent(message.createdAt.toIso8601String())}',
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumb != null)
              CachedNetworkImage(
                imageUrl: thumb,
                width: 220,
                height: 160,
                fit: BoxFit.cover,
              )
            else
              Container(
                width: 220,
                height: 160,
                color: Colors.black26,
              ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}

// ── File ──────────────────────────────────────────────────────────────────────

class _FileMessage extends StatelessWidget {
  final Message message;
  final bool isSent;
  const _FileMessage({required this.message, required this.isSent});

  @override
  Widget build(BuildContext context) {
    final sizeKb = message.media?.sizeBytes != null
        ? '${(message.media!.sizeBytes! / 1024).round()} KB'
        : null;
    final fg = isSent ? Colors.white : AppColors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_rounded, color: fg, size: 28),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.media?.mimeType?.split('/').last.toUpperCase() ?? 'FILE',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: fg),
              ),
              if (sizeKb != null)
                Text(sizeKb,
                    style: TextStyle(
                        fontSize: 11, color: fg.withValues(alpha: 0.7))),
            ],
          ),
        ),
      ],
    );
  }
}

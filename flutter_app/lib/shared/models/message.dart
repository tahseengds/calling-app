enum MessageType { text, image, video, audio, file }

enum MessageStatus { sending, sent, delivered, read, failed }

class ReplyPreview {
  final String senderName;
  final String text;

  const ReplyPreview({required this.senderName, required this.text});

  factory ReplyPreview.fromJson(Map<String, dynamic> json) => ReplyPreview(
        senderName: json['sender_name'] as String,
        text: json['text'] as String,
      );

  Map<String, dynamic> toJson() => {
        'sender_name': senderName,
        'text': text,
      };
}

class MediaAttachment {
  final String url;
  final String? thumbnailUrl;
  final String? mimeType;
  final int? sizeBytes;
  final int? durationSeconds;
  final int? width;
  final int? height;

  const MediaAttachment({
    required this.url,
    this.thumbnailUrl,
    this.mimeType,
    this.sizeBytes,
    this.durationSeconds,
    this.width,
    this.height,
  });

  factory MediaAttachment.fromJson(Map<String, dynamic> json) =>
      MediaAttachment(
        url: json['url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        mimeType: json['mime_type'] as String?,
        sizeBytes: (json['file_size'] ?? json['size_bytes']) as int?,
        durationSeconds: json['duration_seconds'] as int?,
        width: json['width'] as int?,
        height: json['height'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
        if (mimeType != null) 'mime_type': mimeType,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String? content;
  final MediaAttachment? media;
  final MessageStatus status;
  final DateTime createdAt;
  final String? replyToId;
  final ReplyPreview? replyTo;
  final bool isDeleted;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    this.content,
    this.media,
    this.status = MessageStatus.sent,
    required this.createdAt,
    this.replyToId,
    this.replyTo,
    this.isDeleted = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        type: MessageType.values.firstWhere(
          (e) => e.name == (json['message_type'] as String? ?? json['type'] as String),
          orElse: () => MessageType.text,
        ),
        content: json['content'] as String?,
        media: json['media'] != null
            ? MediaAttachment.fromJson(
                json['media'] as Map<String, dynamic>,
              )
            : null,
        status: MessageStatus.values.firstWhere(
          (e) => e.name == (json['status'] as String? ?? 'sent'),
          orElse: () => MessageStatus.sent,
        ),
        createdAt: DateTime.parse(json['created_at'] as String),
        replyToId: json['reply_to_id'] as String?,
        replyTo: json['reply_to'] != null
            ? ReplyPreview.fromJson(json['reply_to'] as Map<String, dynamic>)
            : null,
        isDeleted: json['is_deleted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'type': type.name,
        if (content != null) 'content': content,
        if (media != null) 'media': media!.toJson(),
        'status': status.name,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (replyToId != null) 'reply_to_id': replyToId,
        if (replyTo != null) 'reply_to': replyTo!.toJson(),
        'is_deleted': isDeleted,
      };

  Message copyWith({MessageStatus? status, ReplyPreview? replyTo}) => Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        content: content,
        media: media,
        status: status ?? this.status,
        createdAt: createdAt,
        replyToId: replyToId,
        replyTo: replyTo ?? this.replyTo,
        isDeleted: isDeleted,
      );
}

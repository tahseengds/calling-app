import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/services/signaling_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/storage/local_db.dart';
import '../../../features/auth/domain/auth_notifier.dart';
import '../../../features/auth/domain/auth_state.dart';
import '../../../shared/models/message.dart';
import '../../../shared/models/user.dart';
import '../data/message_local_dao.dart';
import '../data/message_repository.dart';

const _uuid = Uuid();

// ── Chat state ────────────────────────────────────────────────────────────────

class ChatState {
  final List<Message> messages;
  final User? otherUser;
  final bool isLoadingOlder;
  final bool otherUserTyping;
  final bool hasOlderMessages;
  final String? oldestCursor;

  /// Live upload progress for in-flight media sends, keyed by the optimistic
  /// message's client id → fraction in 0..1. Absent once the send completes,
  /// fails, or is cancelled.
  final Map<String, double> uploadProgress;

  const ChatState({
    this.messages = const [],
    this.otherUser,
    this.isLoadingOlder = false,
    this.otherUserTyping = false,
    this.hasOlderMessages = true,
    this.oldestCursor,
    this.uploadProgress = const {},
  });

  ChatState copyWith({
    List<Message>? messages,
    User? otherUser,
    bool? isLoadingOlder,
    bool? otherUserTyping,
    bool? hasOlderMessages,
    String? oldestCursor,
    Map<String, double>? uploadProgress,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        otherUser: otherUser ?? this.otherUser,
        isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
        otherUserTyping: otherUserTyping ?? this.otherUserTyping,
        hasOlderMessages: hasOlderMessages ?? this.hasOlderMessages,
        oldestCursor: oldestCursor ?? this.oldestCursor,
        uploadProgress: uploadProgress ?? this.uploadProgress,
      );
}

// ── ChatNotifier ──────────────────────────────────────────────────────────────

class ChatNotifier extends Notifier<ChatState> {
  ChatNotifier(this._conversationId);
  final String _conversationId;

  StreamSubscription<List<Message>>? _dbSub;
  StreamSubscription<MessageNewEvent>? _msgNewSub;
  StreamSubscription<MessageAckEvent>? _msgAckSub;
  StreamSubscription<MessageDeletedEvent>? _msgDelSub;
  StreamSubscription<MessageReactionEvent>? _msgReactSub;
  StreamSubscription<TypingEvent>? _typingSub;
  StreamSubscription<PresenceEvent>? _presenceSub;
  Timer? _typingStopTimer;
  // Watchdog that clears the peer's "typing…" indicator if their typing:stop
  // event never arrives (app backgrounded/killed mid-type). Without it the
  // three dots can spin forever.
  Timer? _typingClearTimer;
  bool _isTyping = false;

  /// CancelTokens for in-flight media uploads, keyed by optimistic client id —
  /// lets [cancelUpload] abort the HTTP send.
  final Map<String, CancelToken> _uploadTokens = {};

  void _setUploadProgress(String clientId, double fraction) {
    final next = Map<String, double>.from(state.uploadProgress)
      ..[clientId] = fraction.clamp(0.0, 1.0);
    state = state.copyWith(uploadProgress: next);
  }

  void _clearUploadProgress(String clientId) {
    if (!state.uploadProgress.containsKey(clientId)) return;
    final next = Map<String, double>.from(state.uploadProgress)
      ..remove(clientId);
    state = state.copyWith(uploadProgress: next);
  }

  /// Abort an in-flight media upload and remove its optimistic message + the
  /// pending-upload row, so a cancelled send vanishes cleanly.
  Future<void> cancelUpload(String clientId) async {
    _uploadTokens.remove(clientId)?.cancel('cancelled by user');
    _clearUploadProgress(clientId);
    await ref.read(messageLocalDaoProvider).deleteMessage(clientId);
    await ref.read(appDatabaseProvider).pendingMediaUploadsDao.markDone(clientId);
  }

  @override
  ChatState build() {
    ref.onDispose(() {
      _dbSub?.cancel();
      _msgNewSub?.cancel();
      _msgAckSub?.cancel();
      _msgDelSub?.cancel();
      _msgReactSub?.cancel();
      _typingSub?.cancel();
      _presenceSub?.cancel();
      _typingStopTimer?.cancel();
      _typingClearTimer?.cancel();
      for (final t in _uploadTokens.values) {
        t.cancel('chat closed');
      }
      _uploadTokens.clear();
    });

    _init();
    return const ChatState();
  }

  Future<void> _init() async {
    final dao = ref.read(messageLocalDaoProvider);
    final db = ref.read(appDatabaseProvider);

    // Load cached messages immediately.
    final cached = await dao.getMessages(_conversationId);
    state = state.copyWith(messages: cached);

    // Load other-user profile.
    final convRows = await (db.select(db.conversationsTable)
          ..where((c) => c.id.equals(_conversationId)))
        .get();
    if (convRows.isNotEmpty) {
      final userRow = await db.usersDao.getById(convRows.first.otherUserId);
      if (userRow != null) {
        state = state.copyWith(
          otherUser: User(
            id: userRow.id,
            name: userRow.name,
            avatarUrl: userRow.avatarUrl,
            lastSeen: userRow.lastSeen,
            presence: PresenceStatus.values.firstWhere(
              (e) => e.name == userRow.presence,
              orElse: () => PresenceStatus.offline,
            ),
          ),
        );
        // Seed live presence/last-seen for the header — REST never carries it,
        // so without this the chat header is stuck on "offline" / a stale time.
        ref
            .read(signalingServiceProvider)
            .requestPresence([userRow.id]);
      }
    }

    // Watch Drift for any changes (including optimistic writes).
    _dbSub = dao.watchMessages(_conversationId).listen((msgs) {
      state = state.copyWith(messages: msgs);
    });

    // Mark unread as read.
    final unread = cached
        .where((m) => m.status != MessageStatus.read &&
            m.senderId != _currentUserId)
        .map((m) => m.id)
        .toList();
    if (unread.isNotEmpty) {
      ref.read(messageRepositoryProvider).markRead(unread).ignore();
      dao.clearUnread(_conversationId);
    }

    // Fetch missed messages from server.
    await ref.read(syncServiceProvider).fetchMissedMessages(_conversationId);

    // Real-time events.
    _subscribeToSignaling();

    // Wire up reconnect → sync. Also re-request presence so the header's
    // online/last-seen self-heals if the socket wasn't connected when _init
    // first asked (otherwise the chat is stuck on the stale cached value).
    ref.read(signalingServiceProvider).onReconnect = () {
      ref.read(syncServiceProvider).syncAll(_conversationId);
      final otherId = state.otherUser?.id;
      if (otherId != null) {
        ref.read(signalingServiceProvider).requestPresence([otherId]);
      }
    };
  }

  String get _currentUserId {
    final auth = ref.read(authNotifierProvider);
    if (auth is AuthAuthenticated) return auth.me.id;
    return '';
  }

  void _subscribeToSignaling() {
    final signaling = ref.read(signalingServiceProvider);

    _msgNewSub = signaling.onMessageNew.listen((event) {
      final msg = Message.fromJson(event.json);
      if (msg.conversationId != _conversationId) return;
      // Dedup on id — upsert into Drift, which fires the watch.
      ref.read(messageLocalDaoProvider).upsertMessage(msg);
      // Send read receipt.
      if (msg.senderId != _currentUserId) {
        ref.read(messageRepositoryProvider).markRead([msg.id]).ignore();
      }
    });

    _msgAckSub = signaling.onMessageAck.listen((event) {
      final status = MessageStatus.values.firstWhere(
        (e) => e.name == event.status,
        orElse: () => MessageStatus.delivered,
      );
      ref.read(messageLocalDaoProvider).updateStatus(event.messageId, status);
    });

    _msgDelSub = signaling.onMessageDeleted.listen((event) {
      if (event.conversationId != _conversationId) return;
      ref.read(messageLocalDaoProvider).markDeleted(event.messageId);
    });

    _msgReactSub = signaling.onMessageReaction.listen((event) {
      if (event.conversationId != _conversationId) return;
      final summaries = event.reactionsJson
          .map((j) => ReactionSummary.fromJson(j))
          .toList();
      ref
          .read(messageLocalDaoProvider)
          .updateReactions(event.messageId, summaries);
    });

    _typingSub = signaling.onTyping.listen((event) {
      if (event.conversationId != _conversationId) return;
      state = state.copyWith(otherUserTyping: event.isTyping);
      _typingClearTimer?.cancel();
      if (event.isTyping) {
        // Self-heal if the matching typing:stop is lost.
        _typingClearTimer = Timer(const Duration(seconds: 6), () {
          state = state.copyWith(otherUserTyping: false);
        });
      }
    });

    // Live presence/last-seen for the chat header.
    _presenceSub = signaling.onPresence.listen((event) {
      final other = state.otherUser;
      if (other == null || other.id != event.userId) return;
      state = state.copyWith(
        otherUser: other.copyWith(
          presence: event.status == 'online'
              ? PresenceStatus.online
              : PresenceStatus.offline,
          lastSeen: event.lastSeen,
        ),
      );
    });
  }

  // ── Reactions ─────────────────────────────────────────────────────────────

  /// Toggle a reaction by the current user on a message. If the user already
  /// has [emoji] on the message, this removes it; otherwise it adds it.
  /// Updates Drift optimistically and rolls back on a request failure.
  Future<void> toggleReaction(String messageId, String emoji) async {
    HapticFeedback.selectionClick();
    final dao = ref.read(messageLocalDaoProvider);
    final me = _currentUserId;
    if (me.isEmpty) return;

    final msg = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null || msg.isDeleted) return;

    final existing = msg.reactions
        .where((r) => r.emoji == emoji)
        .firstOrNull;
    final iAlreadyReacted = existing?.reactedByUser(me) ?? false;

    // Build optimistic next state.
    final optimistic = _withToggledReaction(
      msg.reactions,
      emoji: emoji,
      userId: me,
      add: !iAlreadyReacted,
    );
    await dao.updateReactions(messageId, optimistic);

    try {
      final updated = iAlreadyReacted
          ? await ref
              .read(messageRepositoryProvider)
              .removeReaction(messageId, emoji)
          : await ref
              .read(messageRepositoryProvider)
              .addReaction(messageId, emoji);
      // Server is the source of truth — overwrite local state with its answer.
      await dao.updateReactions(messageId, updated);
    } catch (e, st) {
      debugPrint('[chat] toggleReaction failed for $messageId / $emoji: $e\n$st');
      // Roll back to the pre-optimistic snapshot.
      await dao.updateReactions(messageId, msg.reactions);
    }
  }

  /// Pure helper — computes the post-toggle reaction list locally so we can
  /// render an immediate change before the server roundtrip.
  List<ReactionSummary> _withToggledReaction(
    List<ReactionSummary> current, {
    required String emoji,
    required String userId,
    required bool add,
  }) {
    final out = <ReactionSummary>[];
    var matched = false;
    for (final r in current) {
      if (r.emoji != emoji) {
        out.add(r);
        continue;
      }
      matched = true;
      if (add) {
        if (r.reactedByUser(userId)) {
          out.add(r); // no-op (server is idempotent)
        } else {
          out.add(ReactionSummary(
            emoji: emoji,
            count: r.count + 1,
            userIds: [...r.userIds, userId],
            firstReactedAt: r.firstReactedAt,
          ));
        }
      } else {
        final remaining =
            r.userIds.where((u) => u != userId).toList(growable: false);
        if (remaining.isNotEmpty) {
          out.add(ReactionSummary(
            emoji: emoji,
            count: remaining.length,
            userIds: remaining,
            firstReactedAt: r.firstReactedAt,
          ));
        }
        // else: drop the chip entirely
      }
    }
    if (!matched && add) {
      out.add(ReactionSummary(
        emoji: emoji,
        count: 1,
        userIds: [userId],
        firstReactedAt: DateTime.now(),
      ));
    }
    return out;
  }

  // ── Send text ─────────────────────────────────────────────────────────────

  /// Resolve the other party's user id for outbound message sends.
  ///
  /// Prefers the live `state.otherUser` (loaded during _init), and falls
  /// back to the cached conversation row in Drift so we can still send
  /// during the small race between the screen mounting and `otherUser`
  /// being hydrated from the local DB.
  ///
  /// Returns null only when neither source can produce one — at which
  /// point the send is left in `failed` state and the user can retry.
  Future<String?> _resolveRecipientId() async {
    final liveId = state.otherUser?.id;
    if (liveId != null && liveId.isNotEmpty) return liveId;

    final db = ref.read(appDatabaseProvider);
    final rows = await (db.select(db.conversationsTable)
          ..where((c) => c.id.equals(_conversationId)))
        .get();
    return rows.firstOrNull?.otherUserId;
  }

  Future<void> sendText(String content, {String? replyToId}) async {
    if (content.trim().isEmpty) return;
    _stopTyping();

    final clientId = _uuid.v4();
    final now = DateTime.now();
    final optimistic = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      type: MessageType.text,
      content: content.trim(),
      status: MessageStatus.sending,
      createdAt: now,
      replyToId: replyToId,
    );

    // Write to Drift immediately → optimistic UI.
    await ref.read(messageLocalDaoProvider).upsertMessage(optimistic);

    final recipientId = await _resolveRecipientId();
    if (recipientId == null) {
      await ref.read(messageLocalDaoProvider).updateStatus(
            clientId,
            MessageStatus.failed,
          );
      return;
    }

    try {
      final result = await ref.read(messageRepositoryProvider).sendMessage(
            clientId: clientId,
            recipientId: recipientId,
            type: MessageType.text,
            content: content.trim(),
            replyToId: replyToId,
          );
      // Server response may differ in status/timestamps.
      await ref.read(messageLocalDaoProvider).upsertMessage(result);
      await ref.read(messageLocalDaoProvider).markSynced(clientId);
    } catch (e, st) {
      // Mark as failed — user can retry via long-press. Log so we can
      // see the actual failure in `flutter logs` instead of guessing.
      _logSendFailure('sendText', clientId, 'text', e, st);
      await ref.read(messageLocalDaoProvider).updateStatus(
            clientId,
            MessageStatus.failed,
          );
    }
  }

  // ── Send media ────────────────────────────────────────────────────────────

  Future<void> sendMedia(
    File file,
    MessageType type, {
    String? replyToId,
    int? durationSeconds,
    void Function(int sent, int total)? onProgress,
  }) async {
    final clientId = _uuid.v4();
    final now = DateTime.now();

    // Track in PendingMediaUploads so it survives app restart.
    final db = ref.read(appDatabaseProvider);
    final stat = await file.stat();
    await db.pendingMediaUploadsDao.upsert(PendingMediaUploadsTableCompanion(
      localId: Value(clientId),
      filePath: Value(file.path),
      type: Value(type.name),
      conversationId: Value(_conversationId),
      totalBytes: Value(stat.size),
    ));

    final optimistic = Message(
      id: clientId,
      conversationId: _conversationId,
      senderId: _currentUserId,
      type: type,
      // local path for optimistic UI. durationSeconds is what the caller
      // recorded — without it the audio bubble defaults to "1s" until
      // the server response arrives with ffprobe-normalized duration.
      media: MediaAttachment(
        url: file.path,
        durationSeconds: durationSeconds,
      ),
      status: MessageStatus.sending,
      createdAt: now,
      replyToId: replyToId,
    );
    await ref.read(messageLocalDaoProvider).upsertMessage(optimistic);

    final recipientId = await _resolveRecipientId();
    if (recipientId == null) {
      await ref.read(messageLocalDaoProvider).updateStatus(
            clientId,
            MessageStatus.failed,
          );
      return;
    }

    final cancelToken = CancelToken();
    _uploadTokens[clientId] = cancelToken;
    _setUploadProgress(clientId, 0);

    try {
      final upload = await ref.read(messageRepositoryProvider).uploadMedia(
            file: file,
            type: MessageRepository.wireType(type),
            cancelToken: cancelToken,
            onProgress: (sent, total) {
              onProgress?.call(sent, total);
              if (total > 0) _setUploadProgress(clientId, sent / total);
              // Fire-and-forget; row was already inserted above with all
              // required columns, so a plain UPDATE is sufficient here.
              db.pendingMediaUploadsDao.updateProgress(clientId, sent);
            },
          );

      final result = await ref.read(messageRepositoryProvider).sendMessage(
            clientId: clientId,
            recipientId: recipientId,
            type: type,
            mediaId: upload.mediaId,
            replyToId: replyToId,
          );
      await ref.read(messageLocalDaoProvider).upsertMessage(result);
      await ref.read(messageLocalDaoProvider).markSynced(clientId);
      await db.pendingMediaUploadsDao.markDone(clientId);
    } catch (e, st) {
      // User-initiated cancellation already removed the message in
      // cancelUpload(); don't resurrect it as a "failed" send.
      if (e is DioException && CancelToken.isCancel(e)) {
        return;
      }
      _logSendFailure('sendMedia', clientId, type.name, e, st);
      await ref.read(messageLocalDaoProvider).updateStatus(
            clientId,
            MessageStatus.failed,
          );
    } finally {
      _uploadTokens.remove(clientId);
      _clearUploadProgress(clientId);
    }
  }

  /// Verbose log for media send failures — surface the status code AND
  /// the server's response body so 415/413/422 from /api/media/upload
  /// or /api/messages/ are diagnosable from `flutter logs` directly.
  void _logSendFailure(
    String origin,
    String clientId,
    String type,
    Object error,
    StackTrace st,
  ) {
    if (error is DioException) {
      final req = error.requestOptions;
      final resp = error.response;
      debugPrint('[chat] $origin failed for $clientId ($type): '
          '${req.method} ${req.path} → ${resp?.statusCode} '
          'body=${resp?.data} dio=${error.type} msg=${error.message}');
    } else {
      debugPrint('[chat] $origin failed for $clientId ($type): $error\n$st');
    }
  }

  // ── Retry ─────────────────────────────────────────────────────────────────

  Future<void> retryMessage(String messageId) async {
    final msgs = state.messages;
    final msg = msgs.where((m) => m.id == messageId).firstOrNull;
    if (msg == null) return;

    await ref.read(messageLocalDaoProvider).updateStatus(
          messageId,
          MessageStatus.sending,
        );

    final recipientId = await _resolveRecipientId();
    if (recipientId == null) {
      await ref.read(messageLocalDaoProvider).updateStatus(
            messageId,
            MessageStatus.failed,
          );
      return;
    }

    try {
      // For media messages we need a media_id — the backend's
      // SendMessageRequest validator rejects non-text without one (422).
      // We don't persist the server-side media_id locally, so on retry
      // re-upload the original file from pending_media_uploads. This also
      // covers the case where the *original* failure happened during the
      // upload itself — there's nothing to reuse anyway.
      String? mediaId;
      final db = ref.read(appDatabaseProvider);

      if (msg.type != MessageType.text) {
        final pendingRows = await (db.select(db.pendingMediaUploadsTable)
              ..where((u) => u.localId.equals(messageId))
              ..limit(1))
            .get();
        final pending = pendingRows.firstOrNull;
        if (pending == null) {
          debugPrint('[chat] retry: no pending_media_uploads row for '
              '$messageId — cannot re-upload media. Marking failed.');
          await ref.read(messageLocalDaoProvider).updateStatus(
                messageId,
                MessageStatus.failed,
              );
          return;
        }
        final file = File(pending.filePath);
        if (!await file.exists()) {
          debugPrint('[chat] retry: local file gone (${pending.filePath}) '
              '— cannot re-upload. Marking failed.');
          await ref.read(messageLocalDaoProvider).updateStatus(
                messageId,
                MessageStatus.failed,
              );
          return;
        }

        final upload = await ref.read(messageRepositoryProvider).uploadMedia(
              file: file,
              type: MessageRepository.wireType(msg.type),
            );
        mediaId = upload.mediaId;
      }

      final result = await ref.read(messageRepositoryProvider).sendMessage(
            clientId: messageId,
            recipientId: recipientId,
            type: msg.type,
            content: msg.content,
            mediaId: mediaId,
            replyToId: msg.replyToId,
          );
      await ref.read(messageLocalDaoProvider).upsertMessage(result);
      await ref.read(messageLocalDaoProvider).markSynced(messageId);
      if (msg.type != MessageType.text) {
        await db.pendingMediaUploadsDao.markDone(messageId);
      }
    } catch (e, st) {
      _logSendFailure('retry', messageId, msg.type.name, e, st);
      await ref.read(messageLocalDaoProvider).updateStatus(
            messageId,
            MessageStatus.failed,
          );
    }
  }

  // ── Forward ─────────────────────────────────────────────────────────────────

  /// Forwards [source] into THIS conversation. Text is re-sent verbatim; media
  /// is downloaded from its URL and re-uploaded, since we don't keep the
  /// server-side media id locally to reference directly. Call-log messages
  /// aren't forwardable. Best-effort: failures are logged, not surfaced.
  Future<void> forward(Message source) async {
    if (source.type == MessageType.text) {
      final content = source.content?.trim() ?? '';
      if (content.isNotEmpty) await sendText(content);
      return;
    }
    if (source.type == MessageType.callLog) return;

    final media = source.media;
    if (media == null || media.url.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final dest = '${dir.path}/fwd_${_uuid.v4()}${_forwardExt(source)}';
      await ref.read(dioProvider).download(media.url, dest);
      await sendMedia(
        File(dest),
        source.type,
        durationSeconds: media.durationSeconds,
      );
    } catch (e, st) {
      debugPrint('[chat] forward failed for ${source.id}: $e\n$st');
    }
  }

  /// Best-effort file extension for a forwarded media download — prefers the
  /// MIME type, then the URL's extension, then a per-type default.
  String _forwardExt(Message source) {
    final mime = source.media?.mimeType ?? '';
    if (mime.contains('png')) return '.png';
    if (mime.contains('gif')) return '.gif';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('jpeg') || mime.contains('jpg')) return '.jpg';
    if (mime.contains('mp4')) return '.mp4';
    if (mime.contains('quicktime') || mime.contains('mov')) return '.mov';
    if (mime.contains('mpeg') || mime.contains('mp3')) return '.mp3';
    if (mime.contains('aac') || mime.contains('m4a')) return '.m4a';
    if (mime.contains('wav')) return '.wav';
    if (mime.contains('pdf')) return '.pdf';

    final url = source.media?.url ?? '';
    final q = url.indexOf('?');
    final clean = q == -1 ? url : url.substring(0, q);
    final slash = clean.lastIndexOf('/');
    final dot = clean.lastIndexOf('.');
    if (dot > slash && dot < clean.length - 1 && clean.length - dot <= 6) {
      return clean.substring(dot);
    }
    return switch (source.type) {
      MessageType.image => '.jpg',
      MessageType.video => '.mp4',
      MessageType.audio => '.m4a',
      MessageType.file => '.bin',
      _ => '.bin',
    };
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    await ref.read(messageLocalDaoProvider).markDeleted(messageId);
    ref.read(messageRepositoryProvider).deleteMessage(messageId).ignore();
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  Future<void> loadOlderMessages() async {
    if (state.isLoadingOlder || !state.hasOlderMessages) return;
    state = state.copyWith(isLoadingOlder: true);

    try {
      final page = await ref.read(messageRepositoryProvider).fetchMessages(
            _conversationId,
            cursor: state.oldestCursor,
          );
      if (page.messages.isEmpty) {
        state = state.copyWith(isLoadingOlder: false, hasOlderMessages: false);
        return;
      }
      for (final msg in page.messages) {
        await ref.read(messageLocalDaoProvider).upsertMessage(msg);
      }
      // Forward the server's opaque cursor verbatim — it encodes
      // (created_at, id) and the backend will refuse anything else.
      state = state.copyWith(
        isLoadingOlder: false,
        oldestCursor: page.nextCursor,
        hasOlderMessages: page.nextCursor != null,
      );
    } catch (e, st) {
      debugPrint('[chat] loadOlderMessages failed: $e\n$st');
      state = state.copyWith(isLoadingOlder: false);
    }
  }

  // ── Typing ────────────────────────────────────────────────────────────────

  void onUserTyping() {
    final toUserId = state.otherUser?.id;
    if (toUserId == null) return;
    if (!_isTyping) {
      _isTyping = true;
      ref.read(signalingServiceProvider).emitTyping(
            isTyping: true,
            conversationId: _conversationId,
            toUserId: toUserId,
          );
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    if (!_isTyping) return;
    _isTyping = false;
    _typingStopTimer?.cancel();
    final toUserId = state.otherUser?.id;
    if (toUserId == null) return;
    ref.read(signalingServiceProvider).emitTyping(
          isTyping: false,
          conversationId: _conversationId,
          toUserId: toUserId,
        );
  }
}

final chatProvider =
    NotifierProvider.family<ChatNotifier, ChatState, String>(ChatNotifier.new);

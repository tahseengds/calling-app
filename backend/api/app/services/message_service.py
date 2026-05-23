"""
Message service — send, fetch, mark delivered/read, soft delete.

Key design decisions:
  - client_id is the message PK. INSERT … ON CONFLICT DO NOTHING makes sends
    idempotent: re-sending with the same client_id returns the original message.
  - Soft-deleted messages are returned as tombstones (is_deleted=True, no content).
  - Every state change publishes to Redis for the Node.js signaling server (prompt 08).
  - New messages also enqueue an FCM job on the fcm_queue stream (prompt 07).
"""
from __future__ import annotations

import uuid as _uuid
from datetime import datetime, timezone
from uuid import UUID

import redis.asyncio as aioredis
from sqlalchemy import and_, func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.contact import Contact
from app.models.conversation import Conversation
from app.models.media import MediaFile
from app.models.message import Message, MessageReceipt
from app.models.user import User
from app.schemas.message import (
    MessagePage,
    MessageResponse,
    ReceiptRequest,
    SendMessageRequest,
    decode_cursor,
    encode_cursor,
)
from app.services.conversation_service import (
    _msg_to_response,
    get_or_create_conversation,
)
from app.services.media_service import media_file_to_response
from app.services.realtime import (
    enqueue_fcm,
    msg_delivery_channel,
    publish,
    receipt_channel,
)
from app.utils.exceptions import ForbiddenError, NotFoundError, ValidationFailedError


# ── Internal helpers ──────────────────────────────────────────────────────────

async def _assert_can_message(
    db: AsyncSession, sender: User, recipient_id: UUID
) -> None:
    """
    Raise if the sender cannot message the recipient:
      - recipient must exist and be active
      - they must be contacts
      - neither may have blocked the other
    """
    # Resolve recipient
    r = await db.execute(
        select(User).where(User.id == recipient_id, User.is_active.is_(True))
    )
    recipient = r.scalar_one_or_none()
    if not recipient:
        raise NotFoundError("Recipient not found")

    if recipient.id == sender.id:
        raise ValidationFailedError("Cannot message yourself")

    # Sender → recipient contact row (sender must have recipient in their list)
    fwd = await db.execute(
        select(Contact).where(
            Contact.user_id == sender.id,
            Contact.contact_user_id == recipient.id,
        )
    )
    fwd_contact = fwd.scalar_one_or_none()
    if not fwd_contact:
        raise ForbiddenError("Recipient is not in your contacts")
    if fwd_contact.is_blocked:
        raise ForbiddenError("You have blocked this contact")

    # Recipient → sender: check if recipient blocked sender
    rev = await db.execute(
        select(Contact).where(
            Contact.user_id == recipient.id,
            Contact.contact_user_id == sender.id,
        )
    )
    rev_contact = rev.scalar_one_or_none()
    if rev_contact and rev_contact.is_blocked:
        raise ForbiddenError("You cannot message this user")


# ── Public API ────────────────────────────────────────────────────────────────

async def send_message(
    db: AsyncSession,
    redis: aioredis.Redis,
    sender: User,
    req: SendMessageRequest,
) -> MessageResponse:
    """
    Send a message. Idempotent on client_id — re-posting returns the original.
    Publishes new-message event to Redis and enqueues an FCM job.
    """
    await _assert_can_message(db, sender, req.recipient_id)

    # Validate media ownership for non-text types
    if req.media_id is not None:
        media_r = await db.execute(
            select(MediaFile).where(
                MediaFile.id == req.media_id,
                MediaFile.uploader_id == sender.id,
            )
        )
        if not media_r.scalar_one_or_none():
            raise NotFoundError("Media file not found or not owned by sender")

    conv = await get_or_create_conversation(db, sender.id, req.recipient_id)

    # ── Idempotent INSERT ────────────────────────────────────────────────────
    insert_stmt = (
        pg_insert(Message)
        .values(
            id=req.client_id,
            conversation_id=conv.id,
            sender_id=sender.id,
            message_type=req.message_type,
            content=req.content,
            media_id=req.media_id,
            reply_to_id=req.reply_to_id,
            status="sent",
        )
        .on_conflict_do_nothing()
        .returning(Message.id)
    )
    insert_result = await db.execute(insert_stmt)
    inserted_id = insert_result.scalar_one_or_none()
    is_new = inserted_id is not None

    # Load the message (new or existing)
    msg_r = await db.execute(select(Message).where(Message.id == req.client_id))
    msg = msg_r.scalar_one()

    if not is_new:
        # Idempotent resend — return existing message without side effects
        media_resp = None
        if msg.media_id:
            mf_r = await db.execute(select(MediaFile).where(MediaFile.id == msg.media_id))
            mf = mf_r.scalar_one_or_none()
            if mf:
                media_resp = media_file_to_response(mf)
        return _msg_to_response(msg, media_resp)

    # ── Update conversation ──────────────────────────────────────────────────
    await db.execute(
        update(Conversation)
        .where(Conversation.id == conv.id)
        .values(
            last_message_id=msg.id,
            last_activity=msg.created_at,
        )
    )

    # ── Create delivery receipt for recipient ────────────────────────────────
    receipt_stmt = (
        pg_insert(MessageReceipt)
        .values(message_id=msg.id, user_id=req.recipient_id)
        .on_conflict_do_nothing()
    )
    await db.execute(receipt_stmt)

    await db.flush()

    # Load media for the response if this is a media message
    media_resp = None
    if msg.media_id:
        mf_r = await db.execute(select(MediaFile).where(MediaFile.id == msg.media_id))
        mf = mf_r.scalar_one_or_none()
        if mf:
            media_resp = media_file_to_response(mf)

    response = _msg_to_response(msg, media_resp)

    # ── Publish to Redis (for Node.js signaling server — prompt 08) ──────────
    payload = response.model_dump(mode="json")
    payload["event"] = "new_message"
    await publish(redis, msg_delivery_channel(str(req.recipient_id)), payload)

    # ── Enqueue FCM job (for prompt 07 worker) ───────────────────────────────
    await enqueue_fcm(
        redis,
        {
            "type": "new_message",
            "recipient_id": str(req.recipient_id),
            "sender_id": str(sender.id),
            "message_id": str(msg.id),
            "conversation_id": str(conv.id),
            "message_type": req.message_type,
        },
    )

    return response


async def fetch_messages(
    db: AsyncSession,
    user: User,
    conversation_id: UUID,
    cursor: str | None = None,
    limit: int = 30,
) -> MessagePage:
    """
    Return up to *limit* messages from a conversation, newest first.
    Soft-deleted messages are included as tombstones (is_deleted=True).
    Pass *cursor* from a previous response to fetch older messages.
    """
    # Verify user is a participant
    conv_r = await db.execute(
        select(Conversation).where(Conversation.id == conversation_id)
    )
    conv = conv_r.scalar_one_or_none()
    if not conv or user.id not in (conv.participant_a, conv.participant_b):
        raise ForbiddenError("Conversation not found or access denied")

    query = (
        select(Message)
        .where(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.desc(), Message.id.desc())
    )

    if cursor:
        cursor_at, cursor_id = decode_cursor(cursor)
        query = query.where(
            (Message.created_at < cursor_at)
            | (
                (Message.created_at == cursor_at)
                & (Message.id < cursor_id)
            )
        )

    # Fetch limit+1 to detect whether a next page exists
    query = query.limit(limit + 1)
    result = await db.execute(query)
    rows = result.scalars().all()

    has_more = len(rows) > limit
    page_rows = rows[:limit]

    next_cursor: str | None = None
    if has_more and page_rows:
        last = page_rows[-1]
        next_cursor = encode_cursor(last.created_at, last.id)

    # Batch-load all media files for messages that have a media_id
    media_ids = [m.media_id for m in page_rows if m.media_id and m.deleted_at is None]
    media_map: dict = {}
    if media_ids:
        from sqlalchemy import in_
        mf_result = await db.execute(
            select(MediaFile).where(MediaFile.id.in_(media_ids))
        )
        for mf in mf_result.scalars().all():
            media_map[mf.id] = media_file_to_response(mf)

    return MessagePage(
        messages=[
            _msg_to_response(m, media_map.get(m.media_id) if m.media_id else None)
            for m in page_rows
        ],
        next_cursor=next_cursor,
    )


async def mark_delivered(
    db: AsyncSession,
    redis: aioredis.Redis,
    user: User,
    message_ids: list[UUID],
) -> None:
    """
    Set delivered_at=now() on receipts for *user* (only those still null).
    Publishes a receipt event to each original sender's channel.
    """
    now = datetime.now(timezone.utc)

    # Load matching receipts and their message sender_ids
    result = await db.execute(
        select(MessageReceipt, Message.sender_id)
        .join(Message, Message.id == MessageReceipt.message_id)
        .where(
            MessageReceipt.message_id.in_(message_ids),
            MessageReceipt.user_id == user.id,
            MessageReceipt.delivered_at.is_(None),
        )
    )
    rows = result.all()

    if not rows:
        return

    updated_ids: list[UUID] = []
    sender_ids: set[UUID] = set()
    for receipt, sender_id in rows:
        receipt.delivered_at = now
        updated_ids.append(receipt.message_id)
        sender_ids.add(sender_id)

    await db.flush()

    # Publish receipt events grouped by sender
    for sender_id in sender_ids:
        await publish(
            redis,
            receipt_channel(str(sender_id)),
            {
                "event": "receipt",
                "status": "delivered",
                "message_ids": [str(m) for m in updated_ids],
                "user_id": str(user.id),
            },
        )


async def mark_read(
    db: AsyncSession,
    redis: aioredis.Redis,
    user: User,
    message_ids: list[UUID],
) -> None:
    """
    Set read_at=now() (and delivered_at if still null) on receipts for *user*.
    Marks the parent message status='read' when all recipients have read it.
    Publishes a receipt event to each original sender's channel.
    """
    now = datetime.now(timezone.utc)

    # Load matching receipts and their message sender_ids
    result = await db.execute(
        select(MessageReceipt, Message.sender_id)
        .join(Message, Message.id == MessageReceipt.message_id)
        .where(
            MessageReceipt.message_id.in_(message_ids),
            MessageReceipt.user_id == user.id,
            MessageReceipt.read_at.is_(None),
        )
    )
    rows = result.all()

    if not rows:
        return

    updated_msg_ids: list[UUID] = []
    sender_ids: set[UUID] = set()
    for receipt, sender_id in rows:
        if receipt.delivered_at is None:
            receipt.delivered_at = now
        receipt.read_at = now
        updated_msg_ids.append(receipt.message_id)
        sender_ids.add(sender_id)

    await db.flush()

    # Promote message status to 'read' when all recipients have read it
    for msg_id in updated_msg_ids:
        unread_r = await db.execute(
            select(func.count())
            .select_from(MessageReceipt)
            .where(
                MessageReceipt.message_id == msg_id,
                MessageReceipt.read_at.is_(None),
            )
        )
        if (unread_r.scalar() or 0) == 0:
            await db.execute(
                update(Message)
                .where(Message.id == msg_id)
                .values(status="read", updated_at=now)
            )

    await db.flush()

    # Publish receipt events grouped by sender
    for sender_id in sender_ids:
        await publish(
            redis,
            receipt_channel(str(sender_id)),
            {
                "event": "receipt",
                "status": "read",
                "message_ids": [str(m) for m in updated_msg_ids],
                "user_id": str(user.id),
            },
        )


async def soft_delete(
    db: AsyncSession,
    redis: aioredis.Redis,
    user: User,
    message_id: UUID,
) -> MessageResponse:
    """
    Soft-delete a message. Only the sender may delete.
    Clears content and media_id, sets deleted_at. Returns the tombstone.
    Publishes a message_deleted event to the recipient's delivery channel.
    """
    msg_r = await db.execute(select(Message).where(Message.id == message_id))
    msg = msg_r.scalar_one_or_none()

    if not msg:
        raise NotFoundError("Message not found")
    if msg.sender_id != user.id:
        raise ForbiddenError("Only the sender may delete this message")
    if msg.deleted_at is not None:
        return _msg_to_response(msg)  # already deleted — idempotent

    now = datetime.now(timezone.utc)
    msg.deleted_at = now
    msg.content = None
    msg.media_id = None
    msg.updated_at = now
    await db.flush()

    response = _msg_to_response(msg)

    # Determine recipient (the other participant in the conversation)
    conv_r = await db.execute(
        select(Conversation).where(Conversation.id == msg.conversation_id)
    )
    conv = conv_r.scalar_one()
    recipient_id = (
        conv.participant_b
        if conv.participant_a == user.id
        else conv.participant_a
    )

    # Publish deletion event to recipient
    payload = response.model_dump(mode="json")
    payload["event"] = "message_deleted"
    await publish(redis, msg_delivery_channel(str(recipient_id)), payload)

    return response

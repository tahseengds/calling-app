"""
Conversation management.

Design notes:
  - participant_a is always min(uuid_a, uuid_b) so (A,B) and (B,A) map to the
    same row. UUID comparison uses lexicographic order on the string representation.
  - get_or_create_conversation handles concurrent creation with
    INSERT … ON CONFLICT DO NOTHING followed by a re-SELECT.
"""
import uuid as _uuid
from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.contact import Contact
from app.models.conversation import Conversation
from app.models.media import MediaFile
from app.models.message import Message, MessageReceipt
from app.models.user import User
from app.schemas.media import MediaResponse
from app.schemas.message import ConversationResponse, MessageResponse
from app.schemas.user import UserPublic
from app.utils.exceptions import (
    ForbiddenError,
    NotFoundError,
    ValidationFailedError,
)


# ── Internal helpers ──────────────────────────────────────────────────────────

def _msg_to_response(
    msg: Message, media: MediaResponse | None = None
) -> MessageResponse:
    """Build a MessageResponse, masking content/media for soft-deleted messages."""
    deleted = msg.deleted_at is not None
    return MessageResponse(
        id=msg.id,
        conversation_id=msg.conversation_id,
        sender_id=msg.sender_id,
        message_type=msg.message_type,
        content=None if deleted else msg.content,
        media_id=None if deleted else msg.media_id,
        media=None if deleted else media,
        reply_to_id=msg.reply_to_id,
        status=msg.status,
        is_deleted=deleted,
        created_at=msg.created_at,
        updated_at=msg.updated_at,
    )


# ── Public API ────────────────────────────────────────────────────────────────

async def get_or_create_conversation(
    db: AsyncSession, user_a_id: UUID, user_b_id: UUID
) -> Conversation:
    """
    Return the 1-to-1 conversation between two users, creating it if needed.
    UUIDs are sorted so (A,B) always maps to the same row as (B,A).
    """
    # Normalize: str comparison on UUID hex gives a stable ordering
    a, b = sorted([user_a_id, user_b_id], key=str)

    # Fast path: conversation already exists
    result = await db.execute(
        select(Conversation).where(
            Conversation.participant_a == a,
            Conversation.participant_b == b,
        )
    )
    conv = result.scalar_one_or_none()
    if conv:
        return conv

    # Insert with ON CONFLICT DO NOTHING to handle concurrent requests
    stmt = (
        pg_insert(Conversation)
        .values(id=_uuid.uuid4(), participant_a=a, participant_b=b)
        .on_conflict_do_nothing(
            index_elements=["participant_a", "participant_b"]
        )
    )
    await db.execute(stmt)
    await db.flush()

    # Re-select — always finds a row (either we just inserted or a concurrent one)
    result = await db.execute(
        select(Conversation).where(
            Conversation.participant_a == a,
            Conversation.participant_b == b,
        )
    )
    return result.scalar_one()


async def open_conversation_with(
    db: AsyncSession, user: User, other_user_id: UUID
) -> ConversationResponse:
    """
    POST /api/conversations/ — get-or-create a 1-on-1 chat with `other_user_id`.

    Authorization mirrors `_assert_can_message` in message_service: the user
    must have the other party in their contacts (not blocked), and the other
    party must not have blocked the user back. Otherwise we'd silently let
    blocked users open a chat shell and discover the block only on send.
    """
    if other_user_id == user.id:
        raise ValidationFailedError("Cannot open a conversation with yourself")

    other_r = await db.execute(
        select(User).where(User.id == other_user_id, User.is_active.is_(True))
    )
    other = other_r.scalar_one_or_none()
    if other is None:
        raise NotFoundError("User not found")

    fwd_r = await db.execute(
        select(Contact).where(
            Contact.user_id == user.id,
            Contact.contact_user_id == other_user_id,
        )
    )
    fwd = fwd_r.scalar_one_or_none()
    if fwd is None:
        raise ForbiddenError("User is not in your contacts")
    if fwd.is_blocked:
        raise ForbiddenError("You have blocked this contact")

    rev_r = await db.execute(
        select(Contact).where(
            Contact.user_id == other_user_id,
            Contact.contact_user_id == user.id,
        )
    )
    rev = rev_r.scalar_one_or_none()
    if rev is not None and rev.is_blocked:
        raise ForbiddenError("You cannot open a conversation with this user")

    conv = await get_or_create_conversation(db, user.id, other_user_id)

    # Return the same shape list_conversations uses so the Flutter client can
    # reuse its ConversationResponse parser. last_message will be None on a
    # freshly-created conversation; populated otherwise.
    last_message: MessageResponse | None = None
    if conv.last_message_id is not None:
        msg_r = await db.execute(
            select(Message).where(Message.id == conv.last_message_id)
        )
        msg = msg_r.scalar_one_or_none()
        if msg is not None:
            media_resp: MediaResponse | None = None
            if msg.media_id and msg.deleted_at is None:
                mf_r = await db.execute(
                    select(MediaFile).where(MediaFile.id == msg.media_id)
                )
                mf = mf_r.scalar_one_or_none()
                if mf:
                    from app.services.media_service import media_file_to_response
                    media_resp = media_file_to_response(mf)
            last_message = _msg_to_response(msg, media_resp)

    unread_r = await db.execute(
        select(func.count())
        .select_from(MessageReceipt)
        .join(Message, Message.id == MessageReceipt.message_id)
        .where(
            Message.conversation_id == conv.id,
            MessageReceipt.user_id == user.id,
            MessageReceipt.read_at.is_(None),
            Message.deleted_at.is_(None),
        )
    )
    unread_count: int = unread_r.scalar() or 0

    return ConversationResponse(
        id=conv.id,
        other_user=UserPublic.model_validate(other),
        last_message=last_message,
        last_activity=conv.last_activity,
        unread_count=unread_count,
    )


async def list_conversations(
    db: AsyncSession, user: User
) -> list[ConversationResponse]:
    """
    All conversations where *user* is a participant, newest activity first.
    Each item includes the other participant, last message, and unread count.
    """
    result = await db.execute(
        select(Conversation)
        .where(
            or_(
                Conversation.participant_a == user.id,
                Conversation.participant_b == user.id,
            )
        )
        .order_by(Conversation.last_activity.desc())
    )
    conversations = result.scalars().all()

    responses: list[ConversationResponse] = []
    for conv in conversations:
        other_user_id: UUID = (
            conv.participant_b
            if conv.participant_a == user.id
            else conv.participant_a
        )

        # Load the other participant
        other_result = await db.execute(
            select(User).where(User.id == other_user_id)
        )
        other_user = other_result.scalar_one()

        # Load the last message (if any), with its media
        last_message: MessageResponse | None = None
        if conv.last_message_id:
            msg_result = await db.execute(
                select(Message).where(Message.id == conv.last_message_id)
            )
            msg = msg_result.scalar_one_or_none()
            if msg:
                media_resp: MediaResponse | None = None
                if msg.media_id and msg.deleted_at is None:
                    mf_r = await db.execute(
                        select(MediaFile).where(MediaFile.id == msg.media_id)
                    )
                    mf = mf_r.scalar_one_or_none()
                    if mf:
                        from app.services.media_service import media_file_to_response
                        media_resp = media_file_to_response(mf)
                last_message = _msg_to_response(msg, media_resp)

        # Count unread: receipts belonging to *user* with read_at IS NULL
        unread_result = await db.execute(
            select(func.count())
            .select_from(MessageReceipt)
            .join(Message, Message.id == MessageReceipt.message_id)
            .where(
                Message.conversation_id == conv.id,
                MessageReceipt.user_id == user.id,
                MessageReceipt.read_at.is_(None),
                Message.deleted_at.is_(None),
            )
        )
        unread_count: int = unread_result.scalar() or 0

        responses.append(
            ConversationResponse(
                id=conv.id,
                other_user=UserPublic.model_validate(other_user),
                last_message=last_message,
                last_activity=conv.last_activity,
                unread_count=unread_count,
            )
        )

    return responses

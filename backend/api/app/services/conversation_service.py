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
    msg: Message,
    media: MediaResponse | None = None,
    reactions: list | None = None,
) -> MessageResponse:
    """
    Build a MessageResponse, masking content/media for soft-deleted messages.
    Soft-deleted messages also drop their reactions client-side — the tombstone
    is supposed to look inert, so we don't return them even if rows linger.
    Caller is responsible for batching reaction loads; pass [] for none.
    """
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
        reactions=[] if deleted else (reactions or []),
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

    Avoids N+1 by batching the four lookups (other users, last messages,
    their media, unread counts) into one query each.
    """
    from app.services.media_service import media_file_to_response

    # 1) Fetch the conversation rows in a single query.
    conv_result = await db.execute(
        select(Conversation)
        .where(
            or_(
                Conversation.participant_a == user.id,
                Conversation.participant_b == user.id,
            )
        )
        .order_by(Conversation.last_activity.desc())
    )
    conversations = conv_result.scalars().all()
    if not conversations:
        return []

    other_user_ids: set[UUID] = set()
    last_message_ids: set[UUID] = set()
    conv_ids: list[UUID] = []
    for conv in conversations:
        conv_ids.append(conv.id)
        other_user_ids.add(
            conv.participant_b
            if conv.participant_a == user.id
            else conv.participant_a
        )
        if conv.last_message_id is not None:
            last_message_ids.add(conv.last_message_id)

    # 2) Batch-fetch the other participants.
    users_result = await db.execute(
        select(User).where(User.id.in_(other_user_ids))
    )
    users_by_id: dict[UUID, User] = {u.id: u for u in users_result.scalars().all()}

    # 3) Batch-fetch the last messages.
    messages_by_id: dict[UUID, Message] = {}
    media_ids_to_load: set[UUID] = set()
    if last_message_ids:
        msg_result = await db.execute(
            select(Message).where(Message.id.in_(last_message_ids))
        )
        for msg in msg_result.scalars().all():
            messages_by_id[msg.id] = msg
            if msg.media_id is not None and msg.deleted_at is None:
                media_ids_to_load.add(msg.media_id)

    # 4) Batch-fetch the media files referenced by those last messages.
    media_by_id: dict[UUID, MediaResponse] = {}
    if media_ids_to_load:
        mf_result = await db.execute(
            select(MediaFile).where(MediaFile.id.in_(media_ids_to_load))
        )
        for mf in mf_result.scalars().all():
            media_by_id[mf.id] = media_file_to_response(mf)

    # 5) Single aggregate query for unread counts across all conversations.
    unread_result = await db.execute(
        select(Message.conversation_id, func.count())
        .select_from(MessageReceipt)
        .join(Message, Message.id == MessageReceipt.message_id)
        .where(
            Message.conversation_id.in_(conv_ids),
            MessageReceipt.user_id == user.id,
            MessageReceipt.read_at.is_(None),
            Message.deleted_at.is_(None),
        )
        .group_by(Message.conversation_id)
    )
    unread_by_conv: dict[UUID, int] = dict(unread_result.all())

    # 6) Assemble responses.
    responses: list[ConversationResponse] = []
    for conv in conversations:
        other_user_id = (
            conv.participant_b
            if conv.participant_a == user.id
            else conv.participant_a
        )
        other_user = users_by_id.get(other_user_id)
        if other_user is None:
            # Other user deleted — skip the row rather than 500 the page.
            continue

        last_message: MessageResponse | None = None
        if conv.last_message_id is not None:
            msg = messages_by_id.get(conv.last_message_id)
            if msg is not None:
                media_resp = (
                    media_by_id.get(msg.media_id)
                    if msg.media_id is not None and msg.deleted_at is None
                    else None
                )
                last_message = _msg_to_response(msg, media_resp)

        responses.append(
            ConversationResponse(
                id=conv.id,
                other_user=UserPublic.model_validate(other_user),
                last_message=last_message,
                last_activity=conv.last_activity,
                unread_count=unread_by_conv.get(conv.id, 0),
            )
        )

    return responses

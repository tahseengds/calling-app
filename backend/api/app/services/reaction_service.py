"""
Reaction service — add, remove, aggregate.

Design notes:
  - One row per (message, user, emoji) in message_reactions. Toggling the
    same emoji from the same user is a delete; a different emoji is a new row.
  - Adds are idempotent via ON CONFLICT DO NOTHING; a repeat POST returns
    the current summary without an error so the client can be naive.
  - Every change publishes to the OTHER participant's msg_delivery channel
    so their open chat updates without a refetch. The actor's own clients
    use the HTTP response as the source of truth.
  - Authorization mirrors fetch_messages: the user must be a participant in
    the message's conversation. Soft-deleted messages can't be reacted to.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from uuid import UUID

import redis.asyncio as aioredis
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conversation import Conversation
from app.models.message import Message, MessageReaction
from app.models.user import User
from app.schemas.message import ReactionSummary
from app.services.realtime import msg_delivery_channel, publish
from app.utils.exceptions import ForbiddenError, NotFoundError, ValidationFailedError


# ── Aggregation helpers ──────────────────────────────────────────────────────

async def load_reactions_for_messages(
    db: AsyncSession, message_ids: list[UUID]
) -> dict[UUID, list[ReactionSummary]]:
    """
    Batch-load reactions for many messages in a single query and group by
    message_id + emoji. Returns a map from message_id → list of summaries
    in insertion order (earliest emoji first). Messages with no reactions
    are absent from the map.
    """
    if not message_ids:
        return {}

    result = await db.execute(
        select(MessageReaction)
        .where(MessageReaction.message_id.in_(message_ids))
        .order_by(MessageReaction.created_at.asc(), MessageReaction.id.asc())
    )
    rows = result.scalars().all()

    # Group: message_id → emoji → (user_ids, first_reacted_at)
    grouped: dict[UUID, dict[str, dict]] = defaultdict(dict)
    for row in rows:
        bucket = grouped[row.message_id].get(row.emoji)
        if bucket is None:
            grouped[row.message_id][row.emoji] = {
                "user_ids": [row.user_id],
                "first_reacted_at": row.created_at,
            }
        else:
            bucket["user_ids"].append(row.user_id)

    out: dict[UUID, list[ReactionSummary]] = {}
    for msg_id, by_emoji in grouped.items():
        out[msg_id] = [
            ReactionSummary(
                emoji=emoji,
                count=len(entry["user_ids"]),
                user_ids=entry["user_ids"],
                first_reacted_at=entry["first_reacted_at"],
            )
            for emoji, entry in sorted(
                by_emoji.items(), key=lambda kv: kv[1]["first_reacted_at"]
            )
        ]
    return out


async def _summary_for_message(
    db: AsyncSession, message_id: UUID
) -> list[ReactionSummary]:
    """Convenience wrapper around load_reactions_for_messages for one msg."""
    grouped = await load_reactions_for_messages(db, [message_id])
    return grouped.get(message_id, [])


# ── Authorization ────────────────────────────────────────────────────────────

async def _load_message_for_reaction(
    db: AsyncSession, user: User, message_id: UUID
) -> tuple[Message, UUID]:
    """
    Resolve the message, verify the user is a participant in its conversation,
    and return (message, other_participant_id). Reacting to a soft-deleted
    message is rejected — there's nothing meaningful to react to.
    """
    result = await db.execute(select(Message).where(Message.id == message_id))
    msg = result.scalar_one_or_none()
    if msg is None:
        raise NotFoundError("Message not found")
    if msg.deleted_at is not None:
        raise ValidationFailedError("Cannot react to a deleted message")

    conv_r = await db.execute(
        select(Conversation).where(Conversation.id == msg.conversation_id)
    )
    conv = conv_r.scalar_one_or_none()
    if conv is None or user.id not in (conv.participant_a, conv.participant_b):
        raise ForbiddenError("Conversation not found or access denied")

    other_id = (
        conv.participant_b if conv.participant_a == user.id else conv.participant_a
    )
    return msg, other_id


# ── Public API ───────────────────────────────────────────────────────────────

async def add_reaction(
    db: AsyncSession,
    redis: aioredis.Redis,
    user: User,
    message_id: UUID,
    emoji: str,
) -> list[ReactionSummary]:
    """
    Add (or no-op if it already exists) the user's reaction. Returns the full
    updated reaction summary for the message. Publishes a 'reaction_added'
    event to the other participant.
    """
    msg, other_id = await _load_message_for_reaction(db, user, message_id)

    stmt = (
        pg_insert(MessageReaction)
        .values(message_id=msg.id, user_id=user.id, emoji=emoji)
        .on_conflict_do_nothing(
            index_elements=["message_id", "user_id", "emoji"]
        )
    )
    await db.execute(stmt)
    await db.flush()

    summaries = await _summary_for_message(db, msg.id)

    await publish(
        redis,
        msg_delivery_channel(str(other_id)),
        {
            "event": "reaction_added",
            "message_id": str(msg.id),
            "conversation_id": str(msg.conversation_id),
            "user_id": str(user.id),
            "emoji": emoji,
            "reactions": [s.model_dump(mode="json") for s in summaries],
        },
    )

    return summaries


async def remove_reaction(
    db: AsyncSession,
    redis: aioredis.Redis,
    user: User,
    message_id: UUID,
    emoji: str,
) -> list[ReactionSummary]:
    """
    Remove the user's reaction (or no-op if absent). Returns the updated
    summary. Publishes a 'reaction_removed' event to the other participant
    so their chip row updates in place.
    """
    msg, other_id = await _load_message_for_reaction(db, user, message_id)

    await db.execute(
        delete(MessageReaction).where(
            MessageReaction.message_id == msg.id,
            MessageReaction.user_id == user.id,
            MessageReaction.emoji == emoji,
        )
    )
    await db.flush()

    summaries = await _summary_for_message(db, msg.id)

    await publish(
        redis,
        msg_delivery_channel(str(other_id)),
        {
            "event": "reaction_removed",
            "message_id": str(msg.id),
            "conversation_id": str(msg.conversation_id),
            "user_id": str(user.id),
            "emoji": emoji,
            "reactions": [s.model_dump(mode="json") for s in summaries],
        },
    )

    return summaries

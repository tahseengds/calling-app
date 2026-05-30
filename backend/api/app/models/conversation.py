from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Integer, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .message import Message
    from .user import User


class Conversation(Base):
    __tablename__ = "conversations"
    # Mirrors the DB-level unique constraint from migration 0001 so the ORM
    # metadata matches reality. (participant_a, participant_b) are normalized
    # (sorted) before insert, so this also backs the ON CONFLICT upsert.
    __table_args__ = (
        UniqueConstraint("participant_a", "participant_b"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    participant_a: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    participant_b: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    # Plain UUID — no FK to avoid circular dependency with messages.
    # Application code is responsible for keeping this consistent.
    last_message_id: Mapped[uuid.UUID | None] = mapped_column(PGUUID(as_uuid=True))
    last_activity: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    # Disappearing messages: TTL in seconds applied to new messages in this
    # conversation. NULL = disabled (messages persist).
    disappearing_seconds: Mapped[int | None] = mapped_column(Integer)

    user_a: Mapped[User] = relationship(
        "User", foreign_keys=[participant_a], lazy="raise"
    )
    user_b: Mapped[User] = relationship(
        "User", foreign_keys=[participant_b], lazy="raise"
    )
    messages: Mapped[list[Message]] = relationship(
        "Message", back_populates="conversation", lazy="raise"
    )

    def __repr__(self) -> str:
        return f"<Conversation id={self.id}>"

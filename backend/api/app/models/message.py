from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .conversation import Conversation
    from .media import MediaFile
    from .user import User


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("conversations.id", ondelete="CASCADE"),
        nullable=False,
    )
    sender_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    message_type: Mapped[str] = mapped_column(String(20), nullable=False)
    content: Mapped[str | None] = mapped_column(Text)
    media_id: Mapped[uuid.UUID | None] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("media_files.id")
    )
    reply_to_id: Mapped[uuid.UUID | None] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("messages.id")
    )
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="sent")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    conversation: Mapped[Conversation] = relationship(
        "Conversation", back_populates="messages", lazy="raise"
    )
    sender: Mapped[User] = relationship(
        "User", foreign_keys=[sender_id], lazy="raise"
    )
    media: Mapped[MediaFile | None] = relationship("MediaFile", lazy="raise")
    reply_to: Mapped[Message | None] = relationship(
        "Message", remote_side="Message.id", foreign_keys=[reply_to_id], lazy="raise"
    )
    replies: Mapped[list[Message]] = relationship(
        "Message",
        primaryjoin="Message.reply_to_id == Message.id",
        foreign_keys=[reply_to_id],
        lazy="raise",
        viewonly=True,
    )
    receipts: Mapped[list[MessageReceipt]] = relationship(
        "MessageReceipt", back_populates="message", lazy="raise"
    )

    def __repr__(self) -> str:
        return f"<Message id={self.id}>"


class MessageReceipt(Base):
    __tablename__ = "message_receipts"

    message_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("messages.id", ondelete="CASCADE"),
        primary_key=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("users.id"), primary_key=True
    )
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    message: Mapped[Message] = relationship(
        "Message", back_populates="receipts", lazy="raise"
    )
    user: Mapped[User] = relationship("User", lazy="raise")

    def __repr__(self) -> str:
        return f"<MessageReceipt message_id={self.message_id} user_id={self.user_id}>"

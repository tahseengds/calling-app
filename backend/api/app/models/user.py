from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .contact import Contact
    from .refresh_token import RefreshToken


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    # phone is optional — phone-based sign-in was removed in favor of Google
    # and email/password. Older rows from the phone-auth era keep their value.
    phone: Mapped[str | None] = mapped_column(String(20), unique=True)
    # email is the primary identifier for the new auth flow (Google or
    # email/password). Nullable for the same reason as phone.
    email: Mapped[str | None] = mapped_column(String(254), unique=True, index=True)
    # Firebase UID — stable across sessions for a given identity within our
    # Firebase project. Use this as the lookup key when trading a Firebase ID
    # token for our own JWTs.
    firebase_uid: Mapped[str | None] = mapped_column(String(128), unique=True, index=True)
    # 'google.com' | 'password' — informational, used to enforce the
    # email-verified rule (we only require it for password sign-ins; Google
    # email-verified is always true).
    auth_provider: Mapped[str | None] = mapped_column(String(32))
    avatar_url: Mapped[str | None] = mapped_column(Text)
    fcm_token: Mapped[str | None] = mapped_column(Text)
    fcm_token_updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    password_hash: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_seen: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    notification_preferences: Mapped[dict] = mapped_column(
        JSONB, nullable=False, default=dict, server_default="{}"
    )
    privacy_settings: Mapped[dict] = mapped_column(
        JSONB, nullable=False, default=dict, server_default="{}"
    )

    contacts: Mapped[list[Contact]] = relationship(
        "Contact",
        foreign_keys="Contact.user_id",
        back_populates="user",
        lazy="raise",
    )
    refresh_tokens: Mapped[list[RefreshToken]] = relationship(
        "RefreshToken", back_populates="user", lazy="raise"
    )

    def __repr__(self) -> str:
        return f"<User id={self.id}>"

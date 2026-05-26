import re
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, field_validator

from app.schemas.user import UserPublic


class AddContactRequest(BaseModel):
    """
    Caller supplies *one* of email or phone to look up the target user.
    Email is the primary identifier under the new auth flow; phone is
    accepted for backward compatibility / legacy accounts.
    """
    email: str | None = None
    phone: str | None = None
    nickname: str | None = None

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str | None) -> str | None:
        if v is None:
            return None
        if not re.match(r"^\+[1-9]\d{7,14}$", v):
            raise ValueError("Phone must be E.164 format, e.g. +14155552671")
        return v

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip().lower()
        if not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", v):
            raise ValueError("Enter a valid email address")
        return v


class BlockRequest(BaseModel):
    blocked: bool


class ContactResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    contact_user: UserPublic
    nickname: str | None
    is_blocked: bool
    created_at: datetime

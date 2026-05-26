import re
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, field_validator

from app.schemas.user import UserPublic


class AddContactRequest(BaseModel):
    """Look up the target user by email."""

    email: str
    nickname: str | None = None

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
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

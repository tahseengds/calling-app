import re
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, field_validator

from app.schemas.user import UserPublic


class AddContactRequest(BaseModel):
    phone: str
    nickname: str | None = None

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        if not re.match(r"^\+[1-9]\d{7,14}$", v):
            raise ValueError("Phone must be E.164 format, e.g. +14155552671")
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

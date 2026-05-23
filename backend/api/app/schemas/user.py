from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, field_validator


class UserPublic(BaseModel):
    """What any authenticated user may see about another user. Never leaks fcm_token or password_hash."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    phone: str
    avatar_url: str | None
    last_seen: datetime


class UserMe(UserPublic):
    """Extended profile visible only to the owner."""

    created_at: datetime
    is_active: bool


class UpdateProfileRequest(BaseModel):
    name: str | None = None

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str | None) -> str | None:
        if v is not None and not (1 <= len(v.strip()) <= 100):
            raise ValueError("name must be between 1 and 100 characters")
        return v


class FcmTokenRequest(BaseModel):
    fcm_token: str
    device_id: str

    @field_validator("fcm_token")
    @classmethod
    def validate_fcm_token(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("fcm_token must be non-empty")
        return v

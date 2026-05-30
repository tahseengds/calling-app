from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

SupportCategory = Literal["bug", "feature", "account", "other"]
SupportStatus = Literal["open", "in_progress", "resolved"]


class SupportFeedbackRequest(BaseModel):
    category: SupportCategory
    message: str = Field(..., min_length=10, max_length=2000)
    app_version: str | None = Field(default=None, max_length=32)
    platform: str | None = Field(default=None, max_length=16)
    device_info: dict | None = None


class SupportFeedbackResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    created_at: datetime


class SupportRequestAdmin(BaseModel):
    """A single support request as seen by an administrator — includes the
    submitter's identity and the full message + diagnostic metadata."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    user_name: str | None = None
    user_email: str | None = None
    # Plain str (not the SupportCategory literal) so the admin view never 500s
    # on a legacy/unexpected category value.
    category: str
    message: str
    app_version: str | None = None
    platform: str | None = None
    device_info: dict = {}
    status: str = "open"
    handled_by: str | None = None
    resolved_at: datetime | None = None
    created_at: datetime


class SupportRequestList(BaseModel):
    """Admin listing payload: the rows plus a total count for the header."""

    total: int
    open_count: int
    requests: list[SupportRequestAdmin]


class SupportStatusUpdate(BaseModel):
    """Admin status change for a single support request."""

    status: SupportStatus

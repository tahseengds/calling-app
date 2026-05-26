from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

SupportCategory = Literal["bug", "feature", "account", "other"]


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

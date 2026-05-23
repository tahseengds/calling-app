from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class MediaResponse(BaseModel):
    """
    Metadata and signed access URL for an uploaded media file.
    url is a short-lived HMAC-signed URL served by Nginx via /media/.
    thumbnail_url is None for audio and documents.
    duration_seconds is None for images and documents.
    """
    model_config = ConfigDict(from_attributes=False)

    id: UUID
    file_type: str
    original_name: str | None
    mime_type: str | None
    file_size: int | None
    duration_seconds: int | None
    width: int | None
    height: int | None
    thumbnail_url: str | None
    url: str
    created_at: datetime

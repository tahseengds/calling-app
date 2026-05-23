"""
Media router — /api/media

POST /upload        — multipart upload; returns MediaResponse with signed URL.
GET  /verify-signature — Nginx auth_request target (no JWT required).
                         Returns 204 if the URL signature is valid, 403 otherwise.

Nginx integration (implemented in prompt 10):
    location /media/ {
        auth_request /api/media/verify-signature;
        alias /var/app-media/;
        expires 7d;
        add_header Accept-Ranges bytes;
    }
    # Nginx passes the original URI so the FastAPI endpoint can verify it:
    location = /api/media/verify-signature {
        internal;
        proxy_pass http://fastapi;
        proxy_set_header X-Original-URI $request_uri;
    }
"""
import urllib.parse
from typing import Annotated, Literal

import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, File, Form, Query, Request, Response, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user, get_db, get_redis, rate_limit
from app.models.user import User
from app.schemas.media import MediaResponse
from app.services import media_service
from app.utils.storage import verify_media_signature

router = APIRouter()

MediaType = Literal["image", "video", "audio", "document"]


@router.post(
    "/upload",
    response_model=MediaResponse,
    dependencies=[
        Depends(rate_limit("media_upload", max_calls=30, window_seconds=60))
    ],
)
async def upload_media(
    file: Annotated[UploadFile, File(description="The file to upload")],
    type: Annotated[MediaType, Form(description="Declared media type")],
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> MediaResponse:
    return await media_service.upload_media(db, current_user, file, type)


@router.get("/verify-signature", include_in_schema=False)
async def verify_signature(
    request: Request,
    stored_name: str | None = Query(default=None),
    sig: str | None = Query(default=None),
    exp: str | None = Query(default=None),
) -> Response:
    """
    Verify an HMAC-signed media URL. Called by Nginx auth_request internally;
    also accepts direct query params for testing.

    When called by Nginx, the original request URI arrives via the
    X-Original-URI header — stored_name is extracted from the path component.
    Direct query params (stored_name, sig, exp) override header-derived values.
    """
    original_uri = request.headers.get("x-original-uri")
    if original_uri and stored_name is None:
        parsed = urllib.parse.urlparse(original_uri)
        qs = urllib.parse.parse_qs(parsed.query)
        sig = qs.get("sig", [sig])[0]
        exp = qs.get("exp", [exp])[0]
        # Path: /media/{stored_name}
        path = parsed.path.lstrip("/")
        if path.startswith("media/"):
            stored_name = path[len("media/"):]

    if not stored_name or not sig or not exp:
        return Response(status_code=403)

    if verify_media_signature(stored_name, sig, exp):
        return Response(status_code=204)
    return Response(status_code=403)

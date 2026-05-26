"""
Media upload, validation, and processing service.

Processing strategy (10-user family app):
  - Images and avatars: processed inline with Pillow (fast, in-process).
  - Audio: transcoded inline with FFmpeg (~real-time for voice notes).
  - Video: original stored as-is (no re-encode — 150 MB re-encode is expensive);
    thumbnail extracted inline with FFmpeg. If FFmpeg fails, upload still succeeds.
  - Documents: stored as-is.

All processors are standalone async functions so a background worker (prompt 07)
could call the same code without changes.

Storage:
  images/originals/{uuid}.webp        — full-size WebP
  images/thumbnails/{uuid}_thumb.webp — 400×400 max thumbnail
  videos/originals/{uuid}.mp4
  videos/thumbnails/{uuid}_thumb.webp
  audio/{uuid}.aac
  documents/{uuid}.{ext}
  avatars/{uuid}.webp
"""
from __future__ import annotations

import asyncio
import io
import json
import logging
import uuid as _uuid
from dataclasses import dataclass
from pathlib import Path

import aiofiles
import magic
from PIL import Image, ImageOps
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.media import MediaFile
from app.models.user import User
from app.schemas.media import MediaResponse
from app.utils.exceptions import FileTooLargeError, UnsupportedMediaTypeError
from app.utils.storage import (
    ensure_media_dirs,
    generate_media_signed_url,
    write_bytes,
)

logger = logging.getLogger(__name__)

# ── MIME allowlists ────────────────────────────────────────────────────────────

_ALLOWED: dict[str, set[str]] = {
    "image": {
        "image/jpeg", "image/png", "image/webp",
        "image/heic", "image/heif",
    },
    "video": {
        "video/mp4", "video/quicktime", "video/webm",
        "video/x-msvideo",
    },
    "audio": {
        "audio/mp4", "audio/aac", "audio/ogg",
        "audio/webm", "audio/wav", "audio/x-wav",
        "audio/x-m4a", "audio/amr", "audio/mpeg",
        "audio/x-ms-wma",
    },
    "document": {
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "text/plain",
    },
}

def _get_size_limit_mb(declared_type: str) -> int:
    """Look up the per-type size limit from settings dynamically (supports monkeypatching in tests)."""
    return {
        "image": settings.MAX_IMAGE_SIZE_MB,
        "video": settings.MAX_VIDEO_SIZE_MB,
        "audio": settings.MAX_AUDIO_SIZE_MB,
        "document": settings.MAX_DOCUMENT_SIZE_MB,
        "avatar": settings.MAX_AVATAR_SIZE_MB,
    }.get(declared_type, 25)


# ── Validated upload container ────────────────────────────────────────────────

@dataclass
class ValidatedFile:
    data: bytes
    mime_type: str
    original_name: str
    file_size: int


# ── Validation ────────────────────────────────────────────────────────────────

async def validate_upload(
    upload,                 # fastapi.UploadFile
    declared_type: str,     # "image" | "video" | "audio" | "document" | "avatar"
) -> ValidatedFile:
    """
    Stream the upload, enforce size limits, detect real MIME type via magic bytes,
    and reject if the type doesn't match the allowlist for declared_type.
    Raises FileTooLargeError (413) or UnsupportedMediaTypeError (415).
    """
    img_type = declared_type if declared_type != "avatar" else "image"
    limit_bytes = _get_size_limit_mb(declared_type) * 1024 * 1024

    # Stream and accumulate — abort immediately if limit exceeded
    chunks: list[bytes] = []
    total = 0
    chunk_size = 256 * 1024  # 256 KB chunks

    while True:
        chunk = await upload.read(chunk_size)
        if not chunk:
            break
        total += len(chunk)
        if total > limit_bytes:
            raise FileTooLargeError(
                f"File exceeds the {_get_size_limit_mb(declared_type)} MB limit"
            )
        chunks.append(chunk)

    data = b"".join(chunks)

    # Detect real MIME via magic bytes (first 2048 bytes is enough)
    detected_mime = magic.from_buffer(data[:2048], mime=True)

    allowed = _ALLOWED.get(img_type, set())
    if detected_mime not in allowed:
        raise UnsupportedMediaTypeError(
            f"Detected MIME type '{detected_mime}' is not allowed for type '{declared_type}'. "
            f"Allowed: {sorted(allowed)}"
        )

    original_name = getattr(upload, "filename", None) or "upload"
    return ValidatedFile(
        data=data,
        mime_type=detected_mime,
        original_name=original_name,
        file_size=total,
    )


# ── Image processing ──────────────────────────────────────────────────────────

def _open_image(data: bytes) -> Image.Image:
    img = Image.open(io.BytesIO(data))
    img = ImageOps.exif_transpose(img)   # auto-orient
    # Strip EXIF by converting to a clean mode
    if img.mode in ("RGBA", "P", "LA"):
        img = img.convert("RGBA")
    else:
        img = img.convert("RGB")
    return img


async def process_image(
    data: bytes, media_id: str
) -> tuple[str, str, int, int]:
    """
    Convert to WebP + generate thumbnail.
    Returns (stored_name, thumb_stored_name, width, height).
    """
    base = Path(settings.MEDIA_BASE_PATH)
    stored_name = f"images/originals/{media_id}.webp"
    thumb_stored_name = f"images/thumbnails/{media_id}_thumb.webp"

    img = _open_image(data)
    width, height = img.size

    # Save original as WebP
    buf = io.BytesIO()
    img.save(buf, "WEBP", quality=85)
    await write_bytes(base / stored_name, buf.getvalue())

    # Thumbnail (max 400×400, preserve aspect ratio)
    thumb = img.copy()
    thumb.thumbnail((400, 400), Image.LANCZOS)
    tbuf = io.BytesIO()
    thumb.save(tbuf, "WEBP", quality=85)
    await write_bytes(base / thumb_stored_name, tbuf.getvalue())

    return stored_name, thumb_stored_name, width, height


async def process_avatar(data: bytes, media_id: str) -> str:
    """
    Convert to WebP, cover-crop to 200×200.
    Returns stored_name.
    """
    base = Path(settings.MEDIA_BASE_PATH)
    stored_name = f"avatars/{media_id}.webp"

    img = _open_image(data)
    # Cover crop: fill 200×200, centred
    img = ImageOps.fit(img, (200, 200), Image.LANCZOS)

    buf = io.BytesIO()
    img.save(buf, "WEBP", quality=85)
    await write_bytes(base / stored_name, buf.getvalue())

    return stored_name


# ── Video processing ──────────────────────────────────────────────────────────

async def process_video(
    data: bytes, media_id: str
) -> tuple[str, str | None, int | None, int | None, int | None]:
    """
    Store original MP4 (no re-encode), extract thumbnail and metadata.
    Returns (stored_name, thumb_stored_name|None, duration|None, width|None, height|None).
    Re-encoding omitted — too expensive for large files. Document: transcode via
    a separate worker if needed.
    """
    base = Path(settings.MEDIA_BASE_PATH)
    stored_name = f"videos/originals/{media_id}.mp4"
    thumb_stored_name = f"videos/thumbnails/{media_id}_thumb.webp"

    input_path = base / stored_name
    thumb_path = base / thumb_stored_name
    await write_bytes(input_path, data)

    duration: int | None = None
    width: int | None = None
    height: int | None = None
    actual_thumb: str | None = None

    # Extract thumbnail at ~1 second
    try:
        proc = await asyncio.create_subprocess_exec(
            "ffmpeg", "-y", "-ss", "1", "-i", str(input_path),
            "-vframes", "1", "-f", "webp", str(thumb_path),
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        _, err = await proc.communicate()
        if proc.returncode == 0 and thumb_path.exists():
            actual_thumb = thumb_stored_name
        else:
            logger.warning("FFmpeg thumbnail failed for %s: %s", media_id, err.decode())
    except Exception as exc:
        logger.warning("FFmpeg error for %s: %s", media_id, exc)

    # Extract metadata with ffprobe
    try:
        probe = await asyncio.create_subprocess_exec(
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_streams", str(input_path),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await probe.communicate()
        if probe.returncode == 0:
            info = json.loads(stdout)
            for stream in info.get("streams", []):
                if stream.get("codec_type") == "video":
                    width = stream.get("width")
                    height = stream.get("height")
                    dur = stream.get("duration")
                    if dur:
                        duration = int(float(dur))
                    break
    except Exception as exc:
        logger.warning("ffprobe error for %s: %s", media_id, exc)

    return stored_name, actual_thumb, duration, width, height


# ── Audio processing ──────────────────────────────────────────────────────────

async def process_audio(
    data: bytes, media_id: str
) -> tuple[str, int | None]:
    """
    Transcode to AAC 32 kbps mono via FFmpeg.
    Returns (stored_name, duration_seconds|None).
    """
    base = Path(settings.MEDIA_BASE_PATH)
    stored_name = f"audio/{media_id}.aac"
    output_path = base / stored_name

    # Write input to a temp file so FFmpeg can read it
    import tempfile, os
    with tempfile.NamedTemporaryFile(delete=False, suffix=".input") as tmp:
        tmp.write(data)
        tmp_path = tmp.name

    duration: int | None = None
    try:
        proc = await asyncio.create_subprocess_exec(
            "ffmpeg", "-y", "-i", tmp_path,
            "-acodec", "aac", "-b:a", "32k", "-ac", "1",
            str(output_path),
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        _, err = await proc.communicate()
        if proc.returncode != 0:
            logger.warning("FFmpeg audio transcode failed: %s", err.decode())
            # Fallback: store original bytes
            await write_bytes(output_path, data)
    finally:
        os.unlink(tmp_path)

    # Read duration via ffprobe
    try:
        probe = await asyncio.create_subprocess_exec(
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", str(output_path),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await probe.communicate()
        if probe.returncode == 0:
            info = json.loads(stdout)
            dur = info.get("format", {}).get("duration")
            if dur:
                duration = int(float(dur))
    except Exception as exc:
        logger.warning("ffprobe duration error: %s", exc)

    return stored_name, duration


# ── Document processing ───────────────────────────────────────────────────────

async def process_document(
    data: bytes, media_id: str, original_name: str
) -> str:
    """
    Store document as-is, preserving the original extension.
    Returns stored_name.
    """
    ext = Path(original_name).suffix or ".bin"
    stored_name = f"documents/{media_id}{ext}"
    await write_bytes(Path(settings.MEDIA_BASE_PATH) / stored_name, data)
    return stored_name


# ── MediaResponse builder ────────────────────────────────────────────────────

def media_file_to_response(mf: MediaFile) -> MediaResponse:
    """Build a MediaResponse from a MediaFile ORM object."""
    url = generate_media_signed_url(mf.stored_name) if mf.stored_name else ""
    thumbnail_url = (
        generate_media_signed_url(mf.thumbnail_stored_name)
        if mf.thumbnail_stored_name
        else None
    )
    return MediaResponse(
        id=mf.id,
        file_type=mf.file_type,
        original_name=mf.original_name,
        mime_type=mf.mime_type,
        file_size=mf.file_size,
        duration_seconds=mf.duration_seconds,
        width=mf.width,
        height=mf.height,
        thumbnail_url=thumbnail_url,
        url=url,
        created_at=mf.created_at,
    )


# ── Upload orchestration ──────────────────────────────────────────────────────

async def upload_media(
    db: AsyncSession,
    user: User,
    upload,              # fastapi.UploadFile
    declared_type: str,  # "image" | "video" | "audio" | "document"
) -> MediaResponse:
    """
    Full upload pipeline:
      validate → process → persist DB row → return signed MediaResponse
    """
    ensure_media_dirs()

    vf = await validate_upload(upload, declared_type)
    media_id = str(_uuid.uuid4())

    stored_name: str
    thumb_stored_name: str | None = None
    duration: int | None = None
    width: int | None = None
    height: int | None = None

    if declared_type == "image":
        stored_name, thumb_stored_name, width, height = await process_image(
            vf.data, media_id
        )
    elif declared_type == "video":
        stored_name, thumb_stored_name, duration, width, height = await process_video(
            vf.data, media_id
        )
    elif declared_type == "audio":
        stored_name, duration = await process_audio(vf.data, media_id)
    else:  # document
        stored_name = await process_document(vf.data, media_id, vf.original_name)

    mf = MediaFile(
        id=_uuid.UUID(media_id),
        uploader_id=user.id,
        file_type=declared_type,
        original_name=vf.original_name,
        stored_name=stored_name,
        storage_path=str(Path(settings.MEDIA_BASE_PATH) / stored_name),
        mime_type=vf.mime_type,
        file_size=vf.file_size,
        duration_seconds=duration,
        thumbnail_stored_name=thumb_stored_name,
        width=width,
        height=height,
    )
    db.add(mf)
    await db.commit()

    return media_file_to_response(mf)


async def upload_avatar(
    db: AsyncSession,
    user: User,
    upload,  # fastapi.UploadFile
) -> str:
    """
    Process an avatar image, persist the MediaFile row, and return the signed URL.
    The caller (user_service) sets user.avatar_url.
    """
    ensure_media_dirs()

    vf = await validate_upload(upload, "avatar")
    media_id = str(_uuid.uuid4())
    stored_name = await process_avatar(vf.data, media_id)

    mf = MediaFile(
        id=_uuid.UUID(media_id),
        uploader_id=user.id,
        file_type="avatar",
        original_name=vf.original_name,
        stored_name=stored_name,
        storage_path=str(Path(settings.MEDIA_BASE_PATH) / stored_name),
        mime_type=vf.mime_type,
        file_size=vf.file_size,
    )
    db.add(mf)
    await db.flush()

    return generate_media_signed_url(stored_name)

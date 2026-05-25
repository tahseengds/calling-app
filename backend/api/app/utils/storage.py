"""
Media storage helpers.

Signed URL format:  https://{DOMAIN}/media/{stored_name}?sig={hex}&exp={epoch}
stored_name:        path relative to MEDIA_BASE_PATH, e.g. images/originals/{uuid}.webp
HMAC:               SHA-256 keyed with settings.MEDIA_SECRET
"""
import hashlib
import hmac
import time
from pathlib import Path

import aiofiles

from app.config import settings

# Sub-directories that must exist under MEDIA_BASE_PATH
MEDIA_SUBDIRS: list[str] = [
    "images/originals",
    "images/thumbnails",
    "videos/originals",
    "videos/thumbnails",
    "audio",
    "documents",
    "avatars",
]


def ensure_media_dirs() -> None:
    """Create all required sub-directories (idempotent)."""
    base = Path(settings.MEDIA_BASE_PATH)
    for sub in MEDIA_SUBDIRS:
        (base / sub).mkdir(parents=True, exist_ok=True)


# ── Signed URL ────────────────────────────────────────────────────────────────

def _sign(stored_name: str, expires: int) -> str:
    message = f"{stored_name}:{expires}"
    return hmac.new(
        settings.MEDIA_SECRET.encode("utf-8"),
        message.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def generate_media_signed_url(stored_name: str, ttl: int = 3600) -> str:
    """
    Build a signed URL valid for *ttl* seconds.
    Nginx validates it via GET /api/media/verify-signature (auth_request).
    """
    expires = int(time.time()) + ttl
    sig = _sign(stored_name, expires)
    return (
        f"{settings.MEDIA_URL_SCHEME}://{settings.DOMAIN}/media/{stored_name}"
        f"?sig={sig}&exp={expires}"
    )


def verify_media_signature(stored_name: str, sig: str, exp: str | int) -> bool:
    """
    Return True iff the HMAC is correct and the URL has not expired.
    Uses hmac.compare_digest for constant-time comparison.
    """
    try:
        exp_int = int(exp)
    except (ValueError, TypeError):
        return False

    if int(time.time()) > exp_int:
        return False  # expired

    expected = _sign(stored_name, exp_int)
    return hmac.compare_digest(expected, sig)


# ── Async file I/O ────────────────────────────────────────────────────────────

async def write_bytes(path: Path, data: bytes) -> None:
    """Write *data* to *path* asynchronously."""
    path.parent.mkdir(parents=True, exist_ok=True)
    async with aiofiles.open(path, "wb") as f:
        await f.write(data)

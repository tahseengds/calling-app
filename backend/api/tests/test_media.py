"""
Tests for /api/media and avatar upload.

Covers:
  - POST /api/media/upload (image) → stored as WebP + thumbnail on disk, DB row created
  - Magic-byte mismatch (PDF bytes declared as image) → 415
  - Oversize file → 413 (monkeypatched size limit)
  - GET /api/media/verify-signature → 204 for fresh signed URL, 403 for tampered/expired
  - Voice-note upload (WAV) → AAC output, duration_seconds populated
  - Avatar upload → user avatar_url updated, returns UserMe
  - Media message (prompt 05 integration) serialises with nested media object
"""
import io
import itertools
import struct
import time
import urllib.parse
import uuid
import wave
from pathlib import Path

import pytest
from httpx import AsyncClient
from PIL import Image

from app.config import settings

# ── Email counter ─────────────────────────────────────────────────────────────
_counter = itertools.count(7000)


def _next_email() -> str:
    return f"media{next(_counter)}@example.com"


# ── Helpers ───────────────────────────────────────────────────────────────────

from app.services import auth_service


def _stub_firebase(monkeypatch: pytest.MonkeyPatch, claims: dict) -> None:
    async def _fake(_id_token: str) -> dict:
        return claims

    monkeypatch.setattr(auth_service, "verify_firebase_id_token", _fake)


async def _signin(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
    email: str,
    name: str = "User",
) -> str:
    _stub_firebase(
        monkeypatch,
        {
            "sub": f"fb-{email}",
            "email": email,
            "email_verified": True,
            "name": name,
            "firebase": {"sign_in_provider": "password"},
        },
    )
    r = await client.post(
        "/api/auth/firebase-signin",
        json={"firebase_id_token": "stub", "device_id": "test-device", "name": name},
    )
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_jpeg(width: int = 50, height: int = 50) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (width, height), color=(100, 150, 200)).save(buf, "JPEG")
    buf.seek(0)
    return buf.read()


def _make_wav(seconds: float = 0.5) -> bytes:
    """Create a minimal valid WAV file (mono, 8kHz, silence)."""
    buf = io.BytesIO()
    n_frames = int(8000 * seconds)
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(8000)
        w.writeframes(struct.pack("<" + "h" * n_frames, *([0] * n_frames)))
    buf.seek(0)
    return buf.read()


# ── Image upload tests ────────────────────────────────────────────────────────

async def test_image_upload_creates_webp_and_thumbnail(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    jpeg_bytes = _make_jpeg(100, 100)

    r = await client.post(
        "/api/media/upload",
        files={"file": ("photo.jpg", io.BytesIO(jpeg_bytes), "image/jpeg")},
        data={"type": "image"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    data = r.json()

    assert data["file_type"] == "image"
    assert data["mime_type"] == "image/jpeg"
    assert data["url"].startswith("https://")
    assert data["thumbnail_url"] is not None
    assert data["width"] == 100
    assert data["height"] == 100
    assert data["file_size"] > 0

    # Files must exist on disk
    base = Path(settings.MEDIA_BASE_PATH)
    media_id = str(data["id"])
    orig_path = base / "images" / "originals" / f"{media_id}.webp"
    thumb_path = base / "images" / "thumbnails" / f"{media_id}_thumb.webp"
    assert orig_path.exists(), f"Original WebP not found: {orig_path}"
    assert thumb_path.exists(), f"Thumbnail not found: {thumb_path}"


async def test_magic_byte_mismatch_rejected(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    # PDF bytes masquerading as a JPEG
    fake_jpeg = b"%PDF-1.4 fake pdf content here\n" + b"\x00" * 100

    r = await client.post(
        "/api/media/upload",
        files={"file": ("trick.jpg", io.BytesIO(fake_jpeg), "image/jpeg")},
        data={"type": "image"},
        headers=_auth(token),
    )
    assert r.status_code == 415, r.text
    assert r.json()["code"] == "unsupported_media_type"


async def test_oversize_file_rejected(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    # Temporarily reduce the image size limit to ~100 bytes (0.0001 MB)
    monkeypatch.setattr(settings, "MAX_IMAGE_SIZE_MB", 0)

    # Even a tiny JPEG exceeds 0 MB
    jpeg_bytes = _make_jpeg(10, 10)

    r = await client.post(
        "/api/media/upload",
        files={"file": ("big.jpg", io.BytesIO(jpeg_bytes), "image/jpeg")},
        data={"type": "image"},
        headers=_auth(token),
    )
    assert r.status_code == 413, r.text
    assert r.json()["code"] == "file_too_large"


# ── Signed URL verification tests ─────────────────────────────────────────────

async def test_verify_signature_valid(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    # Upload an image to get a real signed URL
    r = await client.post(
        "/api/media/upload",
        files={"file": ("v.jpg", io.BytesIO(_make_jpeg()), "image/jpeg")},
        data={"type": "image"},
        headers=_auth(token),
    )
    assert r.status_code == 200
    signed_url = r.json()["url"]

    # Parse stored_name, sig, exp from the URL
    parsed = urllib.parse.urlparse(signed_url)
    qs = urllib.parse.parse_qs(parsed.query)
    stored_name = parsed.path.removeprefix("/media/")
    sig = qs["sig"][0]
    exp = qs["exp"][0]

    # Verify via the endpoint (direct query params, no X-Original-URI)
    r2 = await client.get(
        f"/api/media/verify-signature?stored_name={urllib.parse.quote(stored_name, safe='/')}&sig={sig}&exp={exp}"
    )
    assert r2.status_code == 204


async def test_verify_signature_tampered_returns_403(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    r = await client.post(
        "/api/media/upload",
        files={"file": ("t.jpg", io.BytesIO(_make_jpeg()), "image/jpeg")},
        data={"type": "image"},
        headers=_auth(token),
    )
    signed_url = r.json()["url"]
    parsed = urllib.parse.urlparse(signed_url)
    qs = urllib.parse.parse_qs(parsed.query)
    stored_name = parsed.path.removeprefix("/media/")
    exp = qs["exp"][0]

    r2 = await client.get(
        f"/api/media/verify-signature?stored_name={urllib.parse.quote(stored_name, safe='/')}&sig=deadbeef&exp={exp}"
    )
    assert r2.status_code == 403


async def test_verify_signature_expired_returns_403(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    r = await client.post(
        "/api/media/upload",
        files={"file": ("e.jpg", io.BytesIO(_make_jpeg()), "image/jpeg")},
        data={"type": "image"},
        headers=_auth(token),
    )
    signed_url = r.json()["url"]
    parsed = urllib.parse.urlparse(signed_url)
    qs = urllib.parse.parse_qs(parsed.query)
    stored_name = parsed.path.removeprefix("/media/")
    sig = qs["sig"][0]

    # Use an already-expired timestamp
    past_exp = str(int(time.time()) - 3600)

    r2 = await client.get(
        f"/api/media/verify-signature?stored_name={urllib.parse.quote(stored_name, safe='/')}&sig={sig}&exp={past_exp}"
    )
    assert r2.status_code == 403


# ── Audio upload test ─────────────────────────────────────────────────────────

async def test_voice_note_produces_aac_with_duration(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    wav_bytes = _make_wav(seconds=1.0)

    r = await client.post(
        "/api/media/upload",
        files={"file": ("voice.wav", io.BytesIO(wav_bytes), "audio/x-wav")},
        data={"type": "audio"},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    data = r.json()

    assert data["file_type"] == "audio"
    assert data["url"].startswith("https://")
    assert data["thumbnail_url"] is None

    # AAC file must exist on disk
    base = Path(settings.MEDIA_BASE_PATH)
    aac_path = base / "audio" / f"{data['id']}.aac"
    assert aac_path.exists(), f"AAC file not found: {aac_path}"

    # Duration must be populated
    assert data["duration_seconds"] is not None
    assert data["duration_seconds"] >= 1


# ── Avatar upload test ────────────────────────────────────────────────────────

async def test_avatar_upload_updates_user_profile(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    jpeg_bytes = _make_jpeg(300, 300)

    r = await client.post(
        "/api/users/avatar",
        files={"file": ("avatar.jpg", io.BytesIO(jpeg_bytes), "image/jpeg")},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    data = r.json()

    # avatar_url should now be a signed URL
    assert data["avatar_url"] is not None
    assert data["avatar_url"].startswith("https://")

    # Avatar WebP must exist on disk (200×200)
    url_path = urllib.parse.urlparse(data["avatar_url"]).path
    stored_name = url_path.removeprefix("/media/")
    avatar_path = Path(settings.MEDIA_BASE_PATH) / stored_name
    assert avatar_path.exists(), f"Avatar file not found: {avatar_path}"

    # Verify it's 200×200
    from PIL import Image as PILImage
    img = PILImage.open(avatar_path)
    assert img.size == (200, 200)


# ── Media message integration test ───────────────────────────────────────────

async def test_media_message_includes_nested_media(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Acceptance check 4: a media message serialises with a populated media object."""
    email_a, email_b = _next_email(), _next_email()
    token_a = await _signin(client, monkeypatch, email_a, "Alice")
    token_b = await _signin(client, monkeypatch, email_b, "Bob")

    _alice_id = (await client.get("/api/users/me", headers=_auth(token_a))).json()["id"]
    bob_id = (await client.get("/api/users/me", headers=_auth(token_b))).json()["id"]

    # Add contacts (reciprocal)
    r = await client.post("/api/contacts/", json={"email": email_b}, headers=_auth(token_a))
    assert r.status_code == 201

    # Alice uploads a media file
    jpeg_bytes = _make_jpeg(80, 80)
    r2 = await client.post(
        "/api/media/upload",
        files={"file": ("img.jpg", io.BytesIO(jpeg_bytes), "image/jpeg")},
        data={"type": "image"},
        headers=_auth(token_a),
    )
    assert r2.status_code == 200
    media_id = r2.json()["id"]

    # Alice sends a media message to Bob
    client_id = str(uuid.uuid4())
    r3 = await client.post(
        "/api/messages/",
        json={
            "client_id": client_id,
            "recipient_id": bob_id,
            "message_type": "image",
            "media_id": media_id,
        },
        headers=_auth(token_a),
    )
    assert r3.status_code == 201, r3.text
    msg = r3.json()

    # The message response must include a populated nested media object
    assert msg["media"] is not None
    assert msg["media"]["id"] == media_id
    assert msg["media"]["url"].startswith("https://")
    assert msg["media"]["thumbnail_url"] is not None
    assert msg["media"]["width"] == 80
    assert msg["media"]["height"] == 80

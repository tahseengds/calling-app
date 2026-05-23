"""
Tests for /api/users, /api/contacts, and /api/auth/turn-credentials.

Covers:
  - GET /api/users/me returns profile; without token → 401
  - PUT /api/users/me updates name
  - GET /api/users/{user_id} returns UserPublic (no fcm_token / password_hash)
  - POST /api/contacts adds contact and creates reciprocal row
  - Cannot add self
  - Cannot add unknown phone
  - GET /api/contacts returns contacts with nested UserPublic
  - DELETE /api/contacts/{id} removes one-directionally
  - PUT /api/contacts/{id}/block toggles blocked flag
  - GET /api/auth/turn-credentials returns 4 URIs and verifiable HMAC-SHA1 credential
"""
import base64
import hashlib
import hmac
import itertools

import pytest
from httpx import AsyncClient

from app.config import settings

# ── phone counter shared across this module ────────────────────────────────────
_counter = itertools.count(8000)


def _next_phone() -> str:
    return f"+1555{next(_counter):07d}"


# ── test helpers ───────────────────────────────────────────────────────────────

async def _register(client: AsyncClient, phone: str, name: str = "User") -> str:
    """Register, verify OTP, return access token."""
    r = await client.post("/api/auth/register", json={
        "name": name, "phone": phone, "password": "secret99",
    })
    assert r.status_code == 200, r.text
    otp = r.json()["debug_otp"]

    r2 = await client.post("/api/auth/verify-otp", json={"phone": phone, "otp": otp})
    assert r2.status_code == 200, r2.text
    return r2.json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ── /api/users/me ─────────────────────────────────────────────────────────────

async def test_get_me_returns_profile(client: AsyncClient) -> None:
    phone = _next_phone()
    token = await _register(client, phone, name="Alice")

    r = await client.get("/api/users/me", headers=_auth(token))
    assert r.status_code == 200
    data = r.json()
    assert data["phone"] == phone
    assert data["name"] == "Alice"
    assert "fcm_token" not in data
    assert "password_hash" not in data
    assert "created_at" in data
    assert "is_active" in data


async def test_get_me_without_token_returns_401(client: AsyncClient) -> None:
    r = await client.get("/api/users/me")
    assert r.status_code == 401


async def test_update_profile_name(client: AsyncClient) -> None:
    phone = _next_phone()
    token = await _register(client, phone, name="OldName")

    r = await client.put("/api/users/me", json={"name": "NewName"}, headers=_auth(token))
    assert r.status_code == 200
    assert r.json()["name"] == "NewName"

    r2 = await client.get("/api/users/me", headers=_auth(token))
    assert r2.json()["name"] == "NewName"


async def test_get_user_by_id_no_sensitive_fields(client: AsyncClient) -> None:
    phone = _next_phone()
    token = await _register(client, phone)
    user_id = (await client.get("/api/users/me", headers=_auth(token))).json()["id"]

    r = await client.get(f"/api/users/{user_id}", headers=_auth(token))
    assert r.status_code == 200
    data = r.json()
    assert "fcm_token" not in data
    assert "password_hash" not in data
    assert "created_at" not in data   # UserPublic, not UserMe


async def test_get_unknown_user_returns_404(client: AsyncClient) -> None:
    phone = _next_phone()
    token = await _register(client, phone)
    fake_id = "00000000-0000-0000-0000-000000000000"
    r = await client.get(f"/api/users/{fake_id}", headers=_auth(token))
    assert r.status_code == 404


# ── /api/contacts ─────────────────────────────────────────────────────────────

async def test_add_contact_creates_reciprocal_rows(client: AsyncClient) -> None:
    phone_a, phone_b = _next_phone(), _next_phone()
    token_a = await _register(client, phone_a, "Alice")
    token_b = await _register(client, phone_b, "Bob")

    r = await client.post(
        "/api/contacts/",
        json={"phone": phone_b, "nickname": "Bro"},
        headers=_auth(token_a),
    )
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["contact_user"]["phone"] == phone_b
    assert data["nickname"] == "Bro"

    # Bob's contact list should also include Alice (reciprocal)
    r2 = await client.get("/api/contacts/", headers=_auth(token_b))
    assert r2.status_code == 200
    phones = [c["contact_user"]["phone"] for c in r2.json()]
    assert phone_a in phones


async def test_cannot_add_self(client: AsyncClient) -> None:
    phone = _next_phone()
    token = await _register(client, phone)

    r = await client.post(
        "/api/contacts/",
        json={"phone": phone},
        headers=_auth(token),
    )
    assert r.status_code == 422
    assert r.json()["code"] == "validation_failed"


async def test_cannot_add_unknown_phone(client: AsyncClient) -> None:
    phone = _next_phone()
    token = await _register(client, phone)

    r = await client.post(
        "/api/contacts/",
        json={"phone": "+19999999999"},
        headers=_auth(token),
    )
    assert r.status_code == 404


async def test_list_contacts_returns_nested_user(client: AsyncClient) -> None:
    phone_a, phone_b = _next_phone(), _next_phone()
    token_a = await _register(client, phone_a, "Alice")
    await _register(client, phone_b, "Bob")

    await client.post("/api/contacts/", json={"phone": phone_b}, headers=_auth(token_a))

    r = await client.get("/api/contacts/", headers=_auth(token_a))
    assert r.status_code == 200
    contacts = r.json()
    assert len(contacts) >= 1
    c = next(x for x in contacts if x["contact_user"]["phone"] == phone_b)
    assert "id" in c["contact_user"]
    assert "fcm_token" not in c["contact_user"]


async def test_remove_contact_is_one_directional(client: AsyncClient) -> None:
    phone_a, phone_b = _next_phone(), _next_phone()
    token_a = await _register(client, phone_a, "Alice")
    token_b = await _register(client, phone_b, "Bob")

    r = await client.post("/api/contacts/", json={"phone": phone_b}, headers=_auth(token_a))
    contact_id = r.json()["id"]

    # Alice removes Bob
    r2 = await client.delete(f"/api/contacts/{contact_id}", headers=_auth(token_a))
    assert r2.status_code == 204

    # Alice no longer sees Bob
    r3 = await client.get("/api/contacts/", headers=_auth(token_a))
    phones_a = [c["contact_user"]["phone"] for c in r3.json()]
    assert phone_b not in phones_a

    # Bob still sees Alice (one-directional removal)
    r4 = await client.get("/api/contacts/", headers=_auth(token_b))
    phones_b = [c["contact_user"]["phone"] for c in r4.json()]
    assert phone_a in phones_b


async def test_block_contact(client: AsyncClient) -> None:
    phone_a, phone_b = _next_phone(), _next_phone()
    token_a = await _register(client, phone_a)
    await _register(client, phone_b)

    r = await client.post("/api/contacts/", json={"phone": phone_b}, headers=_auth(token_a))
    contact_id = r.json()["id"]
    assert r.json()["is_blocked"] is False

    r2 = await client.put(
        f"/api/contacts/{contact_id}/block",
        json={"blocked": True},
        headers=_auth(token_a),
    )
    assert r2.status_code == 200
    assert r2.json()["is_blocked"] is True


# ── /api/auth/turn-credentials ────────────────────────────────────────────────

async def test_turn_credentials_format_and_hmac(client: AsyncClient) -> None:
    phone = _next_phone()
    token = await _register(client, phone)

    r = await client.get("/api/auth/turn-credentials", headers=_auth(token))
    assert r.status_code == 200, r.text
    data = r.json()

    # Shape checks
    assert len(data["uris"]) == 4
    assert data["ttl"] == 3600

    # Username format: "<timestamp>:<uuid>"
    username: str = data["username"]
    parts = username.split(":", 1)
    assert len(parts) == 2, f"Unexpected username format: {username}"
    timestamp_str, user_id_str = parts
    assert timestamp_str.isdigit(), "timestamp must be numeric"
    assert len(user_id_str) == 36, "user_id must be a UUID string"

    # URI prefixes
    uris = data["uris"]
    assert any(u.startswith("stun:") for u in uris)
    assert any(u.startswith("turn:") for u in uris)
    assert any(u.startswith("turns:") for u in uris)

    # Credential HMAC-SHA1 verification
    expected_credential = base64.b64encode(
        hmac.new(
            settings.TURN_SECRET.encode("utf-8"),
            username.encode("utf-8"),
            hashlib.sha1,
        ).digest()
    ).decode("utf-8")
    assert data["credential"] == expected_credential, "HMAC credential mismatch"


async def test_turn_credentials_require_auth(client: AsyncClient) -> None:
    r = await client.get("/api/auth/turn-credentials")
    assert r.status_code == 401  # auto_error=False + UnauthorizedError → 401

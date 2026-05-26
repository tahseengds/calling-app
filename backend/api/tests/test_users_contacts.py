"""
Tests for /api/users, /api/contacts, and /api/auth/turn-credentials.

Covers:
  - GET /api/users/me returns profile; without token → 401
  - PUT /api/users/me updates name
  - GET /api/users/{user_id} returns UserPublic (no fcm_token / password_hash)
  - POST /api/contacts adds contact and creates reciprocal row
  - Cannot add self
  - Cannot add unknown email
  - GET /api/contacts returns contacts with nested UserPublic
  - DELETE /api/contacts/{id} removes one-directionally
  - PUT /api/contacts/{id}/block toggles blocked flag
  - GET /api/calls/turn-credentials returns 4 URIs and verifiable HMAC-SHA1 credential
"""
import base64
import hashlib
import hmac
import itertools

import pytest
from httpx import AsyncClient

from app.config import settings
from app.services import auth_service

# ── email counter shared across this module ──────────────────────────────────
_counter = itertools.count(8000)


def _next_email() -> str:
    return f"users{next(_counter)}@example.com"


# ── test helpers ───────────────────────────────────────────────────────────────


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
    """Stub Firebase verifier and sign in. Returns access token."""
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


# ── /api/users/me ─────────────────────────────────────────────────────────────

async def test_get_me_returns_profile(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email, name="Alice")

    r = await client.get("/api/users/me", headers=_auth(token))
    assert r.status_code == 200
    data = r.json()
    assert data["email"] == email
    assert data["name"] == "Alice"
    assert "fcm_token" not in data
    assert "password_hash" not in data
    assert "created_at" in data
    assert "is_active" in data


async def test_get_me_without_token_returns_401(client: AsyncClient) -> None:
    r = await client.get("/api/users/me")
    assert r.status_code == 401


async def test_update_profile_name(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email, name="OldName")

    r = await client.put("/api/users/me", json={"name": "NewName"}, headers=_auth(token))
    assert r.status_code == 200
    assert r.json()["name"] == "NewName"

    r2 = await client.get("/api/users/me", headers=_auth(token))
    assert r2.json()["name"] == "NewName"


async def test_get_user_by_id_no_sensitive_fields(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)
    user_id = (await client.get("/api/users/me", headers=_auth(token))).json()["id"]

    r = await client.get(f"/api/users/{user_id}", headers=_auth(token))
    assert r.status_code == 200
    data = r.json()
    assert "fcm_token" not in data
    assert "password_hash" not in data
    assert "created_at" not in data   # UserPublic, not UserMe


async def test_get_unknown_user_returns_404(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)
    fake_id = "00000000-0000-0000-0000-000000000000"
    r = await client.get(f"/api/users/{fake_id}", headers=_auth(token))
    assert r.status_code == 404


# ── /api/contacts ─────────────────────────────────────────────────────────────

async def test_add_contact_creates_reciprocal_rows(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email_a, email_b = _next_email(), _next_email()
    token_a = await _signin(client, monkeypatch, email_a, "Alice")
    token_b = await _signin(client, monkeypatch, email_b, "Bob")

    r = await client.post(
        "/api/contacts/",
        json={"email": email_b, "nickname": "Bro"},
        headers=_auth(token_a),
    )
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["contact_user"]["email"] == email_b
    assert data["nickname"] == "Bro"

    # Bob's contact list should also include Alice (reciprocal)
    r2 = await client.get("/api/contacts/", headers=_auth(token_b))
    assert r2.status_code == 200
    emails = [c["contact_user"]["email"] for c in r2.json()]
    assert email_a in emails


async def test_cannot_add_self(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    r = await client.post(
        "/api/contacts/",
        json={"email": email},
        headers=_auth(token),
    )
    assert r.status_code == 422
    assert r.json()["code"] == "validation_failed"


async def test_cannot_add_unknown_email(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    r = await client.post(
        "/api/contacts/",
        json={"email": "nobody@example.com"},
        headers=_auth(token),
    )
    assert r.status_code == 404


async def test_list_contacts_returns_nested_user(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email_a, email_b = _next_email(), _next_email()
    token_a = await _signin(client, monkeypatch, email_a, "Alice")
    await _signin(client, monkeypatch, email_b, "Bob")

    await client.post("/api/contacts/", json={"email": email_b}, headers=_auth(token_a))

    r = await client.get("/api/contacts/", headers=_auth(token_a))
    assert r.status_code == 200
    contacts = r.json()
    assert len(contacts) >= 1
    c = next(x for x in contacts if x["contact_user"]["email"] == email_b)
    assert "id" in c["contact_user"]
    assert "fcm_token" not in c["contact_user"]


async def test_remove_contact_is_one_directional(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email_a, email_b = _next_email(), _next_email()
    token_a = await _signin(client, monkeypatch, email_a, "Alice")
    token_b = await _signin(client, monkeypatch, email_b, "Bob")

    r = await client.post("/api/contacts/", json={"email": email_b}, headers=_auth(token_a))
    contact_id = r.json()["id"]

    # Alice removes Bob
    r2 = await client.delete(f"/api/contacts/{contact_id}", headers=_auth(token_a))
    assert r2.status_code == 204

    # Alice no longer sees Bob
    r3 = await client.get("/api/contacts/", headers=_auth(token_a))
    emails_a = [c["contact_user"]["email"] for c in r3.json()]
    assert email_b not in emails_a

    # Bob still sees Alice (one-directional removal)
    r4 = await client.get("/api/contacts/", headers=_auth(token_b))
    emails_b = [c["contact_user"]["email"] for c in r4.json()]
    assert email_a in emails_b


async def test_block_contact(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email_a, email_b = _next_email(), _next_email()
    token_a = await _signin(client, monkeypatch, email_a)
    await _signin(client, monkeypatch, email_b)

    r = await client.post("/api/contacts/", json={"email": email_b}, headers=_auth(token_a))
    contact_id = r.json()["id"]
    assert r.json()["is_blocked"] is False

    r2 = await client.put(
        f"/api/contacts/{contact_id}/block",
        json={"blocked": True},
        headers=_auth(token_a),
    )
    assert r2.status_code == 200
    assert r2.json()["is_blocked"] is True


# ── /api/calls/turn-credentials ───────────────────────────────────────────────

async def test_turn_credentials_format_and_hmac(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    email = _next_email()
    token = await _signin(client, monkeypatch, email)

    r = await client.get("/api/calls/turn-credentials", headers=_auth(token))
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
    r = await client.get("/api/calls/turn-credentials")
    assert r.status_code == 401  # auto_error=False + UnauthorizedError → 401

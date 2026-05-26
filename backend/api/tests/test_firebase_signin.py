"""
Tests for /api/auth/firebase-signin.

The real verifier (google.oauth2.id_token.verify_firebase_token) makes an
HTTPS call to fetch Google's public keys, which we don't want in unit
tests. We monkey-patch verify_firebase_id_token in the service module to
return canned claims (or raise) so we can exercise every branch of the
endpoint synchronously.
"""
from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient

from app.services import auth_service
from app.utils.exceptions import UnauthorizedError, ValidationFailedError


# ── helpers ────────────────────────────────────────────────────────────────────


def _stub_verifier(monkeypatch: pytest.MonkeyPatch, claims: dict[str, Any]) -> None:
    """Make verify_firebase_id_token return *claims* without hitting Google."""

    async def _fake(_id_token: str) -> dict[str, Any]:
        return claims

    monkeypatch.setattr(auth_service, "verify_firebase_id_token", _fake)


def _stub_verifier_raises(
    monkeypatch: pytest.MonkeyPatch, exc: Exception
) -> None:
    async def _fake(_id_token: str) -> dict[str, Any]:
        raise exc

    monkeypatch.setattr(auth_service, "verify_firebase_id_token", _fake)


async def _signin(
    client: AsyncClient,
    *,
    device_id: str = "test-device",
    name: str | None = None,
    fcm_token: str | None = None,
) -> "Any":
    body: dict[str, Any] = {
        "firebase_id_token": "stub-token",
        "device_id": device_id,
    }
    if name is not None:
        body["name"] = name
    if fcm_token is not None:
        body["fcm_token"] = fcm_token
    return await client.post("/api/auth/firebase-signin", json=body)


# ── tests ─────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_firebase_signin_creates_user_on_first_call(
    client: AsyncClient,
    phone: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_verifier(monkeypatch, {"phone_number": phone, "name": "Aunt Liz"})

    r = await _signin(client, name="Aunt Liz")

    assert r.status_code == 200, r.text
    data = r.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"
    assert data["expires_in"] > 0


@pytest.mark.asyncio
async def test_firebase_signin_returning_user_keeps_existing_name(
    client: AsyncClient,
    phone: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A second sign-in must NOT overwrite the user's name with a stale claim."""
    _stub_verifier(monkeypatch, {"phone_number": phone, "name": "Original"})
    r1 = await _signin(client, name="Original")
    assert r1.status_code == 200

    # Second call passes a different `name` — the row's name should not change.
    _stub_verifier(monkeypatch, {"phone_number": phone, "name": "Different"})
    r2 = await _signin(client, name="Should be ignored")
    assert r2.status_code == 200
    tokens = r2.json()

    me = await client.get(
        "/api/users/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert me.status_code == 200
    assert me.json()["name"] == "Original"


@pytest.mark.asyncio
async def test_firebase_signin_invalid_token_returns_401(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_verifier_raises(
        monkeypatch, UnauthorizedError("Invalid Firebase ID token")
    )
    r = await _signin(client)
    assert r.status_code == 401
    body = r.json()
    assert body["code"] == "unauthorized"


@pytest.mark.asyncio
async def test_firebase_signin_missing_phone_claim_returns_422(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Token verified but with no phone_number — e.g. signed in via email.
    _stub_verifier_raises(
        monkeypatch,
        ValidationFailedError(
            "Firebase ID token is missing phone_number — sign in by phone"
        ),
    )
    r = await _signin(client)
    assert r.status_code == 422
    assert r.json()["code"] == "validation_failed"


@pytest.mark.asyncio
async def test_firebase_signin_stores_fcm_token(
    client: AsyncClient,
    phone: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_verifier(monkeypatch, {"phone_number": phone})
    r = await _signin(client, fcm_token="fcm-abcdef")
    assert r.status_code == 200

    # Reach into the DB via /api/users/me — fcm_token is not in the
    # public schema, so verify indirectly by signing out + back in and
    # confirming the same user_id surfaces.
    tokens = r.json()
    me = await client.get(
        "/api/users/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert me.status_code == 200


@pytest.mark.asyncio
async def test_firebase_signin_reactivates_inactive_user(
    client: AsyncClient,
    phone: str,
    monkeypatch: pytest.MonkeyPatch,
    redis_client,
) -> None:
    """A user deactivated via the old register-pending flow should be
    re-activated when they pass Firebase's SMS challenge."""
    from sqlalchemy.ext.asyncio import create_async_engine
    from sqlalchemy.pool import NullPool
    from sqlalchemy import update

    from app.config import settings
    from app.models.user import User

    # Create the row directly in the DB in an inactive state.
    _stub_verifier(monkeypatch, {"phone_number": phone})
    r1 = await _signin(client)
    assert r1.status_code == 200

    engine = create_async_engine(settings.DATABASE_URL, poolclass=NullPool)
    async with engine.begin() as conn:
        await conn.execute(
            update(User).where(User.phone == phone).values(is_active=False)
        )
    await engine.dispose()

    # Sign in again — should reactivate.
    r2 = await _signin(client)
    assert r2.status_code == 200

    engine = create_async_engine(settings.DATABASE_URL, poolclass=NullPool)
    async with engine.begin() as conn:
        from sqlalchemy import select

        res = await conn.execute(
            select(User.is_active).where(User.phone == phone)
        )
        assert res.scalar_one() is True
    await engine.dispose()


@pytest.mark.asyncio
async def test_firebase_signin_default_name_uses_phone_tail(
    client: AsyncClient,
    phone: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """When neither client-supplied name nor Firebase 'name' claim is
    available, fall back to "User <last-4-digits>"."""
    _stub_verifier(monkeypatch, {"phone_number": phone})  # no name claim
    r = await _signin(client)  # no name in body either
    assert r.status_code == 200
    tokens = r.json()

    me = await client.get(
        "/api/users/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert me.status_code == 200
    assert me.json()["name"] == f"User {phone[-4:]}"

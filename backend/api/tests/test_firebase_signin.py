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


def _claims_for(email: str, name: str | None = None) -> dict[str, Any]:
    """Standard email/password Firebase claims."""
    out: dict[str, Any] = {
        "sub": f"fb-{email}",
        "email": email,
        "email_verified": True,
        "firebase": {"sign_in_provider": "password"},
    }
    if name is not None:
        out["name"] = name
    return out


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
    email: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_verifier(monkeypatch, _claims_for(email, name="Aunt Liz"))

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
    email: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A second sign-in must NOT overwrite the user's name with a stale claim."""
    _stub_verifier(monkeypatch, _claims_for(email, name="Original"))
    r1 = await _signin(client, name="Original")
    assert r1.status_code == 200

    # Second call passes a different `name` — the row's name should not change.
    _stub_verifier(monkeypatch, _claims_for(email, name="Different"))
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
async def test_firebase_signin_missing_uid_returns_422(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A verified token with no `sub`/`user_id` claim is malformed → 422."""
    _stub_verifier(monkeypatch, {"email": "x@example.com"})
    r = await _signin(client)
    assert r.status_code == 422
    assert r.json()["code"] == "validation_failed"


@pytest.mark.asyncio
async def test_firebase_signin_stores_fcm_token(
    client: AsyncClient,
    email: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_verifier(monkeypatch, _claims_for(email))
    r = await _signin(client, fcm_token="fcm-abcdef")
    assert r.status_code == 200

    tokens = r.json()
    me = await client.get(
        "/api/users/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert me.status_code == 200


@pytest.mark.asyncio
async def test_firebase_signin_reactivates_inactive_user(
    client: AsyncClient,
    email: str,
    monkeypatch: pytest.MonkeyPatch,
    redis_client,
) -> None:
    """A deactivated user should be re-activated on next Firebase sign-in."""
    from sqlalchemy.ext.asyncio import create_async_engine
    from sqlalchemy.pool import NullPool
    from sqlalchemy import select, update

    from app.config import settings
    from app.models.user import User

    _stub_verifier(monkeypatch, _claims_for(email))
    r1 = await _signin(client)
    assert r1.status_code == 200

    engine = create_async_engine(settings.DATABASE_URL, poolclass=NullPool)
    async with engine.begin() as conn:
        await conn.execute(
            update(User).where(User.email == email).values(is_active=False)
        )
    await engine.dispose()

    # Sign in again — should reactivate.
    r2 = await _signin(client)
    assert r2.status_code == 200

    engine = create_async_engine(settings.DATABASE_URL, poolclass=NullPool)
    async with engine.begin() as conn:
        res = await conn.execute(
            select(User.is_active).where(User.email == email)
        )
        assert res.scalar_one() is True
    await engine.dispose()


@pytest.mark.asyncio
async def test_firebase_signin_default_name_falls_back_to_email_local(
    client: AsyncClient,
    email: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """When neither client-supplied name nor Firebase 'name' claim is
    available, fall back to the email local-part."""
    claims = _claims_for(email)
    claims.pop("name", None)
    _stub_verifier(monkeypatch, claims)
    r = await _signin(client)  # no name in body either
    assert r.status_code == 200
    tokens = r.json()

    me = await client.get(
        "/api/users/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert me.status_code == 200
    expected_local = email.split("@")[0]
    assert me.json()["name"] == expected_local

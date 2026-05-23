"""
Auth smoke tests.

Covers:
  - register → verify-otp → tokens (happy path)
  - wrong OTP returns 422
  - expired / deleted OTP returns 422
  - login wrong password returns 401
  - refresh rotation issues a new pair and invalidates the old
  - refresh-token reuse triggers full revocation (all tokens 401)
  - logout blacklists the access token (protected route returns 401)
"""
import pytest
import redis.asyncio as aioredis
from httpx import AsyncClient


# ── helpers ────────────────────────────────────────────────────────────────────

async def _register_and_verify(client: AsyncClient, phone: str, password: str = "secret99") -> dict:
    """Full register → OTP → token flow. Returns TokenResponse JSON."""
    r = await client.post("/api/auth/register", json={
        "name": "Test User", "phone": phone, "password": password,
    })
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["otp_sent"] is True
    otp = data["debug_otp"]
    assert otp is not None, "DEBUG mode must be on for tests"

    r2 = await client.post("/api/auth/verify-otp", json={"phone": phone, "otp": otp})
    assert r2.status_code == 200, r2.text
    tokens = r2.json()
    assert "access_token" in tokens
    assert "refresh_token" in tokens
    return tokens


# ── tests ──────────────────────────────────────────────────────────────────────

async def test_register_verify_otp_happy_path(client: AsyncClient, phone: str) -> None:
    tokens = await _register_and_verify(client, phone)
    assert tokens["token_type"] == "bearer"
    assert tokens["expires_in"] > 0


async def test_wrong_otp_returns_422(client: AsyncClient, phone: str) -> None:
    r = await client.post("/api/auth/register", json={
        "name": "T", "phone": phone, "password": "secret99",
    })
    assert r.status_code == 200

    r2 = await client.post("/api/auth/verify-otp", json={"phone": phone, "otp": "000000"})
    assert r2.status_code == 422
    assert r2.json()["code"] == "validation_failed"


async def test_expired_otp_returns_422(
    client: AsyncClient, phone: str, redis_client: aioredis.Redis
) -> None:
    r = await client.post("/api/auth/register", json={
        "name": "T", "phone": phone, "password": "secret99",
    })
    assert r.status_code == 200

    # Simulate expiry by deleting the OTP key directly
    await redis_client.delete(f"otp:{phone}")

    r2 = await client.post("/api/auth/verify-otp", json={"phone": phone, "otp": "123456"})
    assert r2.status_code == 422
    assert "expired" in r2.json()["detail"].lower()


async def test_login_wrong_password(client: AsyncClient, phone: str) -> None:
    await _register_and_verify(client, phone)

    r = await client.post("/api/auth/login", json={
        "phone": phone, "password": "wrongpassword", "device_id": "dev1",
    })
    assert r.status_code == 401
    assert r.json()["code"] == "unauthorized"


async def test_login_happy_path(client: AsyncClient, phone: str) -> None:
    await _register_and_verify(client, phone, password="mypassword1")

    r = await client.post("/api/auth/login", json={
        "phone": phone, "password": "mypassword1", "device_id": "dev-android",
    })
    assert r.status_code == 200
    data = r.json()
    assert "access_token" in data


async def test_refresh_rotation(client: AsyncClient, phone: str) -> None:
    tokens = await _register_and_verify(client, phone)
    old_refresh = tokens["refresh_token"]

    r = await client.post("/api/auth/refresh", json={
        "refresh_token": old_refresh, "device_id": "default",
    })
    assert r.status_code == 200, r.text
    new_tokens = r.json()
    assert new_tokens["refresh_token"] != old_refresh
    assert new_tokens["access_token"] != tokens["access_token"]


async def test_refresh_reuse_revokes_all_sessions(client: AsyncClient, phone: str) -> None:
    tokens = await _register_and_verify(client, phone)
    old_refresh = tokens["refresh_token"]

    # First use — valid rotation
    r1 = await client.post("/api/auth/refresh", json={
        "refresh_token": old_refresh, "device_id": "default",
    })
    assert r1.status_code == 200

    # Second use of the *same* (now revoked) token — reuse detected
    r2 = await client.post("/api/auth/refresh", json={
        "refresh_token": old_refresh, "device_id": "default",
    })
    assert r2.status_code == 401
    assert "reuse" in r2.json()["detail"].lower()

    # The new token issued in r1 must also be revoked now
    new_refresh = r1.json()["refresh_token"]
    r3 = await client.post("/api/auth/refresh", json={
        "refresh_token": new_refresh, "device_id": "default",
    })
    assert r3.status_code == 401


async def test_logout_blacklists_access_token(client: AsyncClient, phone: str) -> None:
    tokens = await _register_and_verify(client, phone)
    access = tokens["access_token"]
    refresh = tokens["refresh_token"]

    # Logout
    r = await client.post(
        "/api/auth/logout",
        json={"refresh_token": refresh},
        headers={"Authorization": f"Bearer {access}"},
    )
    assert r.status_code == 204

    # The access token must now be rejected on a protected route.
    # /api/auth/logout itself requires auth — reuse it as the canary.
    r2 = await client.post(
        "/api/auth/logout",
        json={"refresh_token": refresh},
        headers={"Authorization": f"Bearer {access}"},
    )
    assert r2.status_code == 401


async def test_duplicate_phone_registration_rejected(client: AsyncClient, phone: str) -> None:
    await _register_and_verify(client, phone)

    # Re-registering the same active phone must fail with 409
    r = await client.post("/api/auth/register", json={
        "name": "Duplicate", "phone": phone, "password": "secret99",
    })
    assert r.status_code == 409
    assert r.json()["code"] == "conflict"


async def test_invalid_phone_format_rejected(client: AsyncClient) -> None:
    r = await client.post("/api/auth/register", json={
        "name": "Bad", "phone": "not-a-phone", "password": "secret99",
    })
    assert r.status_code == 422


async def test_short_password_rejected(client: AsyncClient, phone: str) -> None:
    r = await client.post("/api/auth/register", json={
        "name": "T", "phone": phone, "password": "short",
    })
    assert r.status_code == 422

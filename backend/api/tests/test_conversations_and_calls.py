"""
Tests for POST /api/conversations/ (get-or-create) and GET /api/calls/history.

Auth uses /api/auth/firebase-signin with the Firebase verifier stubbed —
that's the production auth path.

Covers:
  - POST /api/conversations/ creates a conversation when none exists
  - Re-posting with the same user_id is idempotent — same id returned
  - Either side can open the same conversation (canonical row)
  - Cannot open a conversation with yourself (422)
  - Cannot open a conversation with a non-contact (403)
  - Cannot open a conversation with a user who has blocked you (403)
  - Cannot open a conversation with a contact you have blocked (403)
  - GET /api/calls/history returns rows from the user's perspective,
    newest first, with direction computed against caller_id
  - History pagination via next_cursor returns the next page
  - History excludes calls the user did not participate in
"""
import itertools
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.config import settings
from app.models.call_record import CallRecord
from app.services import auth_service


# ── Email generator ───────────────────────────────────────────────────────────

_email_counter = itertools.count(20_000)


def _next_email() -> str:
    return f"conv{next(_email_counter)}@example.com"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ── Auth helper — stubs the Firebase verifier and signs in ────────────────────


def _stub_firebase(monkeypatch: pytest.MonkeyPatch, claims: dict) -> None:
    async def _fake(_id_token: str) -> dict:
        return claims

    monkeypatch.setattr(auth_service, "verify_firebase_id_token", _fake)


async def _signin(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
    *,
    email: str,
    name: str,
    device_id: str,
) -> tuple[str, str]:
    """Sign in via firebase-signin with a stubbed verifier; returns (token, user_id)."""
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
        json={
            "firebase_id_token": "stub",
            "device_id": device_id,
            "name": name,
        },
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    me = await client.get("/api/users/me", headers=_auth(token))
    assert me.status_code == 200, me.text
    return token, me.json()["id"]


async def _add_contact(client: AsyncClient, token: str, other_email: str) -> str:
    """Adds *other_email* to *token*'s contact list. Returns the contact row id."""
    r = await client.post(
        "/api/contacts/", json={"email": other_email}, headers=_auth(token)
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


async def _setup_pair(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, str, str, str, str, str]:
    """
    Sign Alice + Bob in via stubbed Firebase, make them reciprocal contacts.

    Returns (alice_token, bob_token, alice_id, bob_id, alice_email, bob_email).
    """
    alice_email, bob_email = _next_email(), _next_email()
    alice_token, alice_id = await _signin(
        client, monkeypatch,
        email=alice_email, name="Alice", device_id="alice-dev",
    )
    bob_token, bob_id = await _signin(
        client, monkeypatch,
        email=bob_email, name="Bob", device_id="bob-dev",
    )
    await _add_contact(client, alice_token, bob_email)
    await _add_contact(client, bob_token, alice_email)
    return alice_token, bob_token, alice_id, bob_id, alice_email, bob_email


# ── POST /api/conversations/ ──────────────────────────────────────────────────


async def test_open_conversation_creates_row(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, _, _, bob_id, _, _ = await _setup_pair(client, monkeypatch)
    r = await client.post(
        "/api/conversations/",
        json={"user_id": bob_id},
        headers=_auth(alice_token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["other_user"]["id"] == bob_id
    assert body["unread_count"] == 0
    assert body["last_message"] is None
    assert uuid.UUID(body["id"])  # valid UUID


async def test_open_conversation_is_idempotent(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, _, _, bob_id, _, _ = await _setup_pair(client, monkeypatch)
    r1 = await client.post(
        "/api/conversations/",
        json={"user_id": bob_id},
        headers=_auth(alice_token),
    )
    r2 = await client.post(
        "/api/conversations/",
        json={"user_id": bob_id},
        headers=_auth(alice_token),
    )
    assert r1.status_code == r2.status_code == 200
    assert r1.json()["id"] == r2.json()["id"]


async def test_open_conversation_from_either_side_returns_same_id(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, bob_token, alice_id, bob_id, _, _ = await _setup_pair(
        client, monkeypatch
    )
    r_a = await client.post(
        "/api/conversations/",
        json={"user_id": bob_id},
        headers=_auth(alice_token),
    )
    r_b = await client.post(
        "/api/conversations/",
        json={"user_id": alice_id},
        headers=_auth(bob_token),
    )
    assert r_a.status_code == r_b.status_code == 200, (r_a.text, r_b.text)
    assert r_a.json()["id"] == r_b.json()["id"]


async def test_open_conversation_with_self_fails(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, _, alice_id, _, _, _ = await _setup_pair(client, monkeypatch)
    r = await client.post(
        "/api/conversations/",
        json={"user_id": alice_id},
        headers=_auth(alice_token),
    )
    assert r.status_code == 422, r.text


async def test_open_conversation_with_non_contact_forbidden(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, _ = await _signin(
        client, monkeypatch,
        email=_next_email(), name="Alice", device_id="alice-dev",
    )
    _, stranger_id = await _signin(
        client, monkeypatch,
        email=_next_email(), name="Stranger", device_id="stranger-dev",
    )
    r = await client.post(
        "/api/conversations/",
        json={"user_id": stranger_id},
        headers=_auth(alice_token),
    )
    assert r.status_code == 403, r.text


async def test_open_conversation_when_blocked_by_other_forbidden(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, bob_token, alice_id, bob_id, _, _ = await _setup_pair(
        client, monkeypatch
    )

    # Bob blocks Alice via the contact row in Bob's list
    contacts = await client.get("/api/contacts/", headers=_auth(bob_token))
    alice_contact_id = next(
        c["id"]
        for c in contacts.json()
        if c["contact_user"]["id"] == alice_id
    )
    r = await client.put(
        f"/api/contacts/{alice_contact_id}/block",
        json={"blocked": True},
        headers=_auth(bob_token),
    )
    assert r.status_code == 200, r.text

    r = await client.post(
        "/api/conversations/",
        json={"user_id": bob_id},
        headers=_auth(alice_token),
    )
    assert r.status_code == 403, r.text


async def test_open_conversation_when_caller_blocked_other_forbidden(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, _, _, bob_id, _, _ = await _setup_pair(client, monkeypatch)

    contacts = await client.get("/api/contacts/", headers=_auth(alice_token))
    bob_contact_id = next(
        c["id"] for c in contacts.json() if c["contact_user"]["id"] == bob_id
    )
    await client.put(
        f"/api/contacts/{bob_contact_id}/block",
        json={"blocked": True},
        headers=_auth(alice_token),
    )

    r = await client.post(
        "/api/conversations/",
        json={"user_id": bob_id},
        headers=_auth(alice_token),
    )
    assert r.status_code == 403, r.text


async def test_open_conversation_requires_auth(client: AsyncClient) -> None:
    r = await client.post(
        "/api/conversations/",
        json={"user_id": str(uuid.uuid4())},
    )
    assert r.status_code == 401


# ── GET /api/calls/history ────────────────────────────────────────────────────


async def _insert_call(
    *,
    caller_id: str,
    callee_id: str,
    call_type: str = "audio",
    status: str = "completed",
    started_at: datetime | None = None,
    duration_seconds: int | None = 42,
) -> uuid.UUID:
    """Insert a CallRecord directly via a NullPool engine."""
    engine = create_async_engine(settings.DATABASE_URL, poolclass=NullPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    cid = uuid.uuid4()
    async with session_factory() as s:
        rec = CallRecord(
            id=cid,
            caller_id=uuid.UUID(caller_id),
            callee_id=uuid.UUID(callee_id),
            call_type=call_type,
            status=status,
            started_at=started_at or datetime.now(timezone.utc),
            duration_seconds=duration_seconds,
        )
        s.add(rec)
        await s.commit()
    await engine.dispose()
    return cid


async def test_call_history_empty(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, _ = await _signin(
        client, monkeypatch,
        email=_next_email(), name="Alice", device_id="alice-dev",
    )
    r = await client.get("/api/calls/history", headers=_auth(alice_token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["items"] == []
    assert body["next_cursor"] is None


async def test_call_history_direction_and_other_user(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, _, alice_id, bob_id, _, _ = await _setup_pair(
        client, monkeypatch
    )

    # Alice → Bob (outgoing from Alice's view)
    await _insert_call(caller_id=alice_id, callee_id=bob_id)
    # Bob → Alice (incoming from Alice's view)
    await _insert_call(caller_id=bob_id, callee_id=alice_id, call_type="video")

    r = await client.get("/api/calls/history", headers=_auth(alice_token))
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    assert len(items) == 2
    by_dir = {it["direction"]: it for it in items}
    assert "outgoing" in by_dir and "incoming" in by_dir
    assert by_dir["outgoing"]["other_user"]["id"] == bob_id
    assert by_dir["incoming"]["other_user"]["id"] == bob_id
    assert by_dir["incoming"]["call_type"] == "video"


async def test_call_history_pagination(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, _, alice_id, bob_id, _, _ = await _setup_pair(
        client, monkeypatch
    )

    base = datetime.now(timezone.utc) - timedelta(hours=5)
    for i in range(5):
        await _insert_call(
            caller_id=alice_id,
            callee_id=bob_id,
            started_at=base + timedelta(minutes=i),
        )

    r1 = await client.get(
        "/api/calls/history?limit=2", headers=_auth(alice_token)
    )
    assert r1.status_code == 200, r1.text
    body1 = r1.json()
    assert len(body1["items"]) == 2
    assert body1["next_cursor"] is not None

    r2 = await client.get(
        f"/api/calls/history?limit=2&cursor={body1['next_cursor']}",
        headers=_auth(alice_token),
    )
    assert r2.status_code == 200, r2.text
    body2 = r2.json()
    assert len(body2["items"]) == 2
    page1_ids = {it["id"] for it in body1["items"]}
    page2_ids = {it["id"] for it in body2["items"]}
    assert page1_ids.isdisjoint(page2_ids)


async def test_call_history_excludes_other_users(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    alice_token, _, alice_id, bob_id, _, _ = await _setup_pair(
        client, monkeypatch
    )
    _, charlie_id = await _signin(
        client, monkeypatch,
        email=_next_email(), name="Charlie", device_id="charlie-dev",
    )

    # Call between Charlie and Bob — Alice must not see it
    await _insert_call(caller_id=charlie_id, callee_id=bob_id)
    # Call involving Alice
    await _insert_call(caller_id=alice_id, callee_id=bob_id)

    r = await client.get("/api/calls/history", headers=_auth(alice_token))
    items = r.json()["items"]
    assert len(items) == 1
    assert items[0]["other_user"]["id"] == bob_id


async def test_call_history_requires_auth(client: AsyncClient) -> None:
    r = await client.get("/api/calls/history")
    assert r.status_code == 401

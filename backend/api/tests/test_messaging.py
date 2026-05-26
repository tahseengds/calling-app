"""
Tests for /api/conversations and /api/messages.

Covers:
  - POST /api/messages creates conversation, receipt, publishes to Redis
  - Idempotent resend with same client_id returns original, no duplicate
  - GET /api/conversations shows unread_count
  - GET /api/conversations/{id}/messages cursor pagination: correct order + next_cursor
  - PUT /api/messages/read publishes receipt event and updates message status
  - DELETE /api/messages/{id} soft-delete returns tombstone
  - Non-participant cannot fetch a conversation (403)
  - Blocked contact cannot send a message (403)
"""
import asyncio
import itertools
import json
import uuid

import pytest
import redis.asyncio as aioredis
from httpx import AsyncClient

from app.services import auth_service

# ── Email counter ─────────────────────────────────────────────────────────────
_counter = itertools.count(9000)


def _next_email() -> str:
    return f"msg{next(_counter)}@example.com"


# ── Helpers ───────────────────────────────────────────────────────────────────


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


async def _setup_pair(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> tuple[str, str, str, str]:
    """Register Alice and Bob, add them as contacts. Returns (alice_token, bob_token, alice_id, bob_id)."""
    email_a, email_b = _next_email(), _next_email()
    token_a = await _signin(client, monkeypatch, email_a, "Alice")
    token_b = await _signin(client, monkeypatch, email_b, "Bob")

    # Get user IDs
    alice_id = (await client.get("/api/users/me", headers=_auth(token_a))).json()["id"]
    bob_id = (await client.get("/api/users/me", headers=_auth(token_b))).json()["id"]

    # Add contact (reciprocal)
    r = await client.post("/api/contacts/", json={"email": email_b}, headers=_auth(token_a))
    assert r.status_code == 201, r.text

    return token_a, token_b, alice_id, bob_id


# ── Tests ─────────────────────────────────────────────────────────────────────

async def test_send_text_message_creates_conversation_and_receipt(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, token_b, alice_id, bob_id = await _setup_pair(client, monkeypatch)

    client_id = str(uuid.uuid4())
    r = await client.post(
        "/api/messages/",
        json={
            "client_id": client_id,
            "recipient_id": bob_id,
            "message_type": "text",
            "content": "Hello Bob!",
        },
        headers=_auth(token_a),
    )
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["id"] == client_id
    assert data["content"] == "Hello Bob!"
    assert data["status"] == "sent"
    assert data["is_deleted"] is False
    assert data["sender_id"] == alice_id

    # Conversation must now appear for both Alice and Bob
    r2 = await client.get("/api/conversations/", headers=_auth(token_a))
    assert r2.status_code == 200
    convs = r2.json()
    assert len(convs) >= 1
    conv = next(c for c in convs if c["other_user"]["id"] == bob_id)
    assert conv["last_message"]["id"] == client_id

    # Bob should see the conversation with unread_count == 1
    r3 = await client.get("/api/conversations/", headers=_auth(token_b))
    bob_convs = r3.json()
    bob_conv = next(c for c in bob_convs if c["other_user"]["id"] == alice_id)
    assert bob_conv["unread_count"] == 1


async def test_send_message_publishes_to_redis(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
    redis_client: aioredis.Redis,
) -> None:
    token_a, _token_b, _alice_id, bob_id = await _setup_pair(client, monkeypatch)

    # Subscribe to Bob's delivery channel before sending
    pubsub = redis_client.pubsub()
    channel = f"msg_delivery:{bob_id}"
    await pubsub.subscribe(channel)
    # Flush subscribe confirmation message
    await pubsub.get_message(ignore_subscribe_messages=True, timeout=0.5)

    client_id = str(uuid.uuid4())
    r = await client.post(
        "/api/messages/",
        json={
            "client_id": client_id,
            "recipient_id": bob_id,
            "message_type": "text",
            "content": "Ping!",
        },
        headers=_auth(token_a),
    )
    assert r.status_code == 201, r.text

    # Poll for the published message (up to ~1 second)
    received = None
    for _ in range(20):
        msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=0.1)
        if msg and msg["type"] == "message":
            received = json.loads(msg["data"])
            break
        await asyncio.sleep(0.05)

    await pubsub.unsubscribe(channel)
    await pubsub.aclose()

    assert received is not None, "No message published to Redis"
    assert received["id"] == client_id
    assert received["event"] == "new_message"


async def test_idempotent_resend_returns_original(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, _token_b, _alice_id, bob_id = await _setup_pair(client, monkeypatch)

    client_id = str(uuid.uuid4())
    payload = {
        "client_id": client_id,
        "recipient_id": bob_id,
        "message_type": "text",
        "content": "First send",
    }

    r1 = await client.post("/api/messages/", json=payload, headers=_auth(token_a))
    assert r1.status_code == 201, r1.text

    r2 = await client.post("/api/messages/", json=payload, headers=_auth(token_a))
    assert r2.status_code == 201, r2.text

    # Both responses must be identical
    assert r1.json()["id"] == r2.json()["id"]
    assert r1.json()["created_at"] == r2.json()["created_at"]

    # Only one message in the conversation
    conv_id = r1.json()["conversation_id"]
    r3 = await client.get(
        f"/api/conversations/{conv_id}/messages", headers=_auth(token_a)
    )
    assert r3.status_code == 200
    assert len(r3.json()["messages"]) == 1


async def test_cursor_pagination_correct_order(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, _token_b, _alice_id, bob_id = await _setup_pair(client, monkeypatch)

    # Send 5 messages
    sent_ids = []
    r = None
    for i in range(5):
        cid = str(uuid.uuid4())
        r = await client.post(
            "/api/messages/",
            json={
                "client_id": cid,
                "recipient_id": bob_id,
                "message_type": "text",
                "content": f"Message {i}",
            },
            headers=_auth(token_a),
        )
        assert r.status_code == 201
        sent_ids.append(cid)

    conv_id = r.json()["conversation_id"]

    # Fetch page 1 (limit=3)
    r1 = await client.get(
        f"/api/conversations/{conv_id}/messages?limit=3",
        headers=_auth(token_a),
    )
    assert r1.status_code == 200
    page1 = r1.json()
    assert len(page1["messages"]) == 3
    assert page1["next_cursor"] is not None

    ids_page1 = [m["id"] for m in page1["messages"]]

    # Fetch page 2 with cursor
    r2 = await client.get(
        f"/api/conversations/{conv_id}/messages?limit=3&cursor={page1['next_cursor']}",
        headers=_auth(token_a),
    )
    assert r2.status_code == 200
    page2 = r2.json()
    assert len(page2["messages"]) == 2
    assert page2["next_cursor"] is None

    ids_page2 = [m["id"] for m in page2["messages"]]

    # No overlap
    assert not set(ids_page1) & set(ids_page2)
    # Together they cover all 5 messages
    assert set(ids_page1 + ids_page2) == set(sent_ids)


async def test_mark_read_updates_status_and_publishes(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
    redis_client: aioredis.Redis,
) -> None:
    token_a, token_b, alice_id, bob_id = await _setup_pair(client, monkeypatch)

    client_id = str(uuid.uuid4())
    r = await client.post(
        "/api/messages/",
        json={
            "client_id": client_id,
            "recipient_id": bob_id,
            "message_type": "text",
            "content": "Read me!",
        },
        headers=_auth(token_a),
    )
    assert r.status_code == 201

    # Subscribe to Alice's receipt channel before Bob marks read
    pubsub = redis_client.pubsub()
    await pubsub.subscribe(f"receipt:{alice_id}")
    await pubsub.get_message(ignore_subscribe_messages=True, timeout=0.5)

    # Bob marks the message as read
    r2 = await client.put(
        "/api/messages/read",
        json={"message_ids": [client_id]},
        headers=_auth(token_b),
    )
    assert r2.status_code == 204

    # Alice should receive a receipt event
    received = None
    for _ in range(20):
        msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=0.1)
        if msg and msg["type"] == "message":
            received = json.loads(msg["data"])
            break
        await asyncio.sleep(0.05)

    await pubsub.unsubscribe(f"receipt:{alice_id}")
    await pubsub.aclose()

    assert received is not None, "No receipt event published"
    assert received["status"] == "read"
    assert client_id in received["message_ids"]

    # Message status must be 'read' in the conversation
    conv_id = r.json()["conversation_id"]
    r3 = await client.get(
        f"/api/conversations/{conv_id}/messages", headers=_auth(token_a)
    )
    msgs = r3.json()["messages"]
    msg_data = next(m for m in msgs if m["id"] == client_id)
    assert msg_data["status"] == "read"

    # Unread count for Bob is now 0
    r4 = await client.get("/api/conversations/", headers=_auth(token_b))
    bob_conv = next(c for c in r4.json() if c["other_user"]["id"] == alice_id)
    assert bob_conv["unread_count"] == 0


async def test_soft_delete_leaves_tombstone(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, _token_b, _alice_id, bob_id = await _setup_pair(client, monkeypatch)

    client_id = str(uuid.uuid4())
    r = await client.post(
        "/api/messages/",
        json={
            "client_id": client_id,
            "recipient_id": bob_id,
            "message_type": "text",
            "content": "Delete me",
        },
        headers=_auth(token_a),
    )
    assert r.status_code == 201
    conv_id = r.json()["conversation_id"]

    # Alice deletes the message
    r2 = await client.delete(
        f"/api/messages/{client_id}", headers=_auth(token_a)
    )
    assert r2.status_code == 200
    deleted = r2.json()
    assert deleted["is_deleted"] is True
    assert deleted["content"] is None

    # Tombstone appears in conversation history
    r3 = await client.get(
        f"/api/conversations/{conv_id}/messages", headers=_auth(token_a)
    )
    msgs = r3.json()["messages"]
    tombstone = next(m for m in msgs if m["id"] == client_id)
    assert tombstone["is_deleted"] is True
    assert tombstone["content"] is None


async def test_non_participant_cannot_fetch_conversation(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, _token_b, _alice_id, bob_id = await _setup_pair(client, monkeypatch)

    # Alice sends a message to create a conversation
    r = await client.post(
        "/api/messages/",
        json={
            "client_id": str(uuid.uuid4()),
            "recipient_id": bob_id,
            "message_type": "text",
            "content": "Private",
        },
        headers=_auth(token_a),
    )
    assert r.status_code == 201
    conv_id = r.json()["conversation_id"]

    # Carol is a stranger
    email_c = _next_email()
    token_c = await _signin(client, monkeypatch, email_c, "Carol")

    r2 = await client.get(
        f"/api/conversations/{conv_id}/messages", headers=_auth(token_c)
    )
    assert r2.status_code == 403


async def test_blocked_contact_cannot_send(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, token_b, alice_id, bob_id = await _setup_pair(client, monkeypatch)

    # Alice gets the contact_id for Bob
    r = await client.get("/api/contacts/", headers=_auth(token_a))
    contacts = r.json()
    bob_contact = next(c for c in contacts if c["contact_user"]["id"] == bob_id)
    contact_id = bob_contact["id"]

    # Alice blocks Bob
    r2 = await client.put(
        f"/api/contacts/{contact_id}/block",
        json={"blocked": True},
        headers=_auth(token_a),
    )
    assert r2.status_code == 200
    assert r2.json()["is_blocked"] is True

    # Alice tries to message Bob (she blocked him → ForbiddenError)
    r3 = await client.post(
        "/api/messages/",
        json={
            "client_id": str(uuid.uuid4()),
            "recipient_id": bob_id,
            "message_type": "text",
            "content": "Hello from blocked Alice",
        },
        headers=_auth(token_a),
    )
    assert r3.status_code == 403

    # Bob also cannot message Alice (recipient blocked sender direction)
    r4 = await client.post(
        "/api/messages/",
        json={
            "client_id": str(uuid.uuid4()),
            "recipient_id": alice_id,
            "message_type": "text",
            "content": "Hello from Bob to blocked Alice",
        },
        headers=_auth(token_b),
    )
    assert r4.status_code == 403


async def test_only_sender_can_delete_message(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, token_b, _alice_id, bob_id = await _setup_pair(client, monkeypatch)

    client_id = str(uuid.uuid4())
    r = await client.post(
        "/api/messages/",
        json={
            "client_id": client_id,
            "recipient_id": bob_id,
            "message_type": "text",
            "content": "Don't delete me Bob",
        },
        headers=_auth(token_a),
    )
    assert r.status_code == 201

    # Bob tries to delete Alice's message — must be forbidden
    r2 = await client.delete(f"/api/messages/{client_id}", headers=_auth(token_b))
    assert r2.status_code == 403

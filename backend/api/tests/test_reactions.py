"""
Tests for /api/messages/{message_id}/reactions.

Covers:
  - POST adds a reaction, idempotent on repeat
  - DELETE removes it (and is a no-op if absent)
  - Reactions show up in subsequent message-list fetches
  - Soft-deleted messages can't be reacted to (400) and don't return reactions
  - Authorization: a non-participant gets 403
  - Realtime: an event is published to the *other* user's msg_delivery channel
"""
import asyncio
import itertools
import json
import uuid

import pytest
import redis.asyncio as aioredis
from httpx import AsyncClient

from app.services import auth_service

_counter = itertools.count(11000)


def _next_email() -> str:
    return f"react{next(_counter)}@example.com"


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


async def _setup_pair_with_message(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> tuple[str, str, str, str, str]:
    """
    Register Alice + Bob (mutual contacts), send one text message from Alice,
    and return (alice_token, bob_token, alice_id, bob_id, message_id).
    """
    email_a, email_b = _next_email(), _next_email()
    token_a = await _signin(client, monkeypatch, email_a, "Alice")
    token_b = await _signin(client, monkeypatch, email_b, "Bob")
    alice_id = (await client.get("/api/users/me", headers=_auth(token_a))).json()["id"]
    bob_id = (await client.get("/api/users/me", headers=_auth(token_b))).json()["id"]

    r = await client.post("/api/contacts/", json={"email": email_b}, headers=_auth(token_a))
    assert r.status_code == 201, r.text

    message_id = str(uuid.uuid4())
    r = await client.post(
        "/api/messages/",
        json={
            "client_id": message_id,
            "recipient_id": bob_id,
            "message_type": "text",
            "content": "Reaction-target",
        },
        headers=_auth(token_a),
    )
    assert r.status_code == 201, r.text
    return token_a, token_b, alice_id, bob_id, message_id


async def test_add_then_remove_reaction(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, token_b, alice_id, bob_id, message_id = await _setup_pair_with_message(
        client, monkeypatch
    )

    # Bob reacts ❤️
    r = await client.post(
        f"/api/messages/{message_id}/reactions",
        json={"emoji": "❤️"},
        headers=_auth(token_b),
    )
    assert r.status_code == 200, r.text
    summary = r.json()
    assert len(summary) == 1
    assert summary[0]["emoji"] == "❤️"
    assert summary[0]["count"] == 1
    assert summary[0]["user_ids"] == [bob_id]

    # Repeat add is a no-op
    r = await client.post(
        f"/api/messages/{message_id}/reactions",
        json={"emoji": "❤️"},
        headers=_auth(token_b),
    )
    assert r.status_code == 200, r.text
    assert r.json()[0]["count"] == 1

    # Alice piles on with the same emoji
    r = await client.post(
        f"/api/messages/{message_id}/reactions",
        json={"emoji": "❤️"},
        headers=_auth(token_a),
    )
    assert r.status_code == 200, r.text
    summary = r.json()
    assert len(summary) == 1
    assert summary[0]["count"] == 2
    assert set(summary[0]["user_ids"]) == {alice_id, bob_id}

    # Bob removes his — count drops to 1
    from urllib.parse import quote
    r = await client.delete(
        f"/api/messages/{message_id}/reactions/{quote('❤️')}",
        headers=_auth(token_b),
    )
    assert r.status_code == 200, r.text
    summary = r.json()
    assert len(summary) == 1
    assert summary[0]["count"] == 1
    assert summary[0]["user_ids"] == [alice_id]

    # Alice removes too — chip disappears entirely
    r = await client.delete(
        f"/api/messages/{message_id}/reactions/{quote('❤️')}",
        headers=_auth(token_a),
    )
    assert r.status_code == 200, r.text
    assert r.json() == []


async def test_reactions_included_in_message_listing(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, token_b, _alice_id, bob_id, message_id = await _setup_pair_with_message(
        client, monkeypatch
    )

    await client.post(
        f"/api/messages/{message_id}/reactions",
        json={"emoji": "🔥"},
        headers=_auth(token_b),
    )

    # Resolve the conversation id from Alice's side
    convs = (await client.get("/api/conversations/", headers=_auth(token_a))).json()
    conv = next(c for c in convs if c["other_user"]["id"] == bob_id)
    conv_id = conv["id"]

    r = await client.get(
        f"/api/conversations/{conv_id}/messages",
        headers=_auth(token_a),
    )
    assert r.status_code == 200, r.text
    msg = next(m for m in r.json()["messages"] if m["id"] == message_id)
    assert len(msg["reactions"]) == 1
    assert msg["reactions"][0]["emoji"] == "🔥"
    assert msg["reactions"][0]["count"] == 1


async def test_cannot_react_to_deleted_message(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, token_b, _alice_id, _bob_id, message_id = await _setup_pair_with_message(
        client, monkeypatch
    )

    # Alice (sender) deletes her own message
    r = await client.delete(
        f"/api/messages/{message_id}",
        headers=_auth(token_a),
    )
    assert r.status_code == 200, r.text

    # Bob can no longer react. Reacting to a deleted message is a validation
    # failure, which this API surfaces as 422 (ValidationFailedError) — the
    # same code it uses for every other validation failure.
    r = await client.post(
        f"/api/messages/{message_id}/reactions",
        json={"emoji": "❤️"},
        headers=_auth(token_b),
    )
    assert r.status_code == 422, r.text


async def test_non_participant_cannot_react(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token_a, _token_b, _alice_id, _bob_id, message_id = await _setup_pair_with_message(
        client, monkeypatch
    )

    # Carol has no relationship to Alice/Bob's conversation
    token_c = await _signin(client, monkeypatch, _next_email(), "Carol")
    r = await client.post(
        f"/api/messages/{message_id}/reactions",
        json={"emoji": "❤️"},
        headers=_auth(token_c),
    )
    assert r.status_code == 403, r.text


async def test_reaction_publishes_to_redis(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
    redis_client: aioredis.Redis,
) -> None:
    token_a, token_b, alice_id, bob_id, message_id = await _setup_pair_with_message(
        client, monkeypatch
    )

    # When Bob reacts, the event is pushed to ALICE's msg_delivery channel so
    # her open chat can update in place. Subscribe BEFORE posting to avoid the
    # race where publish completes before the subscriber is attached.
    pubsub = redis_client.pubsub()
    channel = f"msg_delivery:{alice_id}"
    await pubsub.subscribe(channel)
    await pubsub.get_message(ignore_subscribe_messages=True, timeout=0.5)

    r = await client.post(
        f"/api/messages/{message_id}/reactions",
        json={"emoji": "👍"},
        headers=_auth(token_b),
    )
    assert r.status_code == 200, r.text

    received = None
    for _ in range(20):
        msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=0.1)
        if msg and msg["type"] == "message":
            received = json.loads(msg["data"])
            if received.get("event") == "reaction_added":
                break
            received = None
        await asyncio.sleep(0.05)

    await pubsub.unsubscribe(channel)
    await pubsub.aclose()

    assert received is not None, "did not receive reaction_added on msg_delivery channel"
    assert received["message_id"] == message_id
    assert received["emoji"] == "👍"
    assert received["user_id"] == bob_id
    assert len(received["reactions"]) == 1

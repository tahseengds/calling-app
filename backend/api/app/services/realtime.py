"""
Redis Pub/Sub helper for real-time delivery.

Channel name constants are the contract between:
  - This FastAPI service (publisher)
  - The Node.js signaling server (prompt 08, subscriber)
  - The FCM worker (prompt 07, subscriber for streams)

Do NOT rename these constants without updating all three consumers.
"""
import json

import redis.asyncio as aioredis


# ── Channel name helpers ──────────────────────────────────────────────────────

def msg_delivery_channel(user_id: str) -> str:
    """New message / message-deleted events pushed to a recipient."""
    return f"msg_delivery:{user_id}"


def receipt_channel(user_id: str) -> str:
    """Delivered / read receipt events pushed to the original sender."""
    return f"receipt:{user_id}"


def presence_channel(user_id: str) -> str:
    """Online/offline presence events for a user."""
    return f"presence:{user_id}"


# ── Presence lookup ───────────────────────────────────────────────────────────
#
# The Node.js signaling server is the source of truth for live presence: it
# writes `user_presence:{userId}` = {"status": ..., "lastSeen": ...} on connect
# /disconnect/status-change. REST responses read those same keys so a freshly
# opened list shows the correct online state before the socket delivers updates.

async def get_presence_map(
    redis: aioredis.Redis, user_ids: list
) -> dict[str, str]:
    """Return {user_id_str: status} for the given ids; 'offline' when absent."""
    ids = [str(u) for u in user_ids]
    if not ids:
        return {}
    keys = [f"user_presence:{i}" for i in ids]
    raws = await redis.mget(keys)
    out: dict[str, str] = {}
    for i, raw in zip(ids, raws):
        status = "offline"
        if raw:
            try:
                data = json.loads(raw)
                status = data.get("status", "offline") or "offline"
            except (ValueError, TypeError):
                pass
        out[i] = status
    return out


async def stamp_presence(redis: aioredis.Redis, users: list) -> None:
    """Set `.presence` on a list of UserPublic objects from Redis (in place)."""
    if not users:
        return
    pmap = await get_presence_map(redis, [u.id for u in users])
    for u in users:
        u.presence = pmap.get(str(u.id), "offline")


# ── FCM queue stream name ─────────────────────────────────────────────────────

FCM_QUEUE_STREAM = "fcm_queue"


# ── Publish helper ────────────────────────────────────────────────────────────

async def publish(redis: aioredis.Redis, channel: str, payload: dict) -> None:
    """Serialize payload as JSON and publish to a Redis Pub/Sub channel."""
    await redis.publish(channel, json.dumps(payload, default=str))


async def enqueue_fcm(redis: aioredis.Redis, payload: dict) -> None:
    """
    Append a job to the fcm_queue Redis Stream.
    The worker in prompt 07 consumes this stream with XREADGROUP.
    All values must be strings for Redis Streams.
    """
    str_payload = {k: str(v) for k, v in payload.items()}
    await redis.xadd(FCM_QUEUE_STREAM, str_payload, maxlen=10_000, approximate=True)

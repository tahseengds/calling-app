"""
Redis Pub/Sub helper for real-time delivery.

Channel name constants are the contract between:
  - This FastAPI service (publisher)
  - The Node.js signaling server (prompt 08, subscriber)
  - The FCM worker (prompt 07, subscriber for streams)

Do NOT rename these constants without updating all three consumers.
"""
import json
from datetime import datetime, timezone

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


def user_events_channel(user_id: str) -> str:
    """General per-user events that don't fit msg_delivery/receipt/presence —
    e.g. block notifications. The Node signaling service forwards these as a
    user:* socket event family per the `event` field in the payload."""
    return f"user_events:{user_id}"


# ── Presence lookup ───────────────────────────────────────────────────────────
#
# The Node.js signaling server is the source of truth for live presence: it
# writes `user_presence:{userId}` = {"status": ..., "lastSeen": ...} on connect
# /disconnect/status-change. REST responses read those same keys so a freshly
# opened list shows the correct online state before the socket delivers updates.

def _parse_last_seen(raw: str | None) -> datetime | None:
    """Parse the ISO-8601 `lastSeen` the signaling server writes to Redis.

    The Node side emits `new Date().toISOString()` (always UTC, 'Z'-suffixed).
    `datetime.fromisoformat` on 3.11+ handles the 'Z', but normalize defensively
    so older runtimes don't choke.
    """
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


async def get_presence_map(
    redis: aioredis.Redis, user_ids: list
) -> dict[str, dict]:
    """Return {user_id_str: {"status": str, "last_seen": datetime | None}}.

    Reads the `user_presence:{id}` keys the Node signaling server maintains.
    Status defaults to 'offline' and last_seen to None when a key is absent
    (presence TTL expired or the user has never connected).
    """
    ids = [str(u) for u in user_ids]
    if not ids:
        return {}
    keys = [f"user_presence:{i}" for i in ids]
    raws = await redis.mget(keys)
    out: dict[str, dict] = {}
    for i, raw in zip(ids, raws):
        status = "offline"
        last_seen: datetime | None = None
        if raw:
            try:
                data = json.loads(raw)
                status = data.get("status", "offline") or "offline"
                last_seen = _parse_last_seen(data.get("lastSeen"))
            except (ValueError, TypeError):
                pass
        out[i] = {"status": status, "last_seen": last_seen}
    return out


async def stamp_presence(redis: aioredis.Redis, users: list) -> None:
    """Set `.presence` (and live `.last_seen`) on a list of UserPublic objects
    from Redis, in place.

    The DB `users.last_seen` column is only a coarse fallback — the signaling
    server tracks the *real* last-seen in Redis on every connect/disconnect and
    never writes it back to Postgres. So when Redis has a value we trust it over
    the (often stale) DB column; otherwise we leave the DB value untouched.
    """
    if not users:
        return
    pmap = await get_presence_map(redis, [u.id for u in users])
    for u in users:
        info = pmap.get(str(u.id))
        if not info:
            u.presence = "offline"
            continue
        u.presence = info["status"]
        if info["last_seen"] is not None:
            u.last_seen = info["last_seen"]


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

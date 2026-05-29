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


def user_events_channel(user_id: str) -> str:
    """
    General per-user events that don't fit msg_delivery/receipt/presence —
    e.g. block notifications (FIX 8). The Node signaling service forwards
    these as a single user:* socket event family per `event` field in the
    payload (e.g. payload.event="user_blocked" → socket emit "user:blocked").
    """
    return f"user_events:{user_id}"


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

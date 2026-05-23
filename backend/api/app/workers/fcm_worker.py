"""
FCM Worker — standalone process that consumes the fcm_queue Redis Stream and delivers
push notifications via FCM HTTP v1.

Run:
    python -m app.workers.fcm_worker

Design:
  - Consumer group "fcm_workers" on fcm_queue for at-least-once delivery.
  - success / token_invalid / permanent failure → XACK immediately.
  - transient failure (retryable) → ACK main queue, XADD to fcm_retry_queue with
    incremented attempt + next_attempt_at (backoff: 5s, 30s, 2m). After MAX_RETRIES
    attempts the entry is dropped and logged.
  - _drain_retry_queue() runs each loop iteration to flush due retry entries.
  - XAUTOCLAIM reclaims entries idle >60 s (handles worker crash mid-message).
"""
from __future__ import annotations

import asyncio
import logging
import time

import redis.asyncio as aioredis
from redis.exceptions import ResponseError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.config import settings
from app.models.user import User
from app.services.fcm_service import (
    FcmResult,
    _media_preview,
    build_call_notification,
    build_message_notification,
    send_fcm,
)
from app.services.realtime import FCM_QUEUE_STREAM

logger = logging.getLogger(__name__)

CONSUMER_GROUP = "fcm_workers"
CONSUMER_NAME = "worker-1"
FCM_RETRY_QUEUE = "fcm_retry_queue"
RETRY_DELAYS = [5, 30, 120]   # seconds per attempt (1→5s, 2→30s, 3→120s)
MAX_RETRIES = 3
XAUTOCLAIM_IDLE_MS = 60_000   # reclaim entries idle for >60 s


# ── Consumer group setup ──────────────────────────────────────────────────────

async def _ensure_consumer_group(redis: aioredis.Redis) -> None:
    """Create consumer group on fcm_queue. Idempotent — BUSYGROUP is silently ignored."""
    try:
        await redis.xgroup_create(FCM_QUEUE_STREAM, CONSUMER_GROUP, id="0", mkstream=True)
        logger.info("Created consumer group %s on %s", CONSUMER_GROUP, FCM_QUEUE_STREAM)
    except ResponseError as exc:
        if "BUSYGROUP" in str(exc):
            logger.debug("Consumer group %s already exists", CONSUMER_GROUP)
        else:
            raise


# ── DB helpers ────────────────────────────────────────────────────────────────

async def _load_user(db: AsyncSession, user_id: str) -> User | None:
    result = await db.execute(select(User).where(User.id == user_id))
    return result.scalar_one_or_none()


# ── Payload builder + sender ─────────────────────────────────────────────────

async def _build_and_send(
    fields: dict[str, str],
    db: AsyncSession,
    redis: aioredis.Redis,
) -> FcmResult:
    """Resolve recipient token, build the right payload type, call send_fcm."""
    recipient_id = fields.get("recipient_id", "")
    recipient = await _load_user(db, recipient_id)

    if not recipient or not recipient.fcm_token:
        logger.info("No FCM token for recipient %s — skipping", recipient_id)
        return FcmResult(status="failed", error="no_token")

    job_type = fields.get("type", "")

    if job_type == "new_message":
        sender_id = fields.get("sender_id", "")
        sender = await _load_user(db, sender_id)
        sender_name = sender.name if sender else "Someone"

        message_type = fields.get("message_type", "text")
        preview = (
            fields.get("content", "New message")
            if message_type == "text"
            else _media_preview(message_type)
        )
        payload = build_message_notification(
            sender_name=sender_name,
            preview=preview,
            conversation_id=fields.get("conversation_id", ""),
            message_id=fields.get("message_id", ""),
            sender_id=sender_id,
        )

    elif job_type in ("incoming_call", "missed_call"):
        payload = build_call_notification(
            call_id=fields.get("call_id", ""),
            caller_id=fields.get("caller_id", ""),
            caller_name=fields.get("caller_name", ""),
            caller_avatar=fields.get("caller_avatar") or None,
            call_type=fields.get("call_type", "video"),
            sdp_offer=fields.get("sdp_offer", ""),
            signal_token=fields.get("signal_token", ""),
        )

    else:
        logger.warning("Unknown FCM job type %r — skipping", job_type)
        return FcmResult(status="failed", error=f"unknown_type:{job_type}")

    return await send_fcm(recipient.fcm_token, payload, db=db)


# ── Entry processor ───────────────────────────────────────────────────────────

async def _process_entry(
    entry_id: str,
    fields: dict[str, str],
    db: AsyncSession,
    redis: aioredis.Redis,
    attempt: int = 1,
) -> None:
    """
    Process one fcm_queue entry.

    success / token_invalid / failed  → XACK (done).
    retryable, attempt < MAX_RETRIES  → XACK + XADD to fcm_retry_queue with backoff.
    retryable, attempt >= MAX_RETRIES → XACK + drop (logged).
    """
    result = await _build_and_send(fields, db, redis)

    if result.status in ("success", "token_invalid", "failed"):
        await redis.xack(FCM_QUEUE_STREAM, CONSUMER_GROUP, entry_id)
        if result.status == "success":
            logger.info("FCM delivered OK, acked %s", entry_id)
        elif result.status == "token_invalid":
            logger.info("FCM token invalid (cleared), acked %s", entry_id)
        else:
            logger.warning("FCM permanent failure for %s: %s", entry_id, result.error)
        return

    # retryable
    if attempt >= MAX_RETRIES:
        logger.error(
            "FCM max retries (%d) exhausted for entry %s — dropping", MAX_RETRIES, entry_id
        )
        await redis.xack(FCM_QUEUE_STREAM, CONSUMER_GROUP, entry_id)
        return

    delay = RETRY_DELAYS[attempt - 1] if (attempt - 1) < len(RETRY_DELAYS) else RETRY_DELAYS[-1]
    next_attempt_at = str(time.time() + delay)
    retry_fields: dict[str, str] = {
        **fields,
        "original_id": entry_id,
        "attempt": str(attempt + 1),
        "next_attempt_at": next_attempt_at,
    }
    await redis.xadd(FCM_RETRY_QUEUE, retry_fields)
    await redis.xack(FCM_QUEUE_STREAM, CONSUMER_GROUP, entry_id)
    logger.info(
        "FCM retryable — queued retry attempt=%d in %ds for %s",
        attempt + 1, delay, entry_id,
    )


# ── Retry queue drainer ───────────────────────────────────────────────────────

async def _drain_retry_queue(redis: aioredis.Redis, db: AsyncSession) -> None:
    """
    Scan fcm_retry_queue for entries whose next_attempt_at <= now and process them.
    Uses XRANGE (no consumer group needed — single worker owns the retry queue).
    """
    now = time.time()
    entries = await redis.xrange(FCM_RETRY_QUEUE, count=100)

    for retry_id, fields in entries:
        next_attempt_at = float(fields.get("next_attempt_at", "0"))
        if next_attempt_at > now:
            continue

        attempt = int(fields.get("attempt", "1"))
        original_fields = {
            k: v for k, v in fields.items()
            if k not in ("original_id", "attempt", "next_attempt_at")
        }

        result = await _build_and_send(original_fields, db, redis)

        if result.status in ("success", "token_invalid", "failed"):
            await redis.xdel(FCM_RETRY_QUEUE, retry_id)
            logger.info("Retry %s resolved: %s", retry_id, result.status)

        elif result.status == "retryable":
            await redis.xdel(FCM_RETRY_QUEUE, retry_id)
            if attempt >= MAX_RETRIES:
                logger.error(
                    "FCM max retries exhausted for retry entry %s — dropping", retry_id
                )
                continue
            delay = RETRY_DELAYS[attempt - 1] if (attempt - 1) < len(RETRY_DELAYS) else RETRY_DELAYS[-1]
            await redis.xadd(FCM_RETRY_QUEUE, {
                **original_fields,
                "original_id": fields.get("original_id", ""),
                "attempt": str(attempt + 1),
                "next_attempt_at": str(time.time() + delay),
            })
            logger.info("Retry rescheduled attempt=%d in %ds", attempt + 1, delay)


# ── Main loop ─────────────────────────────────────────────────────────────────

async def run_worker() -> None:
    logging.basicConfig(
        level=logging.DEBUG if settings.DEBUG else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    redis_client = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    engine = create_async_engine(settings.DATABASE_URL, poolclass=NullPool)
    SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

    await _ensure_consumer_group(redis_client)
    last_autoclaim_at = time.time()
    logger.info("FCM worker started, consuming stream %s", FCM_QUEUE_STREAM)

    try:
        while True:
            # Drain any due retry entries
            async with SessionLocal() as db:
                await _drain_retry_queue(redis_client, db)

            # Periodically reclaim stale pending entries (crash recovery)
            now = time.time()
            if now - last_autoclaim_at >= 60:
                reclaimed = await redis_client.xautoclaim(
                    FCM_QUEUE_STREAM, CONSUMER_GROUP, CONSUMER_NAME,
                    min_idle_time=XAUTOCLAIM_IDLE_MS,
                    count=10,
                )
                stale_entries = reclaimed[1] if reclaimed else []
                if stale_entries:
                    logger.info("XAUTOCLAIM reclaimed %d stale entries", len(stale_entries))
                    async with SessionLocal() as db:
                        for entry_id, fields in stale_entries:
                            await _process_entry(entry_id, fields, db, redis_client)
                last_autoclaim_at = now

            # Consume new entries via XREADGROUP
            result = await redis_client.xreadgroup(
                groupname=CONSUMER_GROUP,
                consumername=CONSUMER_NAME,
                streams={FCM_QUEUE_STREAM: ">"},
                count=10,
                block=5000,
            )

            if not result:
                continue

            for _stream, entries in result:
                async with SessionLocal() as db:
                    for entry_id, fields in entries:
                        await _process_entry(entry_id, fields, db, redis_client)

    finally:
        await redis_client.aclose()
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(run_worker())

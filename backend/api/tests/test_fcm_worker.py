"""
Tests for the FCM worker.

Covers:
  - Success path: XACK called, no retry entry created
  - token_invalid (404): XACK called, no retry entry
  - retryable (503) attempt 1: XACK + XADD to fcm_retry_queue with attempt=2
  - retryable at MAX_RETRIES: XACK + drop (no retry queue entry)
  - Consumer group creation is idempotent (BUSYGROUP ignored)
  - _drain_retry_queue: due entries are processed and XDELed
  - no_token (recipient has no FCM token): XACK, no retry
"""
import time
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import redis.asyncio as aioredis
from redis.exceptions import ResponseError

from app.services.fcm_service import FcmResult
from app.services.realtime import FCM_QUEUE_STREAM
from app.workers.fcm_worker import (
    CONSUMER_GROUP,
    FCM_RETRY_QUEUE,
    MAX_RETRIES,
    RETRY_DELAYS,
    _drain_retry_queue,
    _ensure_consumer_group,
    _process_entry,
)

pytestmark = pytest.mark.asyncio


# ── Fixtures ──────────────────────────────────────────────────────────────────

def _redis_mock() -> AsyncMock:
    """Minimal async Redis mock with the methods used by the worker."""
    m = AsyncMock()
    m.xack = AsyncMock()
    m.xadd = AsyncMock()
    m.xdel = AsyncMock()
    m.xrange = AsyncMock(return_value=[])
    m.xgroup_create = AsyncMock()
    return m


def _db_mock() -> AsyncMock:
    return AsyncMock()


def _fields(**kwargs) -> dict[str, str]:
    return {
        "type": "new_message",
        "recipient_id": "user-abc",
        "sender_id": "user-xyz",
        "message_id": "msg-001",
        "conversation_id": "conv-001",
        "message_type": "text",
        **kwargs,
    }


# ── _ensure_consumer_group ────────────────────────────────────────────────────

async def test_consumer_group_created_on_first_call() -> None:
    r = _redis_mock()
    await _ensure_consumer_group(r)
    r.xgroup_create.assert_called_once_with(
        FCM_QUEUE_STREAM, CONSUMER_GROUP, id="0", mkstream=True
    )


async def test_consumer_group_idempotent_busygroup() -> None:
    r = _redis_mock()
    r.xgroup_create.side_effect = ResponseError("BUSYGROUP Consumer Group name already exists")
    # Should not raise
    await _ensure_consumer_group(r)
    r.xgroup_create.assert_called_once()


async def test_consumer_group_raises_other_errors() -> None:
    r = _redis_mock()
    r.xgroup_create.side_effect = ResponseError("ERR some other error")
    with pytest.raises(ResponseError):
        await _ensure_consumer_group(r)


# ── _process_entry — success ──────────────────────────────────────────────────

async def test_success_acks_and_no_retry() -> None:
    r = _redis_mock()
    db = _db_mock()
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="success")
    )):
        await _process_entry("1234-0", _fields(), db, r, attempt=1)

    r.xack.assert_called_once_with(FCM_QUEUE_STREAM, CONSUMER_GROUP, "1234-0")
    r.xadd.assert_not_called()


# ── _process_entry — token_invalid ───────────────────────────────────────────

async def test_token_invalid_acks_and_no_retry() -> None:
    r = _redis_mock()
    db = _db_mock()
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="token_invalid", error="unregistered")
    )):
        await _process_entry("1234-0", _fields(), db, r, attempt=1)

    r.xack.assert_called_once_with(FCM_QUEUE_STREAM, CONSUMER_GROUP, "1234-0")
    r.xadd.assert_not_called()


# ── _process_entry — permanent failure ───────────────────────────────────────

async def test_permanent_failure_acks_and_no_retry() -> None:
    r = _redis_mock()
    db = _db_mock()
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="failed", error="http_400")
    )):
        await _process_entry("1234-0", _fields(), db, r, attempt=1)

    r.xack.assert_called_once()
    r.xadd.assert_not_called()


# ── _process_entry — retryable (503) ─────────────────────────────────────────

async def test_retryable_queues_to_retry_queue() -> None:
    r = _redis_mock()
    db = _db_mock()
    fields = _fields()
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="retryable", error="http_503")
    )):
        await _process_entry("1234-0", fields, db, r, attempt=1)

    # Must ACK the main queue entry
    r.xack.assert_called_once_with(FCM_QUEUE_STREAM, CONSUMER_GROUP, "1234-0")

    # Must add to retry queue
    r.xadd.assert_called_once()
    call_args = r.xadd.call_args
    queue_name = call_args[0][0]
    retry_payload = call_args[0][1]

    assert queue_name == FCM_RETRY_QUEUE
    assert retry_payload["attempt"] == "2"
    assert retry_payload["original_id"] == "1234-0"
    assert float(retry_payload["next_attempt_at"]) >= time.time() + RETRY_DELAYS[0] - 1


async def test_retryable_correct_backoff_attempt_2() -> None:
    r = _redis_mock()
    db = _db_mock()
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="retryable", error="http_503")
    )):
        await _process_entry("1234-0", _fields(), db, r, attempt=2)

    retry_payload = r.xadd.call_args[0][1]
    assert retry_payload["attempt"] == "3"
    assert float(retry_payload["next_attempt_at"]) >= time.time() + RETRY_DELAYS[1] - 1


# ── _process_entry — max retries exceeded ────────────────────────────────────

async def test_max_retries_drops_entry() -> None:
    r = _redis_mock()
    db = _db_mock()
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="retryable", error="http_503")
    )):
        await _process_entry("1234-0", _fields(), db, r, attempt=MAX_RETRIES)

    r.xack.assert_called_once_with(FCM_QUEUE_STREAM, CONSUMER_GROUP, "1234-0")
    r.xadd.assert_not_called()


# ── _process_entry — no FCM token ────────────────────────────────────────────

async def test_no_fcm_token_fails_gracefully() -> None:
    """Recipient exists but has no FCM token — should ACK and not retry."""
    r = _redis_mock()
    db = _db_mock()
    # _build_and_send returns failed with no_token
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="failed", error="no_token")
    )):
        await _process_entry("5678-0", _fields(), db, r, attempt=1)

    r.xack.assert_called_once_with(FCM_QUEUE_STREAM, CONSUMER_GROUP, "5678-0")
    r.xadd.assert_not_called()


# ── _drain_retry_queue ────────────────────────────────────────────────────────

async def test_drain_retry_processes_due_entry() -> None:
    """An entry whose next_attempt_at is in the past should be retried and XDELed."""
    r = _redis_mock()
    db = _db_mock()
    past = str(time.time() - 10)
    r.xrange.return_value = [
        (
            "1234-0",
            {
                "type": "new_message",
                "recipient_id": "user-abc",
                "sender_id": "user-xyz",
                "message_id": "msg-001",
                "conversation_id": "conv-001",
                "message_type": "text",
                "original_id": "orig-0",
                "attempt": "2",
                "next_attempt_at": past,
            },
        )
    ]
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="success")
    )):
        await _drain_retry_queue(r, db)

    r.xdel.assert_called_once_with(FCM_RETRY_QUEUE, "1234-0")
    r.xadd.assert_not_called()


async def test_drain_retry_skips_future_entry() -> None:
    """An entry whose next_attempt_at is in the future must not be processed."""
    r = _redis_mock()
    db = _db_mock()
    future = str(time.time() + 300)
    r.xrange.return_value = [
        (
            "1234-0",
            {
                **_fields(),
                "original_id": "orig-0",
                "attempt": "2",
                "next_attempt_at": future,
            },
        )
    ]
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="success")
    )) as mock_send:
        await _drain_retry_queue(r, db)

    mock_send.assert_not_called()
    r.xdel.assert_not_called()


async def test_drain_retry_max_retries_drops() -> None:
    """A due retry entry already at MAX_RETRIES should be dropped (XDELed, not re-queued)."""
    r = _redis_mock()
    db = _db_mock()
    past = str(time.time() - 10)
    r.xrange.return_value = [
        (
            "1234-0",
            {
                **_fields(),
                "original_id": "orig-0",
                "attempt": str(MAX_RETRIES),
                "next_attempt_at": past,
            },
        )
    ]
    with patch("app.workers.fcm_worker._build_and_send", new=AsyncMock(
        return_value=FcmResult(status="retryable", error="http_503")
    )):
        await _drain_retry_queue(r, db)

    r.xdel.assert_called_once_with(FCM_RETRY_QUEUE, "1234-0")
    r.xadd.assert_not_called()

"""
Firebase Cloud Messaging service.

OAuth2 access tokens are cached in process memory and refreshed ~5 minutes
before expiry (tokens last ~1 hour). The lock is created lazily so it binds
to the running event loop — safe for both the FastAPI process and the worker.

send_fcm() result codes:
  success        — 200, notification delivered.
  token_invalid  — 404 / UNREGISTERED, token cleared from DB, no retry.
  retryable      — 429 / 5xx, caller should retry with backoff.
  failed         — other 4xx, permanent, logged, no retry.
"""
from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Literal

import httpx
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings

logger = logging.getLogger(__name__)

FCM_SEND_URL = (
    "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
)
FCM_SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]


# ── Token cache (process-local) ───────────────────────────────────────────────

_token_cache: dict = {"token": None, "expires_at": 0.0}
_token_lock: asyncio.Lock | None = None


async def _get_access_token() -> str:
    """
    Return a valid FCM OAuth2 access token, refreshing when within 5 min of expiry.
    google.auth operations are synchronous — we run them in a thread executor.
    Raises if FIREBASE_SERVICE_ACCOUNT_PATH doesn't exist or credentials are invalid.
    """
    global _token_lock
    if _token_lock is None:
        _token_lock = asyncio.Lock()

    async with _token_lock:
        now = time.time()
        if _token_cache["token"] and now < _token_cache["expires_at"] - 300:
            return _token_cache["token"]

        from google.auth.transport.requests import Request
        from google.oauth2 import service_account

        creds = service_account.Credentials.from_service_account_file(
            settings.FIREBASE_SERVICE_ACCOUNT_PATH,
            scopes=FCM_SCOPES,
        )
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, creds.refresh, Request())

        _token_cache["token"] = creds.token
        _token_cache["expires_at"] = creds.expiry.timestamp() if creds.expiry else (now + 3600)
        logger.debug("FCM access token refreshed, expires at %s", _token_cache["expires_at"])
        return _token_cache["token"]


# ── Result type ───────────────────────────────────────────────────────────────

@dataclass
class FcmResult:
    status: Literal["success", "token_invalid", "retryable", "failed"]
    error: str | None = None


# ── Sender ────────────────────────────────────────────────────────────────────

async def send_fcm(
    token: str,
    message_payload: dict,
    db: AsyncSession | None = None,
) -> FcmResult:
    """
    Deliver a single FCM message.

    On token_invalid (404 / UNREGISTERED): clears the token from users table
    if *db* is provided. Does not raise — returns an FcmResult.
    """
    if not settings.FIREBASE_PROJECT_ID:
        logger.warning("FIREBASE_PROJECT_ID not configured — skipping FCM send")
        return FcmResult(status="failed", error="firebase_not_configured")

    try:
        access_token = await _get_access_token()
    except Exception as exc:
        logger.error("FCM token refresh failed: %s", exc)
        return FcmResult(status="retryable", error=str(exc))

    url = FCM_SEND_URL.format(project_id=settings.FIREBASE_PROJECT_ID)
    body = {"message": {"token": token, **message_payload}}

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                url,
                json=body,
                headers={"Authorization": f"Bearer {access_token}"},
            )
    except (httpx.TimeoutException, httpx.ConnectError) as exc:
        logger.warning("FCM network error: %s", exc)
        return FcmResult(status="retryable", error=str(exc))

    if resp.status_code == 200:
        return FcmResult(status="success")

    if resp.status_code == 404 or _is_unregistered(resp):
        logger.info("FCM token invalid (404/UNREGISTERED), clearing from DB")
        if db:
            await db.execute(
                update(_get_user_model()).where(
                    _get_user_model().fcm_token == token
                ).values(fcm_token=None)
            )
            await db.commit()
        return FcmResult(status="token_invalid", error="unregistered")

    if resp.status_code in (429,) or resp.status_code >= 500:
        logger.warning("FCM transient error %d", resp.status_code)
        return FcmResult(status="retryable", error=f"http_{resp.status_code}")

    # Other 4xx — permanent failure
    logger.error("FCM permanent error %d: %s", resp.status_code, resp.text[:200])
    return FcmResult(status="failed", error=f"http_{resp.status_code}")


def _is_unregistered(resp: httpx.Response) -> bool:
    """Check response body for UNREGISTERED error code."""
    try:
        body = resp.json()
        error_code = body.get("error", {}).get("details", [{}])[0].get("errorCode", "")
        return error_code == "UNREGISTERED"
    except Exception:
        return False


def _get_user_model():
    from app.models.user import User
    return User


# ── Notification payload builders ─────────────────────────────────────────────

def build_message_notification(
    sender_name: str,
    preview: str,
    conversation_id: str,
    message_id: str,
    sender_id: str,
) -> dict:
    """
    Standard chat message notification.
    android.priority=NORMAL, channel_id="messages".
    Body preview is generic for media types.
    """
    # DATA-ONLY on Android (no top-level "notification" block). With a
    # notification block the OS draws the tray notification itself when the app
    # is backgrounded — with an id the app can't see, so it could never be
    # cleared when the chat was opened. Data-only routes every message through
    # FcmService.onMessageReceived, which builds the notification with a stable
    # per-conversation id the app CAN cancel on read. HIGH priority so it's
    # still delivered promptly under Doze. (iOS keeps an apns alert below.)
    return {
        "android": {
            "priority": "HIGH",
        },
        "data": {
            "type": "new_message",
            "conversation_id": conversation_id,
            "message_id": message_id,
            "sender_id": sender_id,
            # Needed so the app can render the notification text itself.
            "sender_name": sender_name,
            "preview": preview[:100],
        },
        "apns": {
            "headers": {"apns-priority": "10"},
            "payload": {
                "aps": {
                    "alert": {"title": sender_name, "body": preview[:100]},
                    "sound": "default",
                }
            }
        },
    }


def build_call_notification(
    call_id: str,
    caller_id: str,
    caller_name: str,
    caller_avatar: str | None,
    call_type: str,
    sdp_offer: str,
    signal_token: str,
    initiated_at: str = "",
) -> dict:
    """
    Incoming call — data-only, HIGH priority, 30s TTL.
    Data-only so the OS delivers it even when the app is killed.
    signal_token (~60s JWT) lets the woken app join signaling without a login round-trip.
    """
    return {
        "android": {
            "priority": "HIGH",
            "ttl": "30s",
        },
        "data": {
            # IDs + SDP only — no persistent secrets
            "type": "incoming_call",
            "call_id": call_id,
            "caller_id": caller_id,
            "caller_name": caller_name,
            "caller_avatar": caller_avatar or "",
            "call_type": call_type,
            "sdp_offer": sdp_offer,
            "signal_token": signal_token,
            # Epoch-ms the call was placed; lets the native callee ring only for
            # the remaining window (or drop an expired call) on late delivery.
            "initiated_at": initiated_at,
        },
        "apns": {
            "headers": {
                "apns-push-type": "voip",
                "apns-priority": "10",
                "apns-expiration": "30",
            },
            "payload": {
                "aps": {"content-available": 1},
                "type": "incoming_call",
                "call_id": call_id,
                "signal_token": signal_token,
            },
        },
    }


def build_missed_call_notification(
    call_id: str,
    caller_id: str,
    caller_name: str,
    caller_avatar: str | None,
    call_type: str,
) -> dict:
    """
    Missed call — a quiet, user-visible notification, NOT a ring.

    Critically the data ``type`` is ``missed_call`` (not ``incoming_call``): the
    native FcmService dispatches on it and posts a missed-call notification.
    Sending ``incoming_call`` here — as the shared call builder did — makes a
    backgrounded/killed callee start CallService and RING for a call that already
    timed out. Data-only + high priority so a killed app still wakes to post the
    notification; no sdp_offer/signal_token since there is nothing to answer.
    """
    return {
        "android": {
            "priority": "HIGH",
            # Missed-call info stays useful even if delivered late (Doze/OEM
            # battery managers), so a much longer TTL than the live-ring push.
            "ttl": "3600s",
        },
        "data": {
            "type": "missed_call",
            "call_id": call_id,
            "caller_id": caller_id,
            "caller_name": caller_name,
            "caller_avatar": caller_avatar or "",
            "call_type": call_type,
        },
        "apns": {
            "headers": {
                "apns-push-type": "alert",
                "apns-priority": "5",
            },
            "payload": {
                "aps": {
                    "alert": {
                        "title": "Missed call",
                        "body": f"From {caller_name}",
                    },
                    "sound": "default",
                },
                "type": "missed_call",
                "call_id": call_id,
            },
        },
    }


def build_call_cancelled_notification(call_id: str) -> dict:
    """
    Caller cancelled / ended a still-ringing call.

    Data-only, HIGH priority, short TTL. The native FcmService handles this by
    stopping CallService for `call_id` (silences the ringer + dismisses the
    full-screen incoming-call notification) so a backgrounded / killed callee
    isn't left ringing after the caller hangs up. No alert/sound — it's a
    silent control message, never a user-visible notification.
    """
    return {
        "android": {
            "priority": "HIGH",
            "ttl": "30s",
        },
        "data": {
            "type": "call_cancelled",
            "call_id": call_id,
        },
        "apns": {
            "headers": {
                "apns-push-type": "background",
                "apns-priority": "5",
                "apns-expiration": "30",
            },
            "payload": {
                "aps": {"content-available": 1},
                "type": "call_cancelled",
                "call_id": call_id,
            },
        },
    }


def _media_preview(message_type: str) -> str:
    """Return a generic preview string for media messages."""
    return {
        "image": "📷 Photo",
        "video": "🎥 Video",
        "audio": "🎤 Voice message",
        "document": "📄 Document",
    }.get(message_type, "New message")

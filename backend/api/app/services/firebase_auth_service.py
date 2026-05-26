"""
Firebase Authentication ID token verification.

Used by /api/auth/firebase-signin: the Flutter client runs
FirebaseAuth.signInWithPhoneNumber → SMS code → getIdToken(), and ships
that ID token here. We verify it via google-auth's verify_firebase_token
(no firebase-admin dependency needed — google-auth is already in
requirements.txt for FCM).

The verified token carries the user's E.164 phone number in the
phone_number claim. That phone is the stable identifier we link to a
User row.

Security:
  - The token's signature is checked against Firebase's public keys
    (cached internally by google-auth).
  - `audience` must equal our FIREBASE_PROJECT_ID — guards against tokens
    minted by other Firebase projects.
  - We reject tokens older than [iat + REPLAY_WINDOW_SECONDS], so a
    stolen-and-reused token has a tight blast radius.
"""
from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

from app.config import settings
from app.utils.exceptions import UnauthorizedError, ValidationFailedError

logger = logging.getLogger(__name__)

# Max age of a Firebase ID token we'll accept on the firebase-signin route.
# Firebase ID tokens live ~1 hour; we want a *much* tighter window because
# we use them only once, immediately after the client gets them.
REPLAY_WINDOW_SECONDS = 5 * 60


async def verify_firebase_id_token(id_token: str) -> dict[str, Any]:
    """
    Verify a Firebase Auth ID token and return its claims.

    Raises:
        UnauthorizedError — token is invalid, expired, or signed by a
                            different Firebase project.
        ValidationFailedError — token is valid but lacks the phone_number
                                claim we need to identify the user.
    """
    if not settings.FIREBASE_PROJECT_ID:
        # Misconfiguration on the server — surface as 500-class to the caller
        # rather than silently letting any token through.
        logger.error("FIREBASE_PROJECT_ID not set; cannot verify ID token")
        raise UnauthorizedError("Firebase verification is unavailable")

    # google-auth's verify_firebase_token is synchronous (it does an HTTPS
    # fetch of Google's public keys, cached process-locally). Run it in a
    # thread to avoid blocking the event loop.
    try:
        claims = await asyncio.get_event_loop().run_in_executor(
            None, _verify_sync, id_token, settings.FIREBASE_PROJECT_ID
        )
    except Exception as exc:
        # google-auth raises a variety of error subclasses; treat them all
        # as 401 (we don't leak which kind to the client). We log at WARNING
        # with the full message and traceback so docker logs surfaces the
        # diagnosis — uvicorn's default config only outputs WARNING+ for
        # non-uvicorn loggers.
        logger.warning(
            "Firebase ID token rejected: %s: %s",
            type(exc).__name__,
            exc,
            exc_info=True,
        )
        raise UnauthorizedError("Invalid Firebase ID token") from exc

    # Tight replay window
    iat = claims.get("iat")
    if isinstance(iat, (int, float)):
        if time.time() - float(iat) > REPLAY_WINDOW_SECONDS:
            raise UnauthorizedError("Firebase ID token is too old")

    phone = claims.get("phone_number")
    if not phone:
        # Could happen if someone signs in with email/Google instead of
        # phone — we only accept phone-based identities.
        raise ValidationFailedError(
            "Firebase ID token is missing phone_number — sign in by phone"
        )

    return claims


def _verify_sync(id_token: str, project_id: str) -> dict[str, Any]:
    """Synchronous body of verify_firebase_id_token (runs in a thread)."""
    # Local import keeps the FastAPI process startup time lean — these
    # modules pull in transitive deps we don't need until first verify.
    from google.auth.transport import requests as ga_requests
    from google.oauth2 import id_token as ga_id_token

    request = ga_requests.Request()
    return ga_id_token.verify_firebase_token(
        id_token,
        request,
        audience=project_id,
    )

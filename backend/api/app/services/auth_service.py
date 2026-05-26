"""
Authentication business logic.

All functions are async and work through the SQLAlchemy AsyncSession +
the async Redis client. No HTTP concerns here — raise AppError subclasses
and let the router/exception handler convert them to JSON responses.
"""
import logging
from datetime import datetime, timedelta, timezone

import redis.asyncio as aioredis
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.schemas.auth import (
    FirebaseSignInRequest,
    LogoutRequest,
    RefreshRequest,
    TokenResponse,
)
from app.services.firebase_auth_service import verify_firebase_id_token
from app.utils.exceptions import UnauthorizedError, ValidationFailedError
from app.utils.security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    hash_refresh_token,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Firebase sign-in (Google or email/password via Firebase Auth)
# ---------------------------------------------------------------------------

async def firebase_signin(
    db: AsyncSession,
    redis: aioredis.Redis,
    req: FirebaseSignInRequest,
) -> TokenResponse:
    """
    Trade a Firebase Auth ID token (Google or email/password) for our own
    access + refresh JWTs.

    Strategy:
      - Verify the ID token (signature, audience, replay window, UID
        present, email_verified for password sign-ins).
      - Upsert a User row keyed on the Firebase UID — first sign-in
        creates the row, returning sign-in just updates session
        bookkeeping.
      - Mint our own tokens via issue_tokens() — Firebase identity is
        only the sign-in gate.
    """
    claims = await verify_firebase_id_token(req.firebase_id_token)
    uid: str | None = claims.get("sub") or claims.get("user_id")
    if not uid:
        raise ValidationFailedError("Firebase ID token is missing UID")
    email = (claims.get("email") or "").strip().lower() or None
    provider = (claims.get("firebase") or {}).get("sign_in_provider")

    # Primary lookup: Firebase UID (stable). Fall back to email — useful if
    # a user signs in via Google after having a password row, since
    # Firebase Auth links the two providers under a single account when
    # the same email is verified.
    result = await db.execute(select(User).where(User.firebase_uid == uid))
    user = result.scalar_one_or_none()
    if user is None and email:
        result = await db.execute(select(User).where(User.email == email))
        user = result.scalar_one_or_none()

    if user is None:
        # First-time sign-in — create the account. Display name preference:
        # client-supplied → Firebase 'name' claim → local-part of email.
        default_name = (
            (req.name or "").strip()
            or (claims.get("name") or "").strip()
            or (email.split("@")[0] if email else "New user")
        )
        user = User(
            name=default_name[:100],
            email=email,
            firebase_uid=uid,
            auth_provider=provider,
            avatar_url=claims.get("picture"),
            is_active=True,
            password_hash=None,  # Firebase-authed users have no local password.
        )
        db.add(user)
        await db.flush()  # populate user.id
        logger.info(
            "Created user via Firebase (provider=%s): id=%s", provider, user.id
        )
    else:
        # Returning user — backfill missing fields if this is the first
        # time they've signed in under the new schema.
        if user.firebase_uid is None:
            user.firebase_uid = uid
        if user.email is None and email:
            user.email = email
        if user.auth_provider is None and provider:
            user.auth_provider = provider

    # Update session bookkeeping (FCM token, last_seen) on every sign-in.
    if req.fcm_token:
        user.fcm_token = req.fcm_token
        user.fcm_token_updated_at = datetime.now(timezone.utc)
    user.last_seen = datetime.now(timezone.utc)

    # Re-activate any previously deactivated account that comes back via a
    # successful Firebase sign-in — that's our verification gate.
    if not user.is_active:
        user.is_active = True

    await db.commit()

    return await issue_tokens(db, user, device_id=req.device_id)


# ---------------------------------------------------------------------------
# Issue tokens (internal helper)
# ---------------------------------------------------------------------------

async def issue_tokens(
    db: AsyncSession,
    user: User,
    device_id: str,
) -> TokenResponse:
    # Rotate: revoke any existing non-revoked token for this (user, device)
    await db.execute(
        update(RefreshToken)
        .where(
            RefreshToken.user_id == user.id,
            RefreshToken.device_id == device_id,
            RefreshToken.revoked_at.is_(None),
        )
        .values(revoked_at=datetime.now(timezone.utc))
    )

    access_token = create_access_token(str(user.id))
    raw_refresh, refresh_hash = create_refresh_token()

    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=refresh_hash,
            device_id=device_id,
            expires_at=datetime.now(timezone.utc)
            + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        )
    )
    await db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=raw_refresh,
        expires_in=settings.JWT_ACCESS_EXPIRE_MINUTES * 60,
    )


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

async def refresh(
    db: AsyncSession,
    redis: aioredis.Redis,
    req: RefreshRequest,
) -> TokenResponse:
    token_hash = hash_refresh_token(req.refresh_token)

    result = await db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    )
    record = result.scalar_one_or_none()

    if record is None:
        raise UnauthorizedError("Invalid refresh token")

    # Reuse detection — a revoked token being replayed is a theft signal
    if record.revoked_at is not None:
        await db.execute(
            update(RefreshToken)
            .where(
                RefreshToken.user_id == record.user_id,
                RefreshToken.revoked_at.is_(None),
            )
            .values(revoked_at=datetime.now(timezone.utc))
        )
        await db.commit()
        raise UnauthorizedError(
            "Refresh token reuse detected — all sessions have been revoked"
        )

    if record.expires_at < datetime.now(timezone.utc):
        raise UnauthorizedError("Refresh token expired")

    # Rotate: mark old token revoked, issue new pair
    record.revoked_at = datetime.now(timezone.utc)
    await db.commit()

    result = await db.execute(select(User).where(User.id == record.user_id))
    user = result.scalar_one_or_none()
    if not user or not user.is_active:
        raise UnauthorizedError("User not found or inactive")

    return await issue_tokens(db, user, device_id=req.device_id)


# ---------------------------------------------------------------------------
# Logout
# ---------------------------------------------------------------------------

async def logout(
    db: AsyncSession,
    redis: aioredis.Redis,
    req: LogoutRequest,
    raw_access_token: str,
) -> None:
    # Revoke the refresh token
    token_hash = hash_refresh_token(req.refresh_token)
    result = await db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    )
    record = result.scalar_one_or_none()
    if record and record.revoked_at is None:
        record.revoked_at = datetime.now(timezone.utc)
        await db.commit()

    # Blacklist the access token's jti for its remaining lifetime.
    # Narrow except — only swallow JWT decode failures (token already
    # invalid means nothing to blacklist). Other errors should surface.
    try:
        payload = decode_access_token(raw_access_token)
    except UnauthorizedError:
        return
    jti: str | None = payload.get("jti")
    if jti:
        exp: int = payload.get("exp", 0)
        remaining = max(1, int(exp - datetime.now(timezone.utc).timestamp()))
        await redis.setex(f"token_revoked:{jti}", remaining, "1")

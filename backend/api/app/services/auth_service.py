"""
Authentication business logic.

All functions are async and work through the SQLAlchemy AsyncSession +
the async Redis client. No HTTP concerns here — raise AppError subclasses
and let the router/exception handler convert them to JSON responses.
"""
import logging
import random
from datetime import datetime, timedelta, timezone

import redis.asyncio as aioredis
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.schemas.auth import (
    FirebaseSignInRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    RegisterResponse,
    TokenResponse,
    VerifyOtpRequest,
)
from app.services.firebase_auth_service import verify_firebase_id_token
from app.utils.exceptions import ConflictError, UnauthorizedError, ValidationFailedError
from app.utils.security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    hash_password,
    hash_refresh_token,
    verify_password,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Register
# ---------------------------------------------------------------------------

async def register(
    db: AsyncSession,
    redis: aioredis.Redis,
    req: RegisterRequest,
) -> RegisterResponse:
    # Reject if an *active* account already owns this phone
    result = await db.execute(
        select(User).where(User.phone == req.phone, User.is_active.is_(True))
    )
    if result.scalar_one_or_none():
        raise ConflictError("Phone number is already registered")

    # Upsert: create or update the pending (inactive) user
    result = await db.execute(select(User).where(User.phone == req.phone))
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            name=req.name,
            phone=req.phone,
            password_hash=hash_password(req.password),
            is_active=False,
        )
        db.add(user)
    else:
        user.name = req.name
        user.password_hash = hash_password(req.password)

    await db.commit()

    # Generate and store a 6-digit OTP
    otp = f"{random.randint(0, 999_999):06d}"
    await redis.setex(f"otp:{req.phone}", settings.OTP_TTL_SECONDS, otp)
    await redis.setex(f"otp_attempts:{req.phone}", settings.OTP_TTL_SECONDS, "0")

    # TODO: integrate SMS provider to deliver the OTP to req.phone
    if settings.DEBUG:
        logger.debug("OTP for %s: %s", req.phone, otp)
    else:
        logger.info("OTP generated for registration (phone not logged in production)")

    return RegisterResponse(
        otp_sent=True,
        debug_otp=otp if settings.DEBUG else None,
    )


# ---------------------------------------------------------------------------
# Verify OTP
# ---------------------------------------------------------------------------

async def verify_otp(
    db: AsyncSession,
    redis: aioredis.Redis,
    req: VerifyOtpRequest,
) -> TokenResponse:
    stored_otp: str | None = await redis.get(f"otp:{req.phone}")
    if stored_otp is None:
        raise ValidationFailedError("OTP expired or not found — please request a new one")

    attempts = await redis.incr(f"otp_attempts:{req.phone}")
    if attempts > 5:
        await redis.delete(f"otp:{req.phone}", f"otp_attempts:{req.phone}")
        raise ValidationFailedError("Too many failed OTP attempts — please register again")

    if stored_otp != req.otp:
        raise ValidationFailedError("Incorrect OTP")

    # Activate the user
    result = await db.execute(select(User).where(User.phone == req.phone))
    user = result.scalar_one_or_none()
    if not user:
        raise ValidationFailedError("User not found")

    user.is_active = True
    await db.commit()

    await redis.delete(f"otp:{req.phone}", f"otp_attempts:{req.phone}")

    return await issue_tokens(db, user, device_id="default")


# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------

async def login(
    db: AsyncSession,
    redis: aioredis.Redis,
    req: LoginRequest,
) -> TokenResponse:
    result = await db.execute(select(User).where(User.phone == req.phone))
    user = result.scalar_one_or_none()

    if not user or not user.password_hash or not verify_password(req.password, user.password_hash):
        raise UnauthorizedError("Invalid phone or password")

    if not user.is_active:
        raise UnauthorizedError("Account not verified — please complete OTP verification")

    if req.fcm_token:
        user.fcm_token = req.fcm_token
        user.fcm_token_updated_at = datetime.now(timezone.utc)

    user.last_seen = datetime.now(timezone.utc)
    await db.commit()

    return await issue_tokens(db, user, device_id=req.device_id)


# ---------------------------------------------------------------------------
# Firebase sign-in (phone via Firebase Auth)
# ---------------------------------------------------------------------------

async def firebase_signin(
    db: AsyncSession,
    redis: aioredis.Redis,
    req: FirebaseSignInRequest,
) -> TokenResponse:
    """
    Trade a Firebase Auth ID token (obtained client-side from a verified
    SMS) for our own access + refresh JWTs.

    Strategy:
      - Verify the ID token (signature, audience, replay window, has
        phone_number claim).
      - Upsert a User row keyed on the phone number — first sign-in on a
        new phone creates the row; returning sign-in just updates
        last_seen / fcm_token.
      - Mint our own tokens via issue_tokens() — Firebase identity is
        only the SMS gate.
    """
    claims = await verify_firebase_id_token(req.firebase_id_token)
    phone: str = claims["phone_number"]

    # Look up the user by phone; create if missing.
    result = await db.execute(select(User).where(User.phone == phone))
    user = result.scalar_one_or_none()

    if user is None:
        # First-time sign-in on this phone — create the account.
        # Display name preference: client-supplied → Firebase 'name' claim →
        # last 4 digits of the phone as a placeholder.
        default_name = (
            (req.name or "").strip()
            or (claims.get("name") or "").strip()
            or f"User {phone[-4:]}"
        )
        user = User(
            name=default_name[:100],
            phone=phone,
            is_active=True,
            password_hash=None,  # Firebase-authed users have no local password.
        )
        db.add(user)
        await db.flush()  # populate user.id
        logger.info("Created user via Firebase phone auth: id=%s", user.id)

    # Update session bookkeeping (FCM token, last_seen) on every sign-in.
    if req.fcm_token:
        user.fcm_token = req.fcm_token
        user.fcm_token_updated_at = datetime.now(timezone.utc)
    user.last_seen = datetime.now(timezone.utc)

    # Re-activate any previously deactivated account that comes back via
    # the same phone — they passed Firebase's SMS challenge, that's enough.
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

    # Blacklist the access token's jti for its remaining lifetime
    try:
        payload = decode_access_token(raw_access_token)
        jti: str | None = payload.get("jti")
        if jti:
            exp: int = payload.get("exp", 0)
            remaining = max(1, int(exp - datetime.now(timezone.utc).timestamp()))
            await redis.setex(f"token_revoked:{jti}", remaining, "1")
    except Exception:
        pass  # Token already invalid — nothing to blacklist

from collections.abc import AsyncGenerator
from uuid import UUID

import redis.asyncio as aioredis
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db  # re-export
from app.models.user import User
from app.utils.exceptions import ForbiddenError, RateLimitError, UnauthorizedError
from app.utils.security import decode_access_token

__all__ = [
    "get_db",
    "get_redis",
    "get_current_user",
    "get_admin_user",
    "rate_limit",
    "client_ip",
]


# ---------------------------------------------------------------------------
# Client IP helper
# ---------------------------------------------------------------------------

def client_ip(request: Request) -> str:
    """
    Return the real client IP, honoring Nginx's X-Real-IP / first hop of
    X-Forwarded-For. The raw ASGI client IP is Nginx's container IP, so
    rate-limit buckets and internal-IP gates must NOT use it directly.
    """
    real = request.headers.get("x-real-ip")
    if real:
        return real.strip()
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        # First hop is the original client.
        return fwd.split(",", 1)[0].strip()
    return request.client.host if request.client else "unknown"

# auto_error=False so we can raise a 401 (not the default 403) when no token
_bearer = HTTPBearer(auto_error=False)


# ---------------------------------------------------------------------------
# Redis dependency
# ---------------------------------------------------------------------------

async def get_redis(request: Request) -> AsyncGenerator[aioredis.Redis, None]:
    """Yield the shared Redis client stored on app.state by the lifespan."""
    yield request.app.state.redis


# ---------------------------------------------------------------------------
# Current user dependency
# ---------------------------------------------------------------------------

async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
) -> User:
    if credentials is None:
        raise UnauthorizedError("Authentication credentials are required")
    token = credentials.credentials
    payload = decode_access_token(token)

    jti: str | None = payload.get("jti")
    if jti and await redis.exists(f"token_revoked:{jti}"):
        raise UnauthorizedError("Token has been revoked")

    user_id_str: str | None = payload.get("sub")
    if not user_id_str:
        raise UnauthorizedError("Malformed token")

    result = await db.execute(select(User).where(User.id == UUID(user_id_str)))
    user = result.scalar_one_or_none()

    if not user or not user.is_active:
        raise UnauthorizedError("User not found or inactive")

    return user


# ---------------------------------------------------------------------------
# Admin dependency
# ---------------------------------------------------------------------------

async def get_admin_user(
    current_user: User = Depends(get_current_user),
) -> User:
    """
    Require the authenticated user to be an administrator.

    There is no role column on the User model; admins are configured via the
    ADMIN_EMAILS env var (comma-separated, case-insensitive). A user with no
    email, or an email not in the list, gets a 403.
    """
    admins = settings.admin_emails
    email = (current_user.email or "").strip().lower()
    if not email or email not in admins:
        raise ForbiddenError("Administrator access required")
    return current_user


# ---------------------------------------------------------------------------
# Rate limit dependency factory
# ---------------------------------------------------------------------------

def rate_limit(endpoint_name: str, max_calls: int, window_seconds: int):
    """
    Dependency factory.  Usage:

        Depends(rate_limit("register", 5, 60))

    Keys: ratelimit:{ip}:{endpoint_name}
    """

    async def _check(
        request: Request,
        redis: aioredis.Redis = Depends(get_redis),
    ) -> None:
        ip = client_ip(request)
        key = f"ratelimit:{ip}:{endpoint_name}"
        count = await redis.incr(key)
        if count == 1:
            await redis.expire(key, window_seconds)
        elif count > max_calls:
            # Self-heal a bucket that was left without a TTL (e.g. the process
            # died between INCR and EXPIRE on the very first call). Without this,
            # a TTL-less key would rate-limit that IP+endpoint permanently.
            if await redis.ttl(key) < 0:
                await redis.expire(key, window_seconds)
        if count > max_calls:
            raise RateLimitError(
                f"Too many requests — limit is {max_calls} per {window_seconds}s"
            )

    return _check

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

import redis.asyncio as aioredis

from app.dependencies import get_db, get_redis, get_current_user, rate_limit
from app.models.user import User
from app.schemas.auth import (
    FirebaseSignInRequest,
    LogoutRequest,
    RefreshRequest,
    TokenResponse,
)
from app.services import auth_service

router = APIRouter()


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    req: RefreshRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
    _rl: None = Depends(rate_limit("refresh_token", 30, 60)),
) -> TokenResponse:
    # Rate-limited per-IP: refresh is unauthenticated (the refresh token is the
    # only credential), so an open endpoint invites brute-forcing. 30/min is
    # generous for a legit client rotating tokens but throttles guessing.
    return await auth_service.refresh(db, redis, req)


@router.post("/firebase-signin", response_model=TokenResponse)
async def firebase_signin(
    req: FirebaseSignInRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
    _rl: None = Depends(rate_limit("firebase_signin", 10, 60)),
) -> TokenResponse:
    """
    Sign in (or register on first call) using a Firebase Auth ID token
    (Google or email/password). Firebase handles identity verification,
    we just trade the verified ID token for our own access + refresh JWTs.
    """
    return await auth_service.firebase_signin(db, redis, req)


@router.post("/logout", status_code=204)
async def logout(
    req: LogoutRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
    _current_user: User = Depends(get_current_user),
) -> None:
    raw_token = request.headers.get("authorization", "").removeprefix("Bearer ").removeprefix("bearer ")
    await auth_service.logout(db, redis, req, raw_token)

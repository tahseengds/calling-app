from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

import redis.asyncio as aioredis

from app.dependencies import get_db, get_redis, get_current_user, rate_limit
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
from app.services import auth_service

router = APIRouter()


# NOTE: /register, /login and /verify-otp predate Firebase Phone Auth and
# are no longer called by the Flutter client (Firebase issues an ID token
# which we trade at /firebase-signin instead). They remain live as a
# fallback / for any external integration; remove in a future pass once
# we're sure no client depends on them.
@router.post("/register", response_model=RegisterResponse, deprecated=True)
async def register(
    req: RegisterRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
    _rl: None = Depends(rate_limit("register", 5, 60)),
) -> RegisterResponse:
    return await auth_service.register(db, redis, req)


@router.post("/verify-otp", response_model=TokenResponse, deprecated=True)
async def verify_otp(
    req: VerifyOtpRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
    _rl: None = Depends(rate_limit("verify_otp", 10, 60)),
) -> TokenResponse:
    return await auth_service.verify_otp(db, redis, req)


@router.post("/login", response_model=TokenResponse, deprecated=True)
async def login(
    req: LoginRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
    _rl: None = Depends(rate_limit("login", 5, 60)),
) -> TokenResponse:
    return await auth_service.login(db, redis, req)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    req: RefreshRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
) -> TokenResponse:
    return await auth_service.refresh(db, redis, req)


@router.post("/firebase-signin", response_model=TokenResponse)
async def firebase_signin(
    req: FirebaseSignInRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
    _rl: None = Depends(rate_limit("firebase_signin", 10, 60)),
) -> TokenResponse:
    """
    Sign in (or register on first call) using a Firebase Phone Auth ID token.

    Replaces the old register / login / verify-otp trio: Firebase handles
    the SMS verification, we just trade the verified ID token for our
    own access + refresh JWTs.
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

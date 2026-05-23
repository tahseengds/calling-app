from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

import redis.asyncio as aioredis

from app.dependencies import get_db, get_redis, get_current_user, rate_limit
from app.models.user import User
from app.schemas.auth import (
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


@router.post("/register", response_model=RegisterResponse)
async def register(
    req: RegisterRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
    _rl: None = Depends(rate_limit("register", 5, 60)),
) -> RegisterResponse:
    return await auth_service.register(db, redis, req)


@router.post("/verify-otp", response_model=TokenResponse)
async def verify_otp(
    req: VerifyOtpRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
    _rl: None = Depends(rate_limit("verify_otp", 10, 60)),
) -> TokenResponse:
    return await auth_service.verify_otp(db, redis, req)


@router.post("/login", response_model=TokenResponse)
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

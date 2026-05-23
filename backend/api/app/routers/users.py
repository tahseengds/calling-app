from typing import Annotated
from uuid import UUID

import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, File, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user, get_db, get_redis
from app.models.user import User
from app.schemas.user import FcmTokenRequest, UpdateProfileRequest, UserMe, UserPublic
from app.services import user_service

router = APIRouter()


@router.get("/me", response_model=UserMe)
async def get_me(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserMe:
    return await user_service.get_me(db, current_user)


@router.put("/me", response_model=UserMe)
async def update_profile(
    req: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserMe:
    return await user_service.update_profile(db, current_user, req)


@router.get("/{user_id}", response_model=UserPublic)
async def get_user(
    user_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserPublic:
    return await user_service.get_user(db, user_id)


@router.post("/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
async def update_fcm_token(
    req: FcmTokenRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    await user_service.update_fcm_token(db, current_user, req)



@router.post("/avatar", response_model=UserMe)
async def upload_avatar(
    file: Annotated[UploadFile, File(description="Avatar image (JPEG / PNG / WebP)")],
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserMe:
    return await user_service.upload_avatar(db, current_user, file)

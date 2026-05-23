from uuid import UUID

import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user, get_db, get_redis, rate_limit
from app.models.user import User
from app.schemas.message import MessageResponse, ReceiptRequest, SendMessageRequest
from app.services import message_service

router = APIRouter()


@router.post(
    "/",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("send_message", max_calls=60, window_seconds=60))],
)
async def send_message(
    req: SendMessageRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
) -> MessageResponse:
    return await message_service.send_message(db, redis, current_user, req)


@router.put("/delivered", status_code=status.HTTP_204_NO_CONTENT)
async def mark_delivered(
    req: ReceiptRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
) -> None:
    await message_service.mark_delivered(db, redis, current_user, req.message_ids)


@router.put("/read", status_code=status.HTTP_204_NO_CONTENT)
async def mark_read(
    req: ReceiptRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
) -> None:
    await message_service.mark_read(db, redis, current_user, req.message_ids)


@router.delete("/{message_id}", response_model=MessageResponse)
async def soft_delete(
    message_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
) -> MessageResponse:
    return await message_service.soft_delete(db, redis, current_user, message_id)

from uuid import UUID

import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user, get_db, get_redis
from app.models.user import User
from app.schemas.contact import AddContactRequest, BlockRequest, ContactResponse
from app.services import contact_service

router = APIRouter()


@router.get("/", response_model=list[ContactResponse])
async def list_contacts(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ContactResponse]:
    return await contact_service.list_contacts(db, current_user)


@router.post("/", response_model=ContactResponse, status_code=status.HTTP_201_CREATED)
async def add_contact(
    req: AddContactRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ContactResponse:
    return await contact_service.add_contact(db, current_user, req)


@router.delete("/{contact_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_contact(
    contact_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    await contact_service.remove_contact(db, current_user, contact_id)


@router.put("/{contact_id}/block", response_model=ContactResponse)
async def set_blocked(
    contact_id: UUID,
    req: BlockRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
) -> ContactResponse:
    # Redis is passed through so set_blocked can publish a user_blocked
    # event for FIX 8 (end any active call between the two parties).
    return await contact_service.set_blocked(
        db, current_user, contact_id, req.blocked, redis=redis,
    )

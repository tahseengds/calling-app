"""
Calls router — partial (TURN credentials only for now).
Mounted at /api/auth so the full path is GET /api/auth/turn-credentials.
WebRTC call signalling is added in prompt 08 (Node.js) and prompt 14 (Flutter).
"""
import redis.asyncio as aioredis
from fastapi import APIRouter, Depends

from app.dependencies import get_current_user, get_redis
from app.models.user import User
from app.schemas.turn import TurnCredentialsResponse
from app.services import turn_service

router = APIRouter()


@router.get("/turn-credentials", response_model=TurnCredentialsResponse)
async def get_turn_credentials(
    current_user: User = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
) -> TurnCredentialsResponse:
    return await turn_service.generate_turn_credentials(redis, str(current_user.id))

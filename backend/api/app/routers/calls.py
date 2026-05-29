"""
Calls router — TURN credentials + historical call list.

WebRTC signalling lives in the Node.js service (Prompt 08); this module only
exposes the REST endpoints the Flutter client polls.
"""
import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user, get_db, get_redis
from app.models.user import User
from app.schemas.call import CallHistoryPage, CallLogReplayRequest
from app.schemas.turn import TurnCredentialsResponse
from app.services import call_service, turn_service

router = APIRouter()


@router.get("/turn-credentials", response_model=TurnCredentialsResponse)
async def get_turn_credentials(
    current_user: User = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
) -> TurnCredentialsResponse:
    return await turn_service.generate_turn_credentials(redis, str(current_user.id))


@router.get("/history", response_model=CallHistoryPage)
async def list_call_history(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=30, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CallHistoryPage:
    """The caller's call history, newest first, cursor-paginated."""
    return await call_service.list_call_history(
        db, current_user, cursor=cursor, limit=limit
    )


@router.post("/log", status_code=status.HTTP_204_NO_CONTENT)
async def replay_interrupted_call(
    req: CallLogReplayRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """
    Client-driven reconciliation for calls whose end didn't reach Node
    signaling (force-killed app mid-call, OS audio interruption, ICE fail,
    user blocked mid-call). Idempotent on call_id — the Node side may have
    already written the row from its own hangup path.

    See Flutter's CallRepository.syncInterruptedCalls — invoked once per app
    launch.
    """
    await call_service.replay_call_log(db, current_user, req)

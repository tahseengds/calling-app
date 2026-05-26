from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user, get_db
from app.models.user import User
from app.schemas.conversation import GetOrCreateConversationRequest
from app.schemas.message import ConversationResponse, MessagePage
from app.services import conversation_service, message_service

router = APIRouter()


@router.get("/", response_model=list[ConversationResponse])
async def list_conversations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ConversationResponse]:
    return await conversation_service.list_conversations(db, current_user)


@router.post("/", response_model=ConversationResponse)
async def open_conversation(
    req: GetOrCreateConversationRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConversationResponse:
    """Get-or-create a 1-on-1 conversation with another user.

    Idempotent: re-posting the same `user_id` returns the same conversation.
    The other user must be in the caller's contacts (mirrors message-send rules).
    """
    return await conversation_service.open_conversation_with(
        db, current_user, req.user_id
    )


@router.get("/{conversation_id}/messages", response_model=MessagePage)
async def get_messages(
    conversation_id: UUID,
    cursor: str | None = Query(default=None),
    limit: int = Query(default=30, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> MessagePage:
    return await message_service.fetch_messages(
        db, current_user, conversation_id, cursor=cursor, limit=limit
    )

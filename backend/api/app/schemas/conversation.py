"""
Request schemas for /api/conversations.

The response schema (ConversationResponse) lives in schemas/message.py with
MessageResponse since they're tightly coupled — list_conversations embeds the
last message inline.
"""
from uuid import UUID

from pydantic import BaseModel


class GetOrCreateConversationRequest(BaseModel):
    """Body for POST /api/conversations/ — opens a chat with user_id."""
    user_id: UUID

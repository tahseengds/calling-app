"""
Schemas for /api/calls endpoints.

The Flutter client expects {items: [...], next_cursor: ...} for the history
listing — keep that envelope name (`items`) so the Dart side keeps working.
"""
from __future__ import annotations

import base64
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.schemas.user import UserPublic


CallTypeLiteral = Literal["audio", "video"]
CallDirectionLiteral = Literal["incoming", "outgoing"]


class CallRecordResponse(BaseModel):
    """One historical call from the current user's perspective.

    `direction` is computed relative to the requesting user: a call where they
    were the caller is "outgoing"; where they were the callee, "incoming".
    `other_user` is whichever participant is *not* the current user.
    """
    model_config = ConfigDict(from_attributes=False)

    id: UUID
    other_user: UserPublic
    call_type: CallTypeLiteral
    direction: CallDirectionLiteral
    status: str  # 'completed' | 'missed' | 'rejected' | 'failed' | 'busy'
    started_at: datetime
    duration_seconds: int | None


class CallHistoryPage(BaseModel):
    """Cursor-paginated page of call records (newest first)."""
    items: list[CallRecordResponse]
    next_cursor: str | None


class CallLogReplayRequest(BaseModel):
    """
    Client-side reconciliation of a call that ended without a hangup signal
    reaching the Node signaling service — e.g. the caller was force-killed
    mid-call, or the OS audio session was interrupted.

    Posted via POST /api/calls/log on next app launch (see Flutter's
    CallRepository.syncInterruptedCalls + stashInterruptedCall). Idempotent
    on call_id — the backend already may have recorded the call from another
    path (Node's hangup handler), so this insert uses ON CONFLICT DO NOTHING.
    """
    call_id: UUID
    peer_user_id: UUID
    call_type: CallTypeLiteral
    direction: CallDirectionLiteral
    started_at: datetime
    connected_at: datetime | None
    ended_at: datetime
    duration_seconds: int
    reason: str  # interrupted | forceKilled | failed | blocked


# ── Cursor helpers — created_at|id encoded base64 ────────────────────────────

def encode_cursor(ts: datetime, call_id: UUID) -> str:
    raw = f"{ts.isoformat()}|{call_id}"
    return base64.urlsafe_b64encode(raw.encode()).decode()


def decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    raw = base64.urlsafe_b64decode(cursor.encode()).decode()
    ts_str, id_str = raw.split("|", 1)
    return datetime.fromisoformat(ts_str), UUID(id_str)

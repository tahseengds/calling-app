"""
Call history queries.

Call records are written by the Node.js signalling service (call lifecycle
events); this module only reads them for the Flutter client.

Cursor pagination uses (started_at, id) so duplicate timestamps still page
deterministically. The current user's perspective decides whether each row is
"incoming" or "outgoing".
"""
from uuid import UUID

from sqlalchemy import and_, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.call_record import CallRecord
from app.models.user import User
from app.schemas.call import (
    CallHistoryPage,
    CallLogRequest,
    CallRecordResponse,
    decode_cursor,
    encode_cursor,
)
from app.schemas.user import UserPublic
from app.utils.exceptions import ValidationFailedError


# Map the client's EndReason name to a canonical call status. Anything not
# listed (e.g. "hungUp") resolves by whether the call actually connected.
_REASON_TO_STATUS = {
    "rejected": "rejected",
    "declined": "rejected",
    "busy": "busy",
    "missed": "missed",
    "timeout": "missed",
    "failed": "failed",
}


async def log_call(db: AsyncSession, user: User, req: CallLogRequest) -> None:
    """Idempotently persist a client-reported call.

    Mirrors the columns the Node.js signaling server writes and dedups on the
    call_id PK (ON CONFLICT DO NOTHING), so whichever side records the call
    first wins and the other is a harmless no-op.
    """
    # caller/callee from the reporter's perspective.
    if req.direction == "outgoing":
        caller_id, callee_id = user.id, req.peer_user_id
    else:
        caller_id, callee_id = req.peer_user_id, user.id

    status = _REASON_TO_STATUS.get(req.reason)
    if status is None:
        # hungUp / unknown: a connected call is "completed", otherwise "missed".
        status = "completed" if req.connected_at is not None else "missed"

    stmt = (
        pg_insert(CallRecord)
        .values(
            id=req.call_id,
            caller_id=caller_id,
            callee_id=callee_id,
            call_type=req.call_type,
            status=status,
            started_at=req.started_at,
            answered_at=req.connected_at,
            ended_at=req.ended_at,
            duration_seconds=req.duration_seconds,
        )
        .on_conflict_do_nothing(index_elements=["id"])
    )
    await db.execute(stmt)
    await db.commit()


async def list_call_history(
    db: AsyncSession,
    user: User,
    *,
    cursor: str | None = None,
    limit: int = 30,
) -> CallHistoryPage:
    """Return the user's most recent calls, newest first."""
    started_col = CallRecord.started_at
    # Fallback for in-progress / not-yet-started rows: use created_at instead
    # of started_at when started_at is NULL (sorting unstarted calls would
    # otherwise dump them all at the tail).
    order_ts = started_col

    stmt = (
        select(CallRecord)
        .where(
            or_(
                CallRecord.caller_id == user.id,
                CallRecord.callee_id == user.id,
            )
        )
    )

    if cursor is not None:
        # A bad cursor used to silently reset to page 1, masking client bugs
        # (e.g. the headline #4 fix). Now we reject it so the client knows.
        try:
            cursor_ts, cursor_id = decode_cursor(cursor)
        except Exception as exc:
            raise ValidationFailedError(
                "Invalid cursor — start a fresh page without one"
            ) from exc
        stmt = stmt.where(
            or_(
                order_ts < cursor_ts,
                and_(order_ts == cursor_ts, CallRecord.id < cursor_id),
            )
        )

    stmt = stmt.order_by(order_ts.desc(), CallRecord.id.desc()).limit(limit + 1)

    result = await db.execute(stmt)
    rows = list(result.scalars().all())

    has_more = len(rows) > limit
    rows = rows[:limit]

    # Batch-load every "other user" referenced by this page in one query.
    # Previously this did one SELECT per row — 100 rows = 100 round-trips.
    other_ids: set[UUID] = {
        r.callee_id if r.caller_id == user.id else r.caller_id
        for r in rows
    }
    users_by_id: dict[UUID, User] = {}
    if other_ids:
        users_r = await db.execute(
            select(User).where(User.id.in_(other_ids))
        )
        users_by_id = {u.id: u for u in users_r.scalars().all()}

    items: list[CallRecordResponse] = []
    for r in rows:
        other_id: UUID = r.callee_id if r.caller_id == user.id else r.caller_id
        other = users_by_id.get(other_id)
        if other is None:
            # User deleted — skip (don't 500 the whole page).
            continue
        direction = "outgoing" if r.caller_id == user.id else "incoming"
        items.append(
            CallRecordResponse(
                id=r.id,
                other_user=UserPublic.model_validate(other),
                call_type=r.call_type,  # type: ignore[arg-type]
                direction=direction,  # type: ignore[arg-type]
                status=r.status,
                started_at=r.started_at or r.created_at,
                duration_seconds=r.duration_seconds,
            )
        )

    next_cursor: str | None = None
    if has_more and rows:
        last = rows[-1]
        next_cursor = encode_cursor(last.started_at or last.created_at, last.id)

    return CallHistoryPage(items=items, next_cursor=next_cursor)

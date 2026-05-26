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
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.call_record import CallRecord
from app.models.user import User
from app.schemas.call import (
    CallHistoryPage,
    CallRecordResponse,
    decode_cursor,
    encode_cursor,
)
from app.schemas.user import UserPublic


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
        try:
            cursor_ts, cursor_id = decode_cursor(cursor)
        except Exception:
            cursor_ts, cursor_id = None, None  # type: ignore[assignment]
        if cursor_ts is not None:
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

    # Load the "other user" for each row — single round-trip per row is fine
    # at limit=30, and avoids an awkward conditional join. If history grows
    # huge we can switch to a batched IN-query.
    items: list[CallRecordResponse] = []
    for r in rows:
        other_id: UUID = r.callee_id if r.caller_id == user.id else r.caller_id
        other_r = await db.execute(select(User).where(User.id == other_id))
        other = other_r.scalar_one_or_none()
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

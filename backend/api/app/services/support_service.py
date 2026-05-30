from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.admin_audit_log import AdminAuditLog
from app.models.support_feedback import SupportFeedback
from app.models.user import User
from app.schemas.support import (
    SupportFeedbackRequest,
    SupportFeedbackResponse,
    SupportRequestAdmin,
    SupportRequestList,
)
from app.utils.exceptions import NotFoundError


async def submit_feedback(
    db: AsyncSession, user: User, req: SupportFeedbackRequest
) -> SupportFeedbackResponse:
    row = SupportFeedback(
        user_id=user.id,
        category=req.category,
        message=req.message.strip(),
        app_version=req.app_version,
        platform=req.platform,
        device_info=req.device_info or {},
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return SupportFeedbackResponse.model_validate(row)


async def list_requests(
    db: AsyncSession, limit: int = 200, offset: int = 0
) -> SupportRequestList:
    """
    Return support requests newest-first, joined with submitter name/email,
    plus the total count. For the admin views only.
    """
    total = await db.scalar(
        select(func.count()).select_from(SupportFeedback)
    )
    open_count = await db.scalar(
        select(func.count())
        .select_from(SupportFeedback)
        .where(SupportFeedback.status == "open")
    )

    # Open requests first, then by newest — so the work queue floats to the top.
    rows = (
        await db.execute(
            select(SupportFeedback, User.name, User.email)
            .join(User, User.id == SupportFeedback.user_id, isouter=True)
            .order_by(
                (SupportFeedback.status == "resolved"),
                SupportFeedback.created_at.desc(),
            )
            .limit(limit)
            .offset(offset)
        )
    ).all()

    requests = [
        SupportRequestAdmin(
            id=fb.id,
            user_id=fb.user_id,
            user_name=name,
            user_email=email,
            category=fb.category,
            message=fb.message,
            app_version=fb.app_version,
            platform=fb.platform,
            device_info=fb.device_info or {},
            status=fb.status,
            handled_by=fb.handled_by,
            resolved_at=fb.resolved_at,
            created_at=fb.created_at,
        )
        for fb, name, email in rows
    ]
    return SupportRequestList(
        total=total or 0, open_count=open_count or 0, requests=requests
    )


async def update_status(
    db: AsyncSession, request_id: UUID, status: str, admin_email: str
) -> SupportFeedback:
    """Set an admin triage status on one request. Stamps handled_by, and
    resolved_at when (and only when) the status becomes 'resolved'."""
    row = await db.get(SupportFeedback, request_id)
    if row is None:
        raise NotFoundError("Support request not found")

    previous_status = row.status
    row.status = status
    row.handled_by = admin_email
    row.resolved_at = (
        datetime.now(timezone.utc) if status == "resolved" else None
    )

    # Append-only audit trail: handled_by/resolved_at on the row only ever show
    # the *latest* change, so record each transition immutably for compliance.
    db.add(
        AdminAuditLog(
            admin_email=admin_email,
            action="support.status_change",
            target_type="support_feedback",
            target_id=request_id,
            detail={"from": previous_status, "to": status},
        )
    )

    await db.commit()
    await db.refresh(row)
    return row

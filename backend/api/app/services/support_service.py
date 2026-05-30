from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.support_feedback import SupportFeedback
from app.models.user import User
from app.schemas.support import (
    SupportFeedbackRequest,
    SupportFeedbackResponse,
    SupportRequestAdmin,
    SupportRequestList,
)


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

    rows = (
        await db.execute(
            select(SupportFeedback, User.name, User.email)
            .join(User, User.id == SupportFeedback.user_id, isouter=True)
            .order_by(SupportFeedback.created_at.desc())
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
            created_at=fb.created_at,
        )
        for fb, name, email in rows
    ]
    return SupportRequestList(total=total or 0, requests=requests)

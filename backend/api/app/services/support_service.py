from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.support_feedback import SupportFeedback
from app.models.user import User
from app.schemas.support import SupportFeedbackRequest, SupportFeedbackResponse


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

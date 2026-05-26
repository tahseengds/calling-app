from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_current_user, get_db
from app.models.user import User
from app.schemas.settings import NotificationPreferences, PrivacySettings
from app.services import settings_service

router = APIRouter()


# ── Notification preferences ─────────────────────────────────────────────

@router.get("/notifications", response_model=NotificationPreferences)
async def get_notifications(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NotificationPreferences:
    return await settings_service.get_notification_preferences(db, current_user)


@router.put("/notifications", response_model=NotificationPreferences)
async def update_notifications(
    req: NotificationPreferences,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NotificationPreferences:
    return await settings_service.update_notification_preferences(
        db, current_user, req
    )


# ── Privacy settings ─────────────────────────────────────────────────────

@router.get("/privacy", response_model=PrivacySettings)
async def get_privacy(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PrivacySettings:
    return await settings_service.get_privacy_settings(db, current_user)


@router.put("/privacy", response_model=PrivacySettings)
async def update_privacy(
    req: PrivacySettings,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PrivacySettings:
    return await settings_service.update_privacy_settings(db, current_user, req)

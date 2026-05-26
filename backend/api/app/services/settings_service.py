"""Per-user notification + privacy settings.

The two JSONB columns on `users` are merged with the Pydantic defaults
on every read so that older rows (or partial writes from older clients)
always validate. Writes are a full replace — clients send the complete
shape.
"""
from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import flag_modified

from app.models.user import User
from app.schemas.settings import NotificationPreferences, PrivacySettings


# ── Notification preferences ─────────────────────────────────────────────

def _merge_notifications(raw: dict | None) -> NotificationPreferences:
    return NotificationPreferences.model_validate(raw or {})


async def get_notification_preferences(
    db: AsyncSession, user: User
) -> NotificationPreferences:
    return _merge_notifications(user.notification_preferences)


async def update_notification_preferences(
    db: AsyncSession, user: User, req: NotificationPreferences
) -> NotificationPreferences:
    user.notification_preferences = req.model_dump(mode="json")
    flag_modified(user, "notification_preferences")
    await db.commit()
    return _merge_notifications(user.notification_preferences)


# ── Privacy settings ─────────────────────────────────────────────────────

def _merge_privacy(raw: dict | None) -> PrivacySettings:
    return PrivacySettings.model_validate(raw or {})


async def get_privacy_settings(db: AsyncSession, user: User) -> PrivacySettings:
    return _merge_privacy(user.privacy_settings)


async def update_privacy_settings(
    db: AsyncSession, user: User, req: PrivacySettings
) -> PrivacySettings:
    user.privacy_settings = req.model_dump(mode="json")
    flag_modified(user, "privacy_settings")
    await db.commit()
    return _merge_privacy(user.privacy_settings)


# ── Push-gating helper ───────────────────────────────────────────────────

def should_send_push(user: User, kind: str) -> bool:
    """
    Returns False when a push of [kind] should be suppressed for [user]
    based on their saved notification_preferences.

    [kind] ∈ {"message", "group_message", "call", "reaction", "mention"}.
    Quiet hours downgrade priority elsewhere — this helper only returns
    a hard yes/no.
    """
    prefs = _merge_notifications(user.notification_preferences)
    return {
        "message": prefs.messages_enabled,
        "group_message": prefs.group_messages_enabled,
        "call": prefs.calls_enabled,
        "reaction": prefs.reaction_notifications,
        "mention": prefs.mention_notifications,
    }.get(kind, True)

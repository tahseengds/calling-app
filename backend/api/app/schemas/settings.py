"""User-settings schemas — typed Pydantic envelopes around the two
free-form JSONB columns on `users` (`notification_preferences`,
`privacy_settings`). The Flutter app and backend both speak these shapes.
"""
from __future__ import annotations

import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

# ── Allowed enums (kept open Literals so callers can validate cheaply) ───
VisibilityLevel = Literal["everyone", "contacts", "nobody"]
OnlineVisibility = Literal["everyone", "same_as_last_seen"]
GroupsWhoCanAdd = Literal["everyone", "contacts"]

_HHMM = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


class NotificationPreferences(BaseModel):
    """All per-user push/local notification toggles."""

    model_config = ConfigDict(extra="ignore")

    # Channels
    messages_enabled: bool = True
    group_messages_enabled: bool = True
    calls_enabled: bool = True
    reaction_notifications: bool = True
    mention_notifications: bool = True

    # Behaviour
    show_preview: bool = True  # show message body on lock screen
    vibrate: bool = True
    high_priority_notifications: bool = True  # heads-up on Android

    # Sounds (asset id, or one of the special tokens below)
    message_sound: str = "system_default"
    call_ringtone: str = "system_default"

    # Quiet hours (24h "HH:MM")
    quiet_hours_enabled: bool = False
    quiet_hours_start: str = "22:00"
    quiet_hours_end: str = "07:00"

    @field_validator("quiet_hours_start", "quiet_hours_end")
    @classmethod
    def _validate_hhmm(cls, v: str) -> str:
        if not _HHMM.match(v):
            raise ValueError("Time must be 'HH:MM' in 24h format")
        return v

    @field_validator("message_sound", "call_ringtone")
    @classmethod
    def _validate_sound(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("sound id must be non-empty")
        if len(v) > 64:
            raise ValueError("sound id must be ≤ 64 chars")
        return v


class PrivacySettings(BaseModel):
    """All per-user privacy/visibility controls."""

    model_config = ConfigDict(extra="ignore")

    last_seen_visibility: VisibilityLevel = "everyone"
    profile_photo_visibility: VisibilityLevel = "everyone"
    about_visibility: VisibilityLevel = "everyone"
    online_status_visibility: OnlineVisibility = "everyone"
    groups_who_can_add: GroupsWhoCanAdd = "everyone"

    read_receipts: bool = True
    calls_silence_unknown: bool = False

    # App-lock flag is mirrored from the device; the actual secret never leaves.
    app_lock_enabled: bool = False
    app_lock_auto_lock_minutes: int = Field(default=0, ge=0, le=1440)

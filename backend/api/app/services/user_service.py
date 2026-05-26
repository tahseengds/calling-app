"""User profile management."""
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.contact import Contact
from app.models.user import User
from app.schemas.user import FcmTokenRequest, UpdateProfileRequest, UserMe, UserPublic
from app.utils.exceptions import NotFoundError


async def get_me(db: AsyncSession, user: User) -> UserMe:
    return UserMe.model_validate(user)


async def update_profile(
    db: AsyncSession, user: User, req: UpdateProfileRequest
) -> UserMe:
    if req.name is not None:
        user.name = req.name.strip()
    await db.commit()
    return UserMe.model_validate(user)


async def get_user(
    db: AsyncSession, caller: User, user_id: UUID
) -> UserPublic:
    """
    Look up a user by UUID. Only contacts may resolve full profiles —
    non-contacts get a 404 so the endpoint can't be used to enumerate
    email / last_seen for arbitrary users.

    Looking up oneself is always permitted.
    """
    if user_id == caller.id:
        return UserPublic.model_validate(caller)

    contact_r = await db.execute(
        select(Contact.id).where(
            Contact.user_id == caller.id,
            Contact.contact_user_id == user_id,
        )
    )
    if contact_r.scalar_one_or_none() is None:
        # Don't leak existence. 404 covers both "no such user" and
        # "not in your contacts".
        raise NotFoundError("User not found")

    result = await db.execute(
        select(User).where(User.id == user_id, User.is_active.is_(True))
    )
    target = result.scalar_one_or_none()
    if not target:
        raise NotFoundError("User not found")
    return UserPublic.model_validate(target)


async def update_fcm_token(
    db: AsyncSession, user: User, req: FcmTokenRequest
) -> None:
    """
    Register an FCM token for this user/device pair.
    FCM tokens are device-unique: if the same token is already registered to a
    different user (e.g. after a device hand-off), clear it from the old user first.
    """
    result = await db.execute(
        select(User).where(User.fcm_token == req.fcm_token, User.id != user.id)
    )
    other = result.scalar_one_or_none()
    if other:
        other.fcm_token = None
        other.fcm_token_updated_at = datetime.now(timezone.utc)

    user.fcm_token = req.fcm_token
    user.fcm_token_updated_at = datetime.now(timezone.utc)
    await db.commit()


async def upload_avatar(
    db: AsyncSession,
    user: User,
    upload,  # fastapi.UploadFile
) -> UserMe:
    """Process an avatar upload and update the user's avatar_url."""
    from app.services.media_service import upload_avatar as _process_avatar
    avatar_url = await _process_avatar(db, user, upload)
    user.avatar_url = avatar_url
    await db.commit()
    return UserMe.model_validate(user)

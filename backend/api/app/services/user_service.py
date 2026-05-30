"""User profile management."""
import logging
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import delete, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.contact import Contact
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.schemas.user import FcmTokenRequest, UpdateProfileRequest, UserMe, UserPublic
from app.utils.exceptions import NotFoundError

logger = logging.getLogger(__name__)


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
        # Device handed off to a new account — the previous owner stops getting
        # pushes. Log it so a support diagnosis isn't a mystery ("why did my
        # notifications stop?") and so token-theft patterns are visible.
        logger.info(
            "FCM token reassigned from user %s to user %s", other.id, user.id
        )
        other.fcm_token = None
        other.fcm_token_updated_at = datetime.now(timezone.utc)

    user.fcm_token = req.fcm_token
    user.fcm_token_updated_at = datetime.now(timezone.utc)
    await db.commit()


async def delete_account(db: AsyncSession, user: User) -> None:
    """
    Erase the caller's account (GDPR / store-policy right-to-erasure).

    We anonymize in place rather than hard-deleting the row so foreign keys
    from messages, conversations, and call records stay intact (other
    participants keep their own chat history), while every piece of personal
    data tied to this user is scrubbed:

      - revoke all refresh tokens (kills every active session on every device)
      - clear the FCM token (stops push notifications)
      - null out email / firebase_uid (severs the identity link and frees both
        for reuse) and the password hash
      - replace display name + avatar with a neutral tombstone
      - wipe notification/privacy preference blobs
      - deactivate the account so it can never authenticate again

    Existing 15-minute access tokens stop working immediately because
    get_current_user rejects inactive users. Contact rows on both sides are
    removed so the account disappears from everyone's address book.
    """
    now = datetime.now(timezone.utc)

    # Revoke every still-active refresh token for this user.
    await db.execute(
        update(RefreshToken)
        .where(
            RefreshToken.user_id == user.id,
            RefreshToken.revoked_at.is_(None),
        )
        .values(revoked_at=now)
    )

    # Remove contact rows pointing at — or owned by — this user, both directions.
    await db.execute(
        delete(Contact).where(
            or_(
                Contact.user_id == user.id,
                Contact.contact_user_id == user.id,
            )
        )
    )

    # Anonymize the user row.
    user.name = "Deleted user"
    user.email = None
    user.firebase_uid = None
    user.auth_provider = None
    user.avatar_url = None
    user.password_hash = None
    user.fcm_token = None
    user.fcm_token_updated_at = now
    user.notification_preferences = {}
    user.privacy_settings = {}
    user.is_active = False

    await db.commit()
    logger.info("Account erased (anonymized) for user %s", user.id)


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

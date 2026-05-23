"""
Contact management.

Design decisions:
  - add_contact is RECIPROCAL: adding a family member creates both the
    forward and reverse contact rows automatically. For a private family app,
    mutual visibility is the expected behaviour.
  - remove_contact is ONE-DIRECTIONAL: removing someone from your list does
    not remove you from theirs. This lets users manage their own view without
    affecting others unexpectedly.
"""
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.contact import Contact
from app.models.user import User
from app.schemas.contact import AddContactRequest, ContactResponse
from app.schemas.user import UserPublic
from app.utils.exceptions import NotFoundError, ValidationFailedError


def _to_response(contact: Contact) -> ContactResponse:
    return ContactResponse(
        id=contact.id,
        contact_user=UserPublic.model_validate(contact.contact_user),
        nickname=contact.nickname,
        is_blocked=contact.is_blocked,
        created_at=contact.created_at,
    )


async def _load_contact(
    db: AsyncSession, contact_id: UUID, user_id: UUID
) -> Contact:
    result = await db.execute(
        select(Contact)
        .where(Contact.id == contact_id, Contact.user_id == user_id)
        .options(selectinload(Contact.contact_user))
    )
    contact = result.scalar_one_or_none()
    if not contact:
        raise NotFoundError("Contact not found")
    return contact


async def add_contact(
    db: AsyncSession, user: User, req: AddContactRequest
) -> ContactResponse:
    # Resolve target by phone
    result = await db.execute(
        select(User).where(User.phone == req.phone, User.is_active.is_(True))
    )
    target = result.scalar_one_or_none()
    if not target:
        raise NotFoundError("No active user with that phone number")

    if target.id == user.id:
        raise ValidationFailedError("You cannot add yourself as a contact")

    # Return existing contact if already present
    result = await db.execute(
        select(Contact)
        .where(Contact.user_id == user.id, Contact.contact_user_id == target.id)
        .options(selectinload(Contact.contact_user))
    )
    existing = result.scalar_one_or_none()
    if existing:
        return _to_response(existing)

    # Create forward contact
    forward = Contact(
        user_id=user.id,
        contact_user_id=target.id,
        nickname=req.nickname,
    )
    db.add(forward)

    # Create reciprocal contact if it doesn't exist
    result = await db.execute(
        select(Contact).where(
            Contact.user_id == target.id, Contact.contact_user_id == user.id
        )
    )
    if not result.scalar_one_or_none():
        reverse = Contact(
            user_id=target.id,
            contact_user_id=user.id,
            nickname=None,
        )
        db.add(reverse)

    await db.commit()

    # Reload forward contact with relationship
    result = await db.execute(
        select(Contact)
        .where(Contact.id == forward.id)
        .options(selectinload(Contact.contact_user))
    )
    return _to_response(result.scalar_one())


async def list_contacts(db: AsyncSession, user: User) -> list[ContactResponse]:
    result = await db.execute(
        select(Contact)
        .where(Contact.user_id == user.id)
        .options(selectinload(Contact.contact_user))
        .order_by(Contact.nickname.nulls_last(), Contact.created_at)
    )
    return [_to_response(c) for c in result.scalars().all()]


async def remove_contact(
    db: AsyncSession, user: User, contact_id: UUID
) -> None:
    """
    One-directional removal: removes the contact from the caller's list only.
    The other party's contact row is unaffected.
    """
    contact = await _load_contact(db, contact_id, user.id)
    await db.delete(contact)
    await db.commit()


async def set_blocked(
    db: AsyncSession, user: User, contact_id: UUID, blocked: bool
) -> ContactResponse:
    contact = await _load_contact(db, contact_id, user.id)
    contact.is_blocked = blocked
    await db.commit()
    return _to_response(contact)

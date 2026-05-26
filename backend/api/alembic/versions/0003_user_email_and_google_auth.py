"""Add email / firebase_uid / auth_provider to users, drop phone NOT NULL.

Revision ID: 0003
Revises: 0002
Create Date: 2026-05-26

The auth flow moved from Firebase Phone (SMS OTP) to Firebase Google
Sign-In + Email/Password (with built-in email-link verification). The
stable identifier for a user is now their Firebase UID; email is the
display/lookup field; phone becomes optional.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Phone is now optional.
    op.alter_column("users", "phone", existing_type=sa.String(20), nullable=True)

    op.add_column(
        "users",
        sa.Column("email", sa.String(254), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("firebase_uid", sa.String(128), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("auth_provider", sa.String(32), nullable=True),
    )

    op.create_unique_constraint("uq_users_email", "users", ["email"])
    op.create_unique_constraint("uq_users_firebase_uid", "users", ["firebase_uid"])
    op.create_index("ix_users_email", "users", ["email"])
    op.create_index("ix_users_firebase_uid", "users", ["firebase_uid"])


def downgrade() -> None:
    op.drop_index("ix_users_firebase_uid", table_name="users")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_constraint("uq_users_firebase_uid", "users", type_="unique")
    op.drop_constraint("uq_users_email", "users", type_="unique")
    op.drop_column("users", "auth_provider")
    op.drop_column("users", "firebase_uid")
    op.drop_column("users", "email")
    op.alter_column("users", "phone", existing_type=sa.String(20), nullable=False)

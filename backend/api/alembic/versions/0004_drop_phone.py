"""Drop the users.phone column.

Revision ID: 0004
Revises: 0003
Create Date: 2026-05-27

Phone-based identity was retired entirely. The new auth flow runs on
Firebase (Google + email/password) with email as the lookup field, so
phone has no remaining consumers in the app or backend.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0004"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 0001 created the unique constraint inline via UniqueConstraint("phone"),
    # which Postgres named uq_users_phone (matches SQLA's default). Drop the
    # constraint before the column so the column drop succeeds.
    op.drop_constraint("users_phone_key", "users", type_="unique")
    op.drop_column("users", "phone")


def downgrade() -> None:
    op.add_column(
        "users",
        sa.Column("phone", sa.String(20), nullable=True),
    )
    op.create_unique_constraint("users_phone_key", "users", ["phone"])

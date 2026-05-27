"""Add message_reactions table.

Revision ID: 0005
Revises: 0004
Create Date: 2026-05-27

One row per (message, user, emoji). The triple is unique — a user can put
multiple distinct emojis on the same message, but the same emoji once.
ON DELETE CASCADE on message_id so soft-deleted/hard-deleted messages drop
their reactions automatically.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from alembic import op

revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "message_reactions",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "message_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("messages.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("emoji", sa.String(32), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.UniqueConstraint(
            "message_id", "user_id", "emoji", name="uq_message_reactions_triple"
        ),
    )
    # Hot read path: "give me all reactions for this message".
    op.create_index(
        "ix_message_reactions_message_id",
        "message_reactions",
        ["message_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_message_reactions_message_id", table_name="message_reactions")
    op.drop_table("message_reactions")

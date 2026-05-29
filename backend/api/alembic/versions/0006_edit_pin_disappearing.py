"""Add edit/pin/disappearing columns to messages and conversations.

Revision ID: 0006
Revises: 0005
Create Date: 2026-05-29

Stage-2 chat features:
  - messages.edited_at   — set when a text message is edited
  - messages.pinned_at   — non-null while a message is pinned
  - messages.expires_at  — disappearing-message expiry (indexed for cleanup)
  - conversations.disappearing_seconds — per-conversation TTL (NULL = off)
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0006"
down_revision: Union[str, None] = "0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "messages",
        sa.Column("edited_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "messages",
        sa.Column("pinned_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "messages",
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "conversations",
        sa.Column("disappearing_seconds", sa.Integer(), nullable=True),
    )
    # Cleanup path: "find messages whose TTL has passed".
    op.create_index("ix_messages_expires_at", "messages", ["expires_at"])


def downgrade() -> None:
    op.drop_index("ix_messages_expires_at", table_name="messages")
    op.drop_column("conversations", "disappearing_seconds")
    op.drop_column("messages", "expires_at")
    op.drop_column("messages", "pinned_at")
    op.drop_column("messages", "edited_at")

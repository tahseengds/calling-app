"""initial schema

Revision ID: 0001
Revises:
Create Date: 2026-05-21

"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from alembic import op

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute('CREATE EXTENSION IF NOT EXISTS "pgcrypto"')

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("phone", sa.String(20), nullable=False),
        sa.Column("avatar_url", sa.Text),
        sa.Column("fcm_token", sa.Text),
        sa.Column("fcm_token_updated_at", sa.DateTime(timezone=True)),
        sa.Column("password_hash", sa.Text),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("last_seen", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.UniqueConstraint("phone"),
    )

    op.create_table(
        "contacts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("contact_user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("nickname", sa.String(100)),
        sa.Column("is_blocked", sa.Boolean, nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.UniqueConstraint("user_id", "contact_user_id"),
    )

    op.create_table(
        "conversations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("participant_a", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("participant_b", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        # No FK — avoids circular dependency with messages
        sa.Column("last_message_id", postgresql.UUID(as_uuid=True)),
        sa.Column("last_activity", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.UniqueConstraint("participant_a", "participant_b"),
    )

    op.create_table(
        "media_files",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("uploader_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("file_type", sa.String(20), nullable=False),
        sa.Column("original_name", sa.String(255)),
        sa.Column("stored_name", sa.String(255)),
        sa.Column("mime_type", sa.String(100)),
        sa.Column("file_size", sa.BigInteger),
        sa.Column("duration_seconds", sa.Integer),
        sa.Column("thumbnail_stored_name", sa.String(255)),
        sa.Column("width", sa.Integer),
        sa.Column("height", sa.Integer),
        sa.Column("storage_path", sa.Text),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("expires_at", sa.DateTime(timezone=True)),
    )

    op.create_table(
        "messages",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("conversation_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False),
        sa.Column("sender_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("message_type", sa.String(20), nullable=False),
        sa.Column("content", sa.Text),
        sa.Column("media_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("media_files.id")),
        sa.Column("reply_to_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("messages.id")),
        sa.Column("status", sa.String(20), nullable=False, server_default=sa.text("'sent'")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True)),
        sa.Column("deleted_at", sa.DateTime(timezone=True)),
    )

    op.create_table(
        "message_receipts",
        sa.Column("message_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("messages.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("delivered_at", sa.DateTime(timezone=True)),
        sa.Column("read_at", sa.DateTime(timezone=True)),
    )

    op.create_table(
        "call_records",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("caller_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("callee_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id"), nullable=False),
        sa.Column("call_type", sa.String(10), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True)),
        sa.Column("answered_at", sa.DateTime(timezone=True)),
        sa.Column("ended_at", sa.DateTime(timezone=True)),
        sa.Column("duration_seconds", sa.Integer),
        sa.Column("conversation_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("conversations.id")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
    )

    op.create_table(
        "refresh_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.Text, nullable=False, unique=True),
        sa.Column("device_id", sa.String(255)),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("now()")),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
    )

    # Indexes
    op.create_index("idx_messages_conversation", "messages",
                    ["conversation_id", sa.text("created_at DESC")])
    op.create_index("idx_messages_sender", "messages",
                    ["sender_id", sa.text("created_at DESC")])
    op.create_index("idx_calls_participants", "call_records",
                    ["caller_id", "callee_id", sa.text("created_at DESC")])
    op.create_index("idx_contacts_user", "contacts", ["user_id"])
    op.create_index("idx_refresh_tokens_user", "refresh_tokens", ["user_id"])


def downgrade() -> None:
    op.drop_index("idx_refresh_tokens_user", table_name="refresh_tokens")
    op.drop_index("idx_contacts_user", table_name="contacts")
    op.drop_index("idx_calls_participants", table_name="call_records")
    op.drop_index("idx_messages_sender", table_name="messages")
    op.drop_index("idx_messages_conversation", table_name="messages")

    op.drop_table("refresh_tokens")
    op.drop_table("call_records")
    op.drop_table("message_receipts")
    op.drop_table("messages")
    op.drop_table("media_files")
    op.drop_table("conversations")
    op.drop_table("contacts")
    op.drop_table("users")

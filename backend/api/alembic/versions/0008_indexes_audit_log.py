"""Performance indexes, self-contact guard, and admin audit log.

Revision ID: 0008
Revises: 0007
Create Date: 2026-05-30

Three independent hardening changes:
  - Indexes on hot lookup columns that were previously unindexed:
      users.fcm_token                      — reverse lookup on device handoff
      message_receipts(user_id, read_at)   — per-user unread-count aggregation
      conversations.last_activity          — conversation list ordering
  - A CHECK constraint preventing a contact row from pointing at its owner
    (already enforced in app code; this makes it a DB invariant).
  - The admin_audit_log table — an append-only trail of privileged actions
    (support triage status changes today).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0008"
down_revision: Union[str, None] = "0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── Indexes ──────────────────────────────────────────────────────────────
    op.create_index(
        "ix_users_fcm_token", "users", ["fcm_token"]
    )
    op.create_index(
        "ix_message_receipts_user_read",
        "message_receipts",
        ["user_id", "read_at"],
    )
    op.create_index(
        "ix_conversations_last_activity",
        "conversations",
        [sa.text("last_activity DESC")],
    )

    # ── Self-contact guard ───────────────────────────────────────────────────
    op.create_check_constraint(
        "chk_contacts_not_self",
        "contacts",
        "user_id <> contact_user_id",
    )

    # ── Admin audit log ──────────────────────────────────────────────────────
    op.create_table(
        "admin_audit_log",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("admin_email", sa.String(254), nullable=False),
        sa.Column("action", sa.String(64), nullable=False),
        sa.Column("target_type", sa.String(64)),
        sa.Column("target_id", postgresql.UUID(as_uuid=True)),
        sa.Column(
            "detail",
            postgresql.JSONB,
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index(
        "ix_admin_audit_log_target",
        "admin_audit_log",
        ["target_type", "target_id"],
    )
    op.create_index(
        "ix_admin_audit_log_created_at",
        "admin_audit_log",
        ["created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_admin_audit_log_created_at", table_name="admin_audit_log")
    op.drop_index("ix_admin_audit_log_target", table_name="admin_audit_log")
    op.drop_table("admin_audit_log")

    op.drop_constraint("chk_contacts_not_self", "contacts", type_="check")

    op.drop_index("ix_conversations_last_activity", table_name="conversations")
    op.drop_index("ix_message_receipts_user_read", table_name="message_receipts")
    op.drop_index("ix_users_fcm_token", table_name="users")

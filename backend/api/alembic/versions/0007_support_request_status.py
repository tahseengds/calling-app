"""Add admin triage status to support_feedback.

Revision ID: 0007
Revises: 0006
Create Date: 2026-05-30

Lets admins move a support request through open → in_progress → resolved,
recording who handled it and when it was resolved.
  - support_feedback.status       — 'open' | 'in_progress' | 'resolved'
  - support_feedback.handled_by   — email of the admin who last changed status
  - support_feedback.resolved_at  — set when status becomes 'resolved'
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0007"
down_revision: Union[str, None] = "0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "support_feedback",
        sa.Column(
            "status",
            sa.String(16),
            nullable=False,
            server_default="open",
        ),
    )
    op.add_column(
        "support_feedback",
        sa.Column("handled_by", sa.String(254), nullable=True),
    )
    op.add_column(
        "support_feedback",
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
    )
    # Common admin filter: "show me the open ones first".
    op.create_index(
        "ix_support_feedback_status", "support_feedback", ["status"]
    )


def downgrade() -> None:
    op.drop_index("ix_support_feedback_status", table_name="support_feedback")
    op.drop_column("support_feedback", "resolved_at")
    op.drop_column("support_feedback", "handled_by")
    op.drop_column("support_feedback", "status")

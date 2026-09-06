"""add device / usage_logs / quota_transactions

Whimread AI 托管：设备匿名账户、LLM 用量审计、额度流水账本。
表结构跨 SQLite/PostgreSQL 可移植（无 PG 专有类型），测试用内存库可直接建表。

Revision ID: 20260906_device_quota
Revises: 20260708_drop_cache_tables
Create Date: 2026-09-06
"""

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "20260906_device_quota"
down_revision = "20260708_drop_cache_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "devices",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("android_id_hash", sa.String(length=64), nullable=False),
        sa.Column("platform", sa.String(length=20), nullable=False, server_default="android"),
        sa.Column("app_version", sa.String(length=32), nullable=True),
        sa.Column("attestation_verified", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("attestation_security_level", sa.String(length=32), nullable=True),
        sa.Column("quota_balance", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="active"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("last_active_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_devices_id", "devices", ["id"], unique=False)
    op.create_index(
        "ix_devices_android_id_hash", "devices", ["android_id_hash"], unique=True
    )
    op.create_index("ix_devices_status", "devices", ["status"], unique=False)
    op.create_index(
        "idx_devices_status_created", "devices", ["status", "created_at"], unique=False
    )

    op.create_table(
        "usage_logs",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("device_id", sa.Integer(), nullable=False),
        sa.Column(
            "endpoint", sa.String(length=64), nullable=False, server_default="/v1/chat/completions"
        ),
        sa.Column("model", sa.String(length=128), nullable=False, server_default=""),
        sa.Column("prompt_tokens", sa.Integer(), nullable=True),
        sa.Column("completion_tokens", sa.Integer(), nullable=True),
        sa.Column("quota_cost", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("error", sa.String(length=512), nullable=True),
        sa.Column("latency_ms", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["device_id"], ["devices.id"], name="usage_logs_device_id_fkey", ondelete="CASCADE"
        ),
    )
    op.create_index("ix_usage_logs_id", "usage_logs", ["id"], unique=False)
    op.create_index("ix_usage_logs_device_id", "usage_logs", ["device_id"], unique=False)
    op.create_index("ix_usage_logs_status", "usage_logs", ["status"], unique=False)
    op.create_index(
        "idx_usage_device_created", "usage_logs", ["device_id", "created_at"], unique=False
    )
    op.create_index(
        "idx_usage_status_created", "usage_logs", ["status", "created_at"], unique=False
    )

    op.create_table(
        "quota_transactions",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("device_id", sa.Integer(), nullable=False),
        sa.Column("delta", sa.Integer(), nullable=False),
        sa.Column("reason", sa.String(length=32), nullable=False),
        sa.Column("balance_after", sa.Integer(), nullable=False),
        sa.Column("ref", sa.String(length=128), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["device_id"],
            ["devices.id"],
            name="quota_transactions_device_id_fkey",
            ondelete="CASCADE",
        ),
    )
    op.create_index(
        "ix_quota_transactions_id", "quota_transactions", ["id"], unique=False
    )
    op.create_index(
        "ix_quota_transactions_device_id", "quota_transactions", ["device_id"], unique=False
    )
    op.create_index(
        "ix_quota_transactions_reason", "quota_transactions", ["reason"], unique=False
    )
    op.create_index(
        "idx_quota_tx_device_created",
        "quota_transactions",
        ["device_id", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_table("quota_transactions")
    op.drop_table("usage_logs")
    op.drop_table("devices")

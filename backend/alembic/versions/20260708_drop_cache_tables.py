"""drop_cache_tables: drop novel_cache_tasks / novel_chapters_cache / chapter_list_cache

移除爬虫与章节缓存功能后，这三张表已无任何代码引用。drop 顺序：
1. novel_chapters_cache（子表，对 novel_cache_tasks 有 FK，ondelete CASCADE）
2. novel_cache_tasks（父表）
3. chapter_list_cache（独立表）

Revision ID: 20260708_drop_cache_tables
Revises: 20260707_add_negative_prompt
Create Date: 2026-07-08
"""

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "20260708_drop_cache_tables"
down_revision = "20260707_add_negative_prompt"
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    """守卫：遗留漂移操作仅对真实存在旧表的存量库执行。

    全新数据库（从未有过爬虫/缓存时代的表）直接跳过，
    使 `alembic upgrade head` 可从零跑通（2026-09-06 修复）。
    """
    from sqlalchemy import inspect
    return inspect(op.get_bind()).has_table(name)


def upgrade() -> None:
    """删除爬虫/缓存专用表，顺序：子表 → 父表 → 独立表（存在才删）。"""
    for table in ("novel_chapters_cache", "novel_cache_tasks", "chapter_list_cache"):
        if _has_table(table):
            op.drop_table(table)


def downgrade() -> None:
    """重建三张表的空结构（不恢复数据；only for alembic 完整性检查）。

    注意：downgrade 不会恢复任何已删除数据，仅为 alembic 历史链完整。
    """
    op.create_table(
        "novel_cache_tasks",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("novel_url", sa.Text(), nullable=False),
        sa.Column("site_id", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("total_chapters", sa.Integer(), nullable=True),
        sa.Column("cached_chapters", sa.Integer(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index(
        op.f("ix_novel_cache_tasks_id"), "novel_cache_tasks", ["id"], unique=False
    )
    op.create_index(
        op.f("ix_novel_cache_tasks_novel_url"),
        "novel_cache_tasks",
        ["novel_url"],
        unique=False,
    )
    op.create_index(
        op.f("ix_novel_cache_tasks_status"),
        "novel_cache_tasks",
        ["status"],
        unique=False,
    )

    op.create_table(
        "novel_chapters_cache",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("novel_url", sa.Text(), nullable=False),
        sa.Column("task_id", sa.String(length=64), nullable=True),
        sa.Column("chapter_index", sa.Integer(), nullable=False),
        sa.Column("chapter_title", sa.Text(), nullable=True),
        sa.Column("chapter_url", sa.Text(), nullable=False),
        sa.Column("content", sa.Text(), nullable=True),
        sa.Column("content_hash", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["task_id"],
            ["novel_cache_tasks.id"],
            name="novel_chapters_cache_task_id_fkey",
            ondelete="CASCADE",
        ),
    )
    op.create_index(
        op.f("ix_novel_chapters_cache_id"),
        "novel_chapters_cache",
        ["id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_novel_chapters_cache_novel_url"),
        "novel_chapters_cache",
        ["novel_url"],
        unique=False,
    )
    op.create_index(
        op.f("ix_novel_chapters_cache_task_id"),
        "novel_chapters_cache",
        ["task_id"],
        unique=False,
    )

    op.create_table(
        "chapter_list_cache",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("novel_url", sa.Text(), nullable=False),
        sa.Column("chapters", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index(
        op.f("ix_chapter_list_cache_id"),
        "chapter_list_cache",
        ["id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_chapter_list_cache_novel_url"),
        "chapter_list_cache",
        ["novel_url"],
        unique=False,
    )

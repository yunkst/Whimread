"""update_user_input_field_in_role_card_tasks

Revision ID: e7b3ba19a7f3
Revises: 1cf2c108acc1
Create Date: 2025-12-17 02:51:07.728544

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'e7b3ba19a7f3'
down_revision = '1cf2c108acc1'
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
    if not _has_table('role_card_tasks'):
        # 全新库：目标遗留表从未存在，跳过本迁移的漂移操作
        return
    # 将 user_input 字段设为可选，并设置默认值
    op.alter_column('role_card_tasks', 'user_input',
                    existing_type=sa.Text(),
                    nullable=True,
                    server_default='生成人物卡')


def downgrade() -> None:
    # 恢复 user_input 字段为必填
    op.alter_column('role_card_tasks', 'user_input',
                    existing_type=sa.Text(),
                    nullable=False,
                    server_default=None)
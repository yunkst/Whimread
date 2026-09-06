"""add video_comfyui_task_id field

Revision ID: 20241230_video_task_id
Revises: 20241228_comfyui_map
Create Date: 2024-12-30 14:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.sql import table, column

# revision identifiers, used by Alembic.
revision = '20241230_video_task_id'
down_revision = '20241228_comfyui_map'
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    """守卫：遗留漂移操作仅对真实存在旧表的存量库执行。

    全新数据库（从未有过爬虫/缓存时代的表）直接跳过，
    使 `alembic upgrade head` 可从零跑通（2026-09-06 修复）。
    """
    from sqlalchemy import inspect
    return inspect(op.get_bind()).has_table(name)


def upgrade():
    if not _has_table('image_video_status'):
        # 全新库：目标遗留表从未存在，跳过本迁移的漂移操作
        return
    """添加 video_comfyui_task_id 字段到 image_video_status 表"""

    # 添加新字段
    op.add_column(
        'image_video_status',
        sa.Column('video_comfyui_task_id', sa.String(length=255), nullable=True, comment='ComfyUI视频生成任务ID')
    )

    # 迁移现有数据：从 error_message 中提取 comfyui_task_id
    # 使用 text() 包装SQL字符串
    from sqlalchemy import text

    connection = op.get_bind()
    connection.execute(text("""
        UPDATE image_video_status
        SET video_comfyui_task_id = SUBSTRING(error_message FROM 'comfyui_task_id:(.*)')
        WHERE error_message LIKE 'comfyui_task_id:%'
    """))

    # 清理已迁移的 error_message
    connection.execute(text("""
        UPDATE image_video_status
        SET error_message = NULL
        WHERE error_message LIKE 'comfyui_task_id:%' AND video_comfyui_task_id IS NOT NULL
    """))


def downgrade():
    """回滚：删除 video_comfyui_task_id 字段"""

    # 将数据迁移回 error_message（如果需要回滚）
    from sqlalchemy import text

    connection = op.get_bind()
    connection.execute(text("""
        UPDATE image_video_status
        SET error_message = 'comfyui_task_id:' || video_comfyui_task_id
        WHERE video_comfyui_task_id IS NOT NULL
    """))

    # 删除字段
    op.drop_column('image_video_status', 'video_comfyui_task_id')

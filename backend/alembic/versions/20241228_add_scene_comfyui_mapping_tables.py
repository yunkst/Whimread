"""add scene comfyui mapping tables

Revision ID: 20241228_add_scene_comfyui_mapping
Revises: 69a1dfa2484c
Create Date: 2024-12-28 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '20241228_comfyui_map'
down_revision = '69a1dfa2484c'
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
    if not _has_table('scene_comfyui_tasks'):
        # 全新库：目标遗留表从未存在，跳过本迁移的漂移操作
        return
    """创建 ComfyUI 映射表并清空旧的图片表."""

    # 创建 scene_comfyui_tasks 表
    op.create_table(
        'scene_comfyui_tasks',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('task_id', sa.String(length=255), nullable=False),
        sa.Column('comfyui_prompt_id', sa.String(length=255), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_scene_comfyui_tasks_task_id'), 'scene_comfyui_tasks', ['task_id'], unique=False)
    op.create_unique_constraint('unique_task_prompt', 'scene_comfyui_tasks', ['task_id', 'comfyui_prompt_id'])

    # 创建 scene_comfyui_images 表
    op.create_table(
        'scene_comfyui_images',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('comfyui_prompt_id', sa.String(length=255), nullable=False),
        sa.Column('images', sa.String(length=5000), nullable=False, server_default='[]'),
        sa.Column('status_fetched', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_scene_comfyui_images_comfyui_prompt_id'), 'scene_comfyui_images', ['comfyui_prompt_id'], unique=True)

    # 清空 scene_image_gallery 表数据（保留表结构以备后用）
    op.execute('TRUNCATE TABLE scene_image_gallery CASCADE')


def downgrade():
    """回滚：删除新表，恢复旧表数据（如果有备份）."""

    # 删除新创建的表
    op.drop_index(op.f('ix_scene_comfyui_images_comfyui_prompt_id'), table_name='scene_comfyui_images')
    op.drop_table('scene_comfyui_images')

    op.drop_constraint('unique_task_prompt', 'scene_comfyui_tasks')
    op.drop_index(op.f('ix_scene_comfyui_tasks_task_id'), table_name='scene_comfyui_tasks')
    op.drop_table('scene_comfyui_tasks')

    # 注意：scene_image_gallery 的数据无法恢复，除非有备份
    # 如果需要恢复，请从备份导入数据

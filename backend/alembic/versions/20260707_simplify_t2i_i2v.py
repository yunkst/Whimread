"""simplify_t2i_i2v: drop role/scene/video_status tables, create text2img_task, recreate image_to_video_task

Revision ID: 20260707_simplify_t2i_i2v
Revises: 87122bfc655a
Create Date: 2026-07-07

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20260707_simplify_t2i_i2v'
down_revision = '87122bfc655a'
branch_labels = None
depends_on = None


# 部分环境在推进版本号前已通过 Base.metadata.create_all() 手动建出简化版
# text2img_task, 这里把 drop/create 改成幂等, 避免 DuplicateTable 中断迁移.
# 旧业务表与旧版 image_to_video_task 的 schema 已彻底废弃, 存在则级联删除.
_DROP_TABLES = [
    'scene_comfyui_images',
    'scene_comfyui_tasks',
    'scene_image_gallery',
    'scene_illustration_tasks',
    'role_image_gallery',
    'role_card_tasks',
    'image_video_status',
    'image_to_video_task',
]


def _has_table(name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return inspector.has_table(name)


def upgrade() -> None:
    """Drop old business tables and create simplified t2i/i2v task tables (idempotent)."""
    # 旧业务表/旧版 image_to_video_task: 存在则级联删除
    for table_name in _DROP_TABLES:
        if _has_table(table_name):
            op.execute(f'DROP TABLE IF EXISTS "{table_name}" CASCADE')

    # 新 text2img_task: 若已存在(与目标结构一致)则保留, 否则按简化结构创建
    if not _has_table('text2img_task'):
        op.create_table(
            'text2img_task',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('prompt_id', sa.String(length=255), nullable=False),
            sa.Column('prompt', sa.Text(), nullable=False),
            sa.Column('model_name', sa.String(length=100), nullable=False),
            sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
            sa.Column('filename', sa.String(length=500), nullable=True),
            sa.Column('error_message', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=True),
            sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_text2img_task_prompt_id', 'text2img_task', ['prompt_id'], unique=True)

    # 新 image_to_video_task: 若不存在才创建
    if not _has_table('image_to_video_task'):
        op.create_table(
            'image_to_video_task',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('prompt_id', sa.String(length=255), nullable=False),
            sa.Column('prompt', sa.Text(), nullable=False),
            sa.Column('model_name', sa.String(length=100), nullable=False),
            sa.Column('image_filename', sa.String(length=255), nullable=True),
            sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
            sa.Column('video_filename', sa.String(length=500), nullable=True),
            sa.Column('error_message', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=True),
            sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_image_to_video_task_prompt_id', 'image_to_video_task', ['prompt_id'], unique=True)


def downgrade() -> None:
    """Downgrade is not supported for this destructive migration."""
    raise NotImplementedError("This migration drops tables with data. Downgrade is not supported.")

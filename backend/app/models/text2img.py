"""
文生图与图生视频任务模型.

本模块包含文生图(Text2ImgTask)和图生视频(ImageToVideoTask)的数据库模型。
两者统一以 ComfyUI 的 prompt_id 作为对外任务标识(task_id)。
"""

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from ..database import Base


class Text2ImgTask(Base):
    """文生图任务模型."""

    __tablename__ = "text2img_task"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, comment="主键ID")
    prompt_id: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        nullable=False,
        index=True,
        comment="ComfyUI prompt_id, 对外即 task_id",
    )
    prompt: Mapped[str] = mapped_column(
        Text, nullable=False, comment="用户提供的提示词"
    )
    negative_prompt: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        comment="用户提供的负向提示词（可选；工作流不支持时静默忽略）",
    )
    model_name: Mapped[str] = mapped_column(
        String(100), nullable=False, comment="使用的模型名称"
    )
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="pending",
        comment="任务状态: pending/completed/failed",
    )
    filename: Mapped[str | None] = mapped_column(
        String(500), nullable=True, comment="生成成功后的图片文件名"
    )
    error_message: Mapped[str | None] = mapped_column(
        Text, nullable=True, comment="错误信息"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), comment="创建时间"
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, comment="完成时间"
    )

    def __repr__(self) -> str:
        return f"<Text2ImgTask(prompt_id='{self.prompt_id}', status='{self.status}')>"


class ImageToVideoTask(Base):
    """图生视频任务模型."""

    __tablename__ = "image_to_video_task"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, comment="主键ID")
    prompt_id: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        nullable=False,
        index=True,
        comment="ComfyUI prompt_id, 对外即 task_id",
    )
    prompt: Mapped[str] = mapped_column(
        Text, nullable=False, comment="用户提供的视频提示词"
    )
    model_name: Mapped[str] = mapped_column(
        String(100), nullable=False, comment="使用的图生视频模型名称"
    )
    image_filename: Mapped[str | None] = mapped_column(
        String(255), nullable=True, comment="上传到 ComfyUI 的图片文件名"
    )
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="pending",
        comment="任务状态: pending/completed/failed",
    )
    video_filename: Mapped[str | None] = mapped_column(
        String(500),
        nullable=True,
        comment="生成成功后的视频文件名(可含 subfolder/filename)",
    )
    error_message: Mapped[str | None] = mapped_column(
        Text, nullable=True, comment="错误信息"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), comment="创建时间"
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, comment="完成时间"
    )

    def __repr__(self) -> str:
        return (
            f"<ImageToVideoTask(prompt_id='{self.prompt_id}', status='{self.status}')>"
        )

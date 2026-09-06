#!/usr/bin/env python3
"""
UsageLog model — API 用量审计。

每次 LLM 代理调用（无论成败）落一行，是用量审计的核心表：
谁（device）、什么时候、用什么模型、消耗多少 token 与额度、结果如何。
"""

from datetime import UTC, datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ..database import Base


class UsageLog(Base):
    """LLM 代理调用审计表"""

    __tablename__ = "usage_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[int] = mapped_column(
        ForeignKey("devices.id", ondelete="CASCADE"), nullable=False, index=True
    )
    endpoint: Mapped[str] = mapped_column(
        String(64), nullable=False, default="/v1/chat/completions"
    )
    # 实际转发到上游的模型名（服务端覆写后的）
    model: Mapped[str] = mapped_column(String(128), nullable=False, default="")
    prompt_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    completion_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # 本次调用扣减的额度点数（失败/拒绝为 0）
    quota_cost: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # ok / insufficient_quota / upstream_error / interrupted
    status: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    error: Mapped[str | None] = mapped_column(String(512), nullable=True)
    latency_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=lambda: datetime.now(UTC)
    )

    __table_args__ = (
        Index("idx_usage_device_created", "device_id", "created_at"),
        Index("idx_usage_status_created", "status", "created_at"),
    )

    def __repr__(self):
        return (
            f"<UsageLog(id={self.id}, device_id={self.device_id}, "
            f"model={self.model}, quota_cost={self.quota_cost}, status={self.status})>"
        )
